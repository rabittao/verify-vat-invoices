from __future__ import annotations

import json
import logging
import math
import os
import shutil
import subprocess
import sys
import uuid
from inspect import signature
from datetime import date, datetime, timezone
from pathlib import Path
from typing import Any, Callable, Iterable

from openpyxl import Workbook
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.cidfonts import UnicodeCIDFont
from reportlab.pdfgen import canvas
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.config import AppSettings, load_local_env_file
from app.database import session_scope, utcnow
from app.models import Export, Invoice, SystemSetting, User, VerificationJob, VerificationJobItem
from app.schemas import Pagination
from app.security import hash_password, verify_password

logger = logging.getLogger(__name__)


OPENROUTER_CAPTCHA_MODEL_DEFAULT = "google/gemini-3-flash-preview"
QWEN_INVOICE_MODEL_DEFAULT = "qwen3.5-plus"
SYSTEM_SETTING_KEYS = {
    "QWEN_API_KEY": True,
    "QWEN_INVOICE_MODEL": False,
    "OPENROUTER_API_KEY": True,
    "OPENROUTER_CAPTCHA_MODEL": False,
}
LEDGER_AVAILABLE_COLUMNS = [
    "invoice_number",
    "invoice_date",
    "total_amount",
    "seller_name",
    "buyer_name",
    "last_verified_at",
    "invoice_type",
    "source_job",
]
LEDGER_DEFAULT_COLUMNS = [
    "invoice_number",
    "invoice_date",
    "total_amount",
    "seller_name",
    "buyer_name",
    "last_verified_at",
]
TASK_TIMELINE = [
    ("uploaded", "已上传"),
    ("extracting", "抽取中"),
    ("verifying", "核验中"),
    ("persisting", "入库中"),
    ("completed", "完成"),
]


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def parse_json(value: str | None, default: Any) -> Any:
    if not value:
        return default
    return json.loads(value)


def json_text(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False)


def mask_secret(value: str | None) -> str | None:
    if not value:
        return None
    if len(value) <= 8:
        return "*" * len(value)
    return f"{value[:4]}{'*' * max(len(value) - 8, 4)}{value[-4:]}"


def parse_datetime(value: str | None) -> datetime | None:
    if not value:
        return None
    return datetime.fromisoformat(value)


def humanize_status(extraction_status: str | None, verification_status: str | None, verification_message: str | None) -> tuple[str, str | None]:
    if verification_status == "success":
        return "核验成功", None
    if verification_status == "data_mismatch":
        return "信息不一致", "税站返回查无此票或信息不一致"
    if verification_status == "captcha_error":
        return "验证码失败", "验证码识别或提交失败"
    if verification_status == "daily_limit_exceeded":
        return "次数超限", "该发票当日查验次数已超限"
    if verification_status == "website_system_error":
        return "税站异常", "税站返回系统异常，请稍后重试"
    if verification_status == "verification_form_not_activated":
        return "表单未激活", "税站查验表单未正确激活"
    if verification_status == "script_error":
        return "脚本异常", "自动核验脚本异常"
    if verification_status == "skipped" and extraction_status == "missing_fields":
        return "字段缺失", "缺少关键字段，未进入税站核验"
    if verification_status == "skipped" and extraction_status == "no_invoice_detected":
        return "未识别到发票", "当前页面未识别到增值税发票"
    if extraction_status == "failed":
        return "抽取失败", "发票抽取阶段失败"
    if verification_status == "skipped":
        return "已跳过", verification_message or "当前记录未进入税站核验"
    return "处理中", verification_message


def compute_progress(stage: str, status: str) -> int:
    if stage == "uploaded":
        return 0
    if stage == "extracting":
        return 20
    if stage == "verifying":
        return 65
    if stage == "persisting":
        return 85
    if stage == "completed":
        return 100
    if status == "failed":
        return 100
    return 0


def paginate(total: int, page: int, page_size: int) -> Pagination:
    total_pages = math.ceil(total / page_size) if total else 0
    return Pagination(
        page=page,
        page_size=page_size,
        total=total,
        total_pages=total_pages,
        has_next=page < total_pages,
        has_prev=page > 1 and total_pages > 0,
    )


def source_files_for_job(job: VerificationJob) -> list[dict[str, Any]]:
    return parse_json(job.source_files_json, [])


def source_file_lookup(job: VerificationJob) -> dict[str, dict[str, Any]]:
    files = source_files_for_job(job)
    return {entry["relative_path"]: entry for entry in files}


def get_job_delete_block_reason(session: Session, job: VerificationJob) -> str | None:
    if job.stage != "completed":
        return "仅支持删除已完成任务"

    job_items = session.scalars(select(VerificationJobItem).where(VerificationJobItem.job_id == job.id)).all()
    job_item_ids = [item.id for item in job_items]
    referenced_invoices = session.scalars(
        select(Invoice).where(
            (Invoice.latest_job_id == job.id) | (Invoice.latest_job_item_id.in_(job_item_ids))
        )
    ).all() if job_item_ids else session.scalars(select(Invoice).where(Invoice.latest_job_id == job.id)).all()

    for invoice in referenced_invoices:
        alternate_item = session.scalar(
            select(VerificationJobItem)
            .join(VerificationJob, VerificationJob.id == VerificationJobItem.job_id)
            .where(
                VerificationJobItem.invoice_key == invoice.invoice_key,
                VerificationJobItem.verification_status == "success",
                VerificationJobItem.id != invoice.latest_job_item_id,
                VerificationJobItem.job_id != job.id,
                VerificationJob.stage == "completed",
            )
            .order_by(VerificationJobItem.verified_at.desc(), VerificationJobItem.id.desc())
        )
        if alternate_item is None:
            return f"该任务仍是台账发票 {invoice.invoice_number} 的唯一成功来源"
    return None


def build_task_card(session: Session, job: VerificationJob) -> dict[str, Any]:
    files = source_files_for_job(job)
    delete_block_reason = get_job_delete_block_reason(session, job)
    return {
        "job_id": job.job_uuid,
        "status": job.status,
        "stage": job.stage,
        "progress_percent": job.progress_percent,
        "source_file_count": len(files),
        "total_records": job.total_records,
        "success_count": job.success_count,
        "failed_count": job.failed_count,
        "skipped_count": job.skipped_count,
        "created_at": job.created_at,
        "updated_at": job.updated_at,
        "finished_at": job.finished_at,
        "display_title": f"{len(files)}个PDF，{job.total_records}条记录",
        "source_files": [{"file_name": entry["original_name"]} for entry in files],
        "deletable": delete_block_reason is None,
        "delete_block_reason": delete_block_reason,
    }


def ensure_admin_user(session: Session, settings: AppSettings) -> None:
    existing = session.scalar(select(User).where(User.username == settings.admin_username))
    if existing:
        return
    if settings.admin_password_generated:
        logger.warning(
            "APP_ADMIN_PASSWORD 未配置，已为首次初始化管理员账户生成临时随机密码。"
            " 请立即在 .env 或系统配置中设置固定密码。username=%s generated_password=%s",
            settings.admin_username,
            settings.admin_password,
        )
    session.add(
        User(
            username=settings.admin_username,
            password_hash=hash_password(settings.admin_password),
            role="admin",
            display_name="系统管理员",
            is_active=True,
        )
    )


def authenticate_user(session: Session, username: str, password: str) -> User | None:
    user = session.scalar(select(User).where(User.username == username))
    if not user or not user.is_active:
        return None
    if not verify_password(password, user.password_hash):
        return None
    return user


def get_setting_map(session: Session) -> dict[str, str]:
    rows = session.scalars(select(SystemSetting)).all()
    result: dict[str, str] = {}
    for row in rows:
        if row.setting_value is not None:
            result[row.setting_key] = row.setting_value
    return result


def build_pipeline_env(session: Session, settings: AppSettings) -> dict[str, str]:
    env = os.environ.copy()
    env_file_values = load_local_env_file(settings.env_file_path)
    for key, value in env_file_values.items():
        env.setdefault(key, value)
    for key, value in get_setting_map(session).items():
        env[key] = value
    env.setdefault("OPENROUTER_CAPTCHA_MODEL", OPENROUTER_CAPTCHA_MODEL_DEFAULT)
    return env


def get_system_config(session: Session, settings: AppSettings) -> dict[str, Any]:
    env = build_pipeline_env(session, settings)
    return {
        "qwen_api_key": {
            "is_configured": bool(env.get("QWEN_API_KEY")),
            "masked_value": mask_secret(env.get("QWEN_API_KEY")),
        },
        "qwen_invoice_model": env.get("QWEN_INVOICE_MODEL", QWEN_INVOICE_MODEL_DEFAULT),
        "openrouter_api_key": {
            "is_configured": bool(env.get("OPENROUTER_API_KEY")),
            "masked_value": mask_secret(env.get("OPENROUTER_API_KEY")),
        },
        "openrouter_captcha_model": env.get("OPENROUTER_CAPTCHA_MODEL", OPENROUTER_CAPTCHA_MODEL_DEFAULT),
    }


def update_system_config(session: Session, user: User, updates: dict[str, str | None]) -> None:
    for key, is_sensitive in SYSTEM_SETTING_KEYS.items():
        if key not in updates:
            continue
        value = updates[key]
        row = session.scalar(select(SystemSetting).where(SystemSetting.setting_key == key))
        if row is None:
            row = SystemSetting(setting_key=key, is_sensitive=is_sensitive, updated_by_user_id=user.id)
            session.add(row)
        row.setting_value = value or None
        row.updated_by_user_id = user.id


def validate_system_config(session: Session, settings: AppSettings) -> list[dict[str, Any]]:
    env = build_pipeline_env(session, settings)
    results = []
    for key in ("QWEN_API_KEY", "QWEN_INVOICE_MODEL", "OPENROUTER_API_KEY", "OPENROUTER_CAPTCHA_MODEL"):
        value = env.get(key)
        ok = bool(value)
        message = "已配置" if ok else "未配置"
        if key == "QWEN_INVOICE_MODEL" and ok:
            message = f"当前模型：{value}"
        if key == "OPENROUTER_CAPTCHA_MODEL" and ok:
            message = f"当前模型：{value}"
        results.append({"key": key, "ok": ok, "message": message})
    return results


def sanitize_filename(name: str) -> str:
    safe = "".join(ch if ch.isalnum() or ch in {"-", "_", "."} else "_" for ch in name)
    return safe or "upload.pdf"


def create_job(
    session: Session,
    settings: AppSettings,
    user: User,
    uploads: list[dict[str, Any]],
) -> VerificationJob:
    job_uuid = f"job_{datetime.now().strftime('%Y%m%d_%H%M%S')}_{uuid.uuid4().hex[:6]}"
    uploads_dir = settings.uploads_dir / job_uuid
    output_root = settings.jobs_dir / job_uuid
    uploads_dir.mkdir(parents=True, exist_ok=True)
    output_root.mkdir(parents=True, exist_ok=True)
    source_files = []
    for index, upload in enumerate(uploads, start=1):
        original_name = upload["filename"]
        safe_name = sanitize_filename(original_name)
        relative_path = f"{index:02d}_{safe_name}"
        file_path = uploads_dir / relative_path
        file_path.write_bytes(upload["content"])
        source_files.append(
            {
                "file_id": f"file_{index:03d}",
                "original_name": original_name,
                "relative_path": relative_path,
                "stored_path": str(file_path),
                "size_bytes": len(upload["content"]),
            }
        )
    job = VerificationJob(
        job_uuid=job_uuid,
        created_by_user_id=user.id,
        source_files_json=json_text(source_files),
        uploads_dir=str(uploads_dir),
        output_root_path=str(output_root),
        status="queued",
        stage="uploaded",
        progress_percent=0,
    )
    session.add(job)
    session.flush()
    return job


def create_retry_job(session: Session, settings: AppSettings, user: User, original_job: VerificationJob, file_id: str) -> VerificationJob:
    source_files = source_files_for_job(original_job)
    selected = next((entry for entry in source_files if entry["file_id"] == file_id), None)
    if selected is None:
        raise ValueError("指定文件不存在")
    content = Path(selected["stored_path"]).read_bytes()
    return create_job(
        session=session,
        settings=settings,
        user=user,
        uploads=[{"filename": selected["original_name"], "content": content}],
    )


def set_job_state(session: Session, job: VerificationJob, *, status: str | None = None, stage: str | None = None, error_message: str | None = None) -> None:
    if status is not None:
        job.status = status
    if stage is not None:
        job.stage = stage
        job.progress_percent = compute_progress(stage, job.status)
    if error_message is not None:
        job.error_message = error_message


def build_verification_fallback(extracted_json: Path, verified_json: Path, message: str) -> None:
    extracted_payload = json.loads(extracted_json.read_text(encoding="utf-8"))
    results_by_key = {}
    for record in extracted_payload.get("records", []):
        invoice_key = record.get("invoice_key") or record.get("record_id")
        if invoice_key in results_by_key:
            continue
        results_by_key[invoice_key] = {
            "invoice_key": record.get("invoice_key"),
            "verification_status": "script_error",
            "verification_message": message,
            "captcha_attempts": 0,
            "verified_at": now_iso(),
            "result_screenshot": None,
            "result_text": None,
        }
    verified_json.write_text(
        json.dumps(
            {
                "generated_at": now_iso(),
                "source_file": str(extracted_json),
                "results_by_key": results_by_key,
            },
            ensure_ascii=False,
            indent=2,
        ),
        encoding="utf-8",
    )


def _trim_output(value: str | None, limit: int = 4000) -> str:
    if not value:
        return ""
    if len(value) <= limit:
        return value.strip()
    return f"{value[-limit:].strip()}\n... <trimmed to last {limit} chars>"


def write_process_log(log_path: Path, title: str, result: subprocess.CompletedProcess[str]) -> None:
    log_path.parent.mkdir(parents=True, exist_ok=True)
    with log_path.open("a", encoding="utf-8") as handle:
        handle.write(f"\n===== {title} =====\n")
        handle.write(f"returncode: {result.returncode}\n")
        handle.write("\n--- stdout ---\n")
        handle.write(result.stdout or "")
        handle.write("\n--- stderr ---\n")
        handle.write(result.stderr or "")
        handle.write("\n")


def run_command(command: list[str], cwd: Path, env: dict[str, str], *, log_path: Path | None = None, label: str = "command") -> subprocess.CompletedProcess[str]:
    safe_command = " ".join(command)
    logger.info("Running %s: %s", label, safe_command)
    result = subprocess.run(command, cwd=cwd, text=True, capture_output=True, check=False, env=env)
    if log_path is not None:
        write_process_log(log_path, label, result)
    if result.stdout:
        logger.info("%s stdout:\n%s", label, _trim_output(result.stdout))
    if result.stderr:
        logger.warning("%s stderr:\n%s", label, _trim_output(result.stderr))
    logger.info("%s finished with returncode=%s", label, result.returncode)
    return result


def execute_invoice_pipeline(
    settings: AppSettings,
    env: dict[str, str],
    input_dir: Path,
    output_root: Path,
    on_stage_change: Callable[[str], None] | None = None,
) -> tuple[Path, Path]:
    scripts_dir = settings.root_dir / "scripts"
    artifacts_root = output_root / "artifacts"
    intermediate_dir = artifacts_root / "intermediate"
    rendered_dir = artifacts_root / "rendered"
    playwright_dir = artifacts_root / "playwright"
    intermediate_dir.mkdir(parents=True, exist_ok=True)
    rendered_dir.mkdir(parents=True, exist_ok=True)
    playwright_dir.mkdir(parents=True, exist_ok=True)
    extracted_json = intermediate_dir / "extracted.json"
    verified_json = intermediate_dir / "verified.json"
    pipeline_log = output_root / "pipeline.log"
    logger.info("Pipeline started: input_dir=%s output_root=%s log=%s", input_dir, output_root, pipeline_log)

    extract_cmd = [
        sys.executable,
        str(scripts_dir / "extract_invoices.py"),
        "--input-dir",
        str(input_dir),
        "--output-json",
        str(extracted_json),
        "--render-dir",
        str(rendered_dir),
    ]
    extraction = run_command(extract_cmd, cwd=settings.root_dir, env=env, log_path=pipeline_log, label="extract_invoices")
    if extraction.returncode != 0:
        message = (extraction.stderr or extraction.stdout).strip() or "invoice extraction failed"
        logger.error("Extraction failed: %s", _trim_output(message))
        raise RuntimeError(message)
    logger.info("Extraction completed: %s", extracted_json)
    if on_stage_change is not None:
        on_stage_change("verifying")

    verify_cmd = [
        "node",
        str(scripts_dir / "verify_invoices.js"),
        "--input-json",
        str(extracted_json),
        "--output-json",
        str(verified_json),
        "--artifacts-dir",
        str(playwright_dir),
    ]
    verification = run_command(verify_cmd, cwd=settings.root_dir, env=env, log_path=pipeline_log, label="verify_invoices")
    if verification.returncode != 0:
        message = (verification.stderr or verification.stdout).strip() or "verification script failed"
        logger.error("Verification failed; writing fallback results: %s", _trim_output(message))
        build_verification_fallback(extracted_json, verified_json, message)
    else:
        logger.info("Verification completed: %s", verified_json)
    return extracted_json, verified_json


def determine_job_status(success_count: int, failed_count: int, skipped_count: int) -> str:
    if failed_count == 0 and skipped_count == 0:
        return "succeeded"
    if success_count == 0 and failed_count > 0 and skipped_count == 0:
        return "failed"
    return "partially_failed"


def parse_verified_timestamp(value: str | None) -> datetime | None:
    if not value:
        return None
    return datetime.fromisoformat(value)


def upsert_invoice(session: Session, job: VerificationJob, item: VerificationJobItem) -> None:
    if not item.invoice_key or item.verification_status != "success" or not item.verified_at:
        return
    existing = session.scalar(select(Invoice).where(Invoice.invoice_key == item.invoice_key))
    if existing is None:
        session.add(
            Invoice(
                invoice_key=item.invoice_key,
                latest_job_id=job.id,
                latest_job_item_id=item.id,
                invoice_type=item.invoice_type,
                invoice_code=item.invoice_code,
                invoice_number=item.invoice_number or "",
                invoice_date=item.invoice_date or "",
                pretax_amount=item.pretax_amount or "",
                tax_amount=item.tax_amount,
                total_amount=item.total_amount,
                seller_name=item.seller_name,
                buyer_name=item.buyer_name,
                check_code=item.check_code,
                verification_status=item.verification_status,
                verification_message=item.verification_message,
                verification_amount_type=item.verification_amount_type,
                verification_amount_used=item.verification_amount_used,
                verified_at=item.verified_at,
                source_pdf=item.source_pdf,
                page_number=item.page_number,
                result_screenshot_path=item.verify_screenshot_path,
                first_verified_at=item.verified_at,
                last_verified_at=item.verified_at,
            )
        )
        return
    existing.latest_job_id = job.id
    existing.latest_job_item_id = item.id
    existing.invoice_type = item.invoice_type
    existing.invoice_code = item.invoice_code
    existing.invoice_number = item.invoice_number or existing.invoice_number
    existing.invoice_date = item.invoice_date or existing.invoice_date
    existing.pretax_amount = item.pretax_amount or existing.pretax_amount
    existing.tax_amount = item.tax_amount
    existing.total_amount = item.total_amount
    existing.seller_name = item.seller_name
    existing.buyer_name = item.buyer_name
    existing.check_code = item.check_code
    existing.verification_status = item.verification_status
    existing.verification_message = item.verification_message
    existing.verification_amount_type = item.verification_amount_type
    existing.verification_amount_used = item.verification_amount_used
    existing.verified_at = item.verified_at
    existing.source_pdf = item.source_pdf
    existing.page_number = item.page_number
    existing.result_screenshot_path = item.verify_screenshot_path
    existing.last_verified_at = item.verified_at


def _apply_invoice_from_item(invoice: Invoice, job: VerificationJob, item: VerificationJobItem) -> None:
    invoice.latest_job_id = job.id
    invoice.latest_job_item_id = item.id
    invoice.invoice_type = item.invoice_type
    invoice.invoice_code = item.invoice_code
    invoice.invoice_number = item.invoice_number or invoice.invoice_number
    invoice.invoice_date = item.invoice_date or invoice.invoice_date
    invoice.pretax_amount = item.pretax_amount or invoice.pretax_amount
    invoice.tax_amount = item.tax_amount
    invoice.total_amount = item.total_amount
    invoice.seller_name = item.seller_name
    invoice.buyer_name = item.buyer_name
    invoice.check_code = item.check_code
    invoice.verification_status = item.verification_status or invoice.verification_status
    invoice.verification_message = item.verification_message
    invoice.verification_amount_type = item.verification_amount_type
    invoice.verification_amount_used = item.verification_amount_used
    if item.verified_at is not None:
        invoice.verified_at = item.verified_at
        invoice.last_verified_at = item.verified_at
    invoice.source_pdf = item.source_pdf
    invoice.page_number = item.page_number
    invoice.result_screenshot_path = item.verify_screenshot_path


def delete_completed_job(session: Session, job_uuid: str) -> None:
    job = session.scalar(select(VerificationJob).where(VerificationJob.job_uuid == job_uuid))
    if job is None:
        raise ValueError("任务不存在")
    delete_block_reason = get_job_delete_block_reason(session, job)
    if delete_block_reason is not None:
        raise ValueError(delete_block_reason)

    job_items = session.scalars(select(VerificationJobItem).where(VerificationJobItem.job_id == job.id)).all()
    job_item_ids = {item.id for item in job_items}

    referenced_invoices = session.scalars(
        select(Invoice).where(
            (Invoice.latest_job_id == job.id) | (Invoice.latest_job_item_id.in_(job_item_ids))
        )
    ).all() if job_item_ids else session.scalars(select(Invoice).where(Invoice.latest_job_id == job.id)).all()

    for invoice in referenced_invoices:
        alternate_item = session.scalar(
            select(VerificationJobItem)
            .join(VerificationJob, VerificationJob.id == VerificationJobItem.job_id)
            .where(
                VerificationJobItem.invoice_key == invoice.invoice_key,
                VerificationJobItem.verification_status == "success",
                VerificationJobItem.id != invoice.latest_job_item_id,
                VerificationJobItem.job_id != job.id,
                VerificationJob.stage == "completed",
            )
            .order_by(VerificationJobItem.verified_at.desc(), VerificationJobItem.id.desc())
        )
        if alternate_item is None:
            raise ValueError(f"任务 {job_uuid} 仍是台账发票 {invoice.invoice_number} 的唯一成功来源，不能删除")
        alternate_job = session.get(VerificationJob, alternate_item.job_id)
        if alternate_job is None:
            raise ValueError("备用任务不存在，无法删除当前任务")
        _apply_invoice_from_item(invoice, alternate_job, alternate_item)

    for item in job_items:
        session.delete(item)
    session.delete(job)


def persist_pipeline_results(session: Session, job: VerificationJob, extracted_json: Path, verified_json: Path) -> None:
    logger.info("Persisting pipeline results: job=%s extracted=%s verified=%s", job.job_uuid, extracted_json, verified_json)
    lookup = source_file_lookup(job)
    extracted_payload = json.loads(extracted_json.read_text(encoding="utf-8"))
    verified_payload = json.loads(verified_json.read_text(encoding="utf-8"))
    existing_items = session.scalars(select(VerificationJobItem).where(VerificationJobItem.job_id == job.id)).all()
    for item in existing_items:
        session.delete(item)
    session.flush()

    items_by_invoice_key: dict[str, list[VerificationJobItem]] = {}
    items_by_record_id: dict[str, VerificationJobItem] = {}
    for record in extracted_payload.get("records", []):
        source_pdf = record.get("source_pdf")
        file_meta = lookup.get(source_pdf or "", {})
        item = VerificationJobItem(
            job_id=job.id,
            record_id=record.get("record_id"),
            invoice_key=record.get("invoice_key"),
            file_id=file_meta.get("file_id"),
            source_pdf=source_pdf,
            page_number=record.get("page_number"),
            invoice_index=record.get("invoice_index"),
            invoice_type=record.get("invoice_type"),
            invoice_code=record.get("invoice_code"),
            invoice_number=record.get("invoice_number"),
            invoice_date=record.get("invoice_date"),
            pretax_amount=record.get("pretax_amount"),
            tax_amount=record.get("tax_amount"),
            total_amount=record.get("total_amount"),
            seller_name=record.get("seller_name"),
            buyer_name=record.get("buyer_name"),
            check_code=record.get("check_code"),
            extraction_status=record.get("extraction_status"),
            extraction_message=record.get("extraction_message"),
            extraction_method=record.get("extraction_method"),
            validation_status=record.get("validation_status"),
            validation_errors_json=json_text(record.get("validation_errors") or []),
            validation_warnings_json=json_text(record.get("validation_warnings") or []),
            needs_verification=bool(record.get("needs_verification")),
            extract_screenshot_path=record.get("result_screenshot"),
            raw_extracted_json=json_text(record),
        )
        session.add(item)
        session.flush()
        if item.invoice_key:
            items_by_invoice_key.setdefault(item.invoice_key, []).append(item)
        if item.record_id:
            items_by_record_id[item.record_id] = item

    for key, result in (verified_payload.get("results_by_key") or {}).items():
        targets = items_by_invoice_key.get(key) or ([items_by_record_id[key]] if key in items_by_record_id else [])
        for item in targets:
            item.verification_status = result.get("verification_status")
            item.verification_message = result.get("verification_message")
            item.verification_amount_type = result.get("verification_amount_type")
            item.verification_amount_used = result.get("verification_amount_used")
            item.captcha_attempts = result.get("captcha_attempts")
            item.verified_at = parse_verified_timestamp(result.get("verified_at")) or utcnow()
            item.verify_screenshot_path = result.get("result_screenshot")
            item.result_text = result.get("result_text")
            item.raw_verified_json = json_text(result)

    all_items = session.scalars(select(VerificationJobItem).where(VerificationJobItem.job_id == job.id)).all()
    success_count = 0
    failed_count = 0
    skipped_count = 0
    for item in all_items:
        if item.verification_status == "success":
            success_count += 1
            upsert_invoice(session, job, item)
        elif item.verification_status in {
            "data_mismatch",
            "captcha_error",
            "website_system_error",
            "script_error",
            "verification_form_not_activated",
            "daily_limit_exceeded",
        } or item.extraction_status == "failed":
            failed_count += 1
        else:
            skipped_count += 1
    job.total_records = len(all_items)
    job.success_count = success_count
    job.failed_count = failed_count
    job.skipped_count = skipped_count
    job.status = determine_job_status(success_count, failed_count, skipped_count)
    job.stage = "completed"
    job.progress_percent = 100
    job.finished_at = utcnow()
    job.error_message = None
    logger.info(
        "Job persisted: job=%s status=%s total=%s success=%s failed=%s skipped=%s",
        job.job_uuid,
        job.status,
        job.total_records,
        job.success_count,
        job.failed_count,
        job.skipped_count,
    )


def process_job(job_uuid: str, session_factory, settings: AppSettings) -> None:
    logger.info("Job processing started: %s", job_uuid)
    with session_scope(session_factory) as session:
        job = session.scalar(select(VerificationJob).where(VerificationJob.job_uuid == job_uuid))
        if job is None:
            raise ValueError("job not found")
        set_job_state(session, job, status="running", stage="extracting")
        if job.started_at is None:
            job.started_at = utcnow()
        logger.info("Job stage changed: job=%s stage=extracting progress=%s", job_uuid, job.progress_percent)

    try:
        def update_stage(stage: str) -> None:
            with session_scope(session_factory) as stage_session:
                stage_job = stage_session.scalar(select(VerificationJob).where(VerificationJob.job_uuid == job_uuid))
                if stage_job is not None:
                    set_job_state(stage_session, stage_job, status="running", stage=stage)
                    logger.info("Job stage changed: job=%s stage=%s progress=%s", job_uuid, stage, stage_job.progress_percent)

        with session_scope(session_factory) as session:
            job = session.scalar(select(VerificationJob).where(VerificationJob.job_uuid == job_uuid))
            assert job is not None
            env = build_pipeline_env(session, settings)
            uploads_dir = Path(job.uploads_dir)
            output_root = Path(job.output_root_path)
            if "on_stage_change" in signature(execute_invoice_pipeline).parameters:
                extracted_json, verified_json = execute_invoice_pipeline(
                    settings,
                    env,
                    uploads_dir,
                    output_root,
                    on_stage_change=update_stage,
                )
            else:
                extracted_json, verified_json = execute_invoice_pipeline(settings, env, uploads_dir, output_root)
            set_job_state(session, job, status="running", stage="persisting")
            logger.info("Job stage changed: job=%s stage=persisting progress=%s", job_uuid, job.progress_percent)
            persist_pipeline_results(session, job, extracted_json, verified_json)
            logger.info("Job processing finished: %s", job_uuid)
    except Exception as exc:
        logger.exception("Job processing failed: %s", job_uuid)
        with session_scope(session_factory) as session:
            job = session.scalar(select(VerificationJob).where(VerificationJob.job_uuid == job_uuid))
            if job is None:
                return
            job.status = "failed"
            job.stage = "completed"
            job.progress_percent = 100
            job.finished_at = utcnow()
            job.error_message = str(exc)


def list_jobs(session: Session, completed_page: int, completed_page_size: int) -> dict[str, Any]:
    running_jobs = session.scalars(
        select(VerificationJob)
        .where(VerificationJob.status.in_(["queued", "running"]))
        .order_by(VerificationJob.created_at.desc())
    ).all()
    completed_total = session.scalar(
        select(func.count()).select_from(VerificationJob).where(VerificationJob.status.in_(["succeeded", "partially_failed", "failed"]))
    ) or 0
    completed_jobs = session.scalars(
        select(VerificationJob)
        .where(VerificationJob.status.in_(["succeeded", "partially_failed", "failed"]))
        .order_by(VerificationJob.created_at.desc())
        .offset((completed_page - 1) * completed_page_size)
        .limit(completed_page_size)
    ).all()
    return {
        "running_items": [build_task_card(session, job) for job in running_jobs],
        "completed_items": [build_task_card(session, job) for job in completed_jobs],
        "running_summary": {"count": len(running_jobs)},
        "completed_pagination": paginate(completed_total, completed_page, completed_page_size),
    }


def build_timeline(job: VerificationJob) -> list[dict[str, Any]]:
    current_index = next((index for index, (stage, _) in enumerate(TASK_TIMELINE) if stage == job.stage), len(TASK_TIMELINE) - 1)
    timeline = []
    for index, (stage, label) in enumerate(TASK_TIMELINE):
        done = index < current_index or (job.stage == "completed" and index <= current_index)
        timeline.append({"stage": stage, "label": label, "done": done, "current": stage == job.stage})
    return timeline


def get_job_detail(session: Session, job_uuid: str) -> dict[str, Any]:
    job = session.scalar(select(VerificationJob).where(VerificationJob.job_uuid == job_uuid))
    if job is None:
        raise ValueError("任务不存在")
    files = source_files_for_job(job)
    items = session.scalars(
        select(VerificationJobItem).where(VerificationJobItem.job_id == job.id).order_by(VerificationJobItem.id.asc())
    ).all()
    grouped: dict[str, dict[str, Any]] = {
        entry["file_id"]: {
            "file_id": entry["file_id"],
            "file_name": entry["original_name"],
            "source_pdf": entry["relative_path"],
            "record_count": 0,
            "success_count": 0,
            "failed_count": 0,
            "skipped_count": 0,
            "retryable": True,
            "items": [],
        }
        for entry in files
    }
    for item in items:
        file_group = grouped.setdefault(
            item.file_id or "unknown",
            {
                "file_id": item.file_id or "unknown",
                "file_name": item.source_pdf or "未知文件",
                "source_pdf": item.source_pdf or "unknown",
                "record_count": 0,
                "success_count": 0,
                "failed_count": 0,
                "skipped_count": 0,
                "retryable": True,
                "items": [],
            },
        )
        label, summary = humanize_status(item.extraction_status, item.verification_status, item.verification_message)
        status_key = item.verification_status or item.extraction_status or "pending"
        if status_key == "success":
            file_group["success_count"] += 1
        elif status_key in {"data_mismatch", "captcha_error", "website_system_error", "script_error", "verification_form_not_activated", "daily_limit_exceeded", "failed"}:
            file_group["failed_count"] += 1
        else:
            file_group["skipped_count"] += 1
        file_group["record_count"] += 1
        file_group["items"].append(
            {
                "job_item_id": item.id,
                "invoice_key": item.invoice_key,
                "invoice_number": item.invoice_number,
                "invoice_date": item.invoice_date,
                "amount": item.total_amount or item.pretax_amount,
                "status": status_key,
                "status_label": label,
                "failure_summary": summary,
            }
        )
    file_groups = []
    for group in grouped.values():
        if group["failed_count"] == 0 and group["skipped_count"] == 0:
            status = "succeeded"
        elif group["success_count"] == 0 and group["failed_count"] > 0 and group["skipped_count"] == 0:
            status = "failed"
        else:
            status = "partially_failed"
        group["status"] = status
        file_groups.append(group)
    return {
        "job_id": job.job_uuid,
        "status": job.status,
        "stage": job.stage,
        "progress_percent": job.progress_percent,
        "created_at": job.created_at,
        "started_at": job.started_at,
        "finished_at": job.finished_at,
        "timeline": build_timeline(job),
        "summary": {
            "source_file_count": len(files),
            "total_records": job.total_records,
            "success_count": job.success_count,
            "failed_count": job.failed_count,
            "skipped_count": job.skipped_count,
        },
        "file_groups": file_groups,
    }


def get_job_item_detail(session: Session, job_uuid: str, job_item_id: int) -> dict[str, Any]:
    job = session.scalar(select(VerificationJob).where(VerificationJob.job_uuid == job_uuid))
    if job is None:
        raise ValueError("任务不存在")
    item = session.scalar(
        select(VerificationJobItem).where(VerificationJobItem.job_id == job.id, VerificationJobItem.id == job_item_id)
    )
    if item is None:
        raise ValueError("任务明细不存在")
    _, human_summary = humanize_status(item.extraction_status, item.verification_status, item.verification_message)
    return {
        "job_item_id": item.id,
        "invoice_key": item.invoice_key,
        "basic_info": {
            "invoice_type": item.invoice_type,
            "invoice_code": item.invoice_code,
            "invoice_number": item.invoice_number,
            "invoice_date": item.invoice_date,
            "pretax_amount": item.pretax_amount,
            "tax_amount": item.tax_amount,
            "total_amount": item.total_amount,
            "seller_name": item.seller_name,
            "buyer_name": item.buyer_name,
            "check_code": item.check_code,
        },
        "processing_info": {
            "extraction_status": item.extraction_status,
            "extraction_message": item.extraction_message,
            "validation_status": item.validation_status,
            "verification_status": item.verification_status,
            "verification_message": item.verification_message,
            "human_summary": human_summary,
        },
        "evidence": {
            "extract_screenshot_url": f"/api/files/job-items/{item.id}/extract-screenshot" if item.extract_screenshot_path else None,
            "verify_screenshot_url": f"/api/files/job-items/{item.id}/verify-screenshot" if item.verify_screenshot_path else None,
        },
        "technical_details": {
            "result_text": item.result_text,
            "validation_errors": parse_json(item.validation_errors_json, []),
        },
    }


def apply_ledger_filters(query, *, invoice_number: str | None, date_from: date | None, date_to: date | None, seller_name: str | None, buyer_name: str | None):
    if invoice_number:
        query = query.where(Invoice.invoice_number.contains(invoice_number))
    if seller_name:
        query = query.where(Invoice.seller_name.contains(seller_name))
    if buyer_name:
        query = query.where(Invoice.buyer_name.contains(buyer_name))
    if date_from:
        query = query.where(Invoice.invoice_date >= date_from.isoformat())
    if date_to:
        query = query.where(Invoice.invoice_date <= date_to.isoformat())
    return query


def list_invoices(
    session: Session,
    *,
    page: int,
    page_size: int,
    invoice_number: str | None,
    date_from: date | None,
    date_to: date | None,
    seller_name: str | None,
    buyer_name: str | None,
    quick_range: str | None,
    sort_by: str,
    sort_order: str,
) -> dict[str, Any]:
    base_query = select(Invoice)
    base_query = apply_ledger_filters(
        base_query,
        invoice_number=invoice_number,
        date_from=date_from,
        date_to=date_to,
        seller_name=seller_name,
        buyer_name=buyer_name,
    )
    count_query = select(func.count()).select_from(Invoice)
    count_query = apply_ledger_filters(
        count_query,
        invoice_number=invoice_number,
        date_from=date_from,
        date_to=date_to,
        seller_name=seller_name,
        buyer_name=buyer_name,
    )
    sort_column = {
        "last_verified_at": Invoice.last_verified_at,
        "invoice_date": Invoice.invoice_date,
        "invoice_number": Invoice.invoice_number,
    }.get(sort_by, Invoice.last_verified_at)
    sort_expr = sort_column.desc() if sort_order != "asc" else sort_column.asc()
    total = session.scalar(count_query) or 0
    rows = session.scalars(base_query.order_by(sort_expr).offset((page - 1) * page_size).limit(page_size)).all()
    items = []
    for row in rows:
        items.append(
            {
                "invoice_id": row.id,
                "invoice_key": row.invoice_key,
                "invoice_type": row.invoice_type,
                "invoice_code": row.invoice_code,
                "invoice_number": row.invoice_number,
                "invoice_date": row.invoice_date,
                "pretax_amount": row.pretax_amount,
                "tax_amount": row.tax_amount,
                "total_amount": row.total_amount,
                "seller_name": row.seller_name,
                "buyer_name": row.buyer_name,
                "last_verified_at": row.last_verified_at,
                "source_job": {"job_id": session.scalar(select(VerificationJob.job_uuid).where(VerificationJob.id == row.latest_job_id)), "label": f"任务 {session.scalar(select(VerificationJob.job_uuid).where(VerificationJob.id == row.latest_job_id))}"},
                "has_screenshot": bool(row.result_screenshot_path),
            }
        )
    return {
        "filters": {
            "invoice_number": invoice_number,
            "date_from": date_from,
            "date_to": date_to,
            "seller_name": seller_name,
            "buyer_name": buyer_name,
            "quick_range": quick_range,
            "sort_by": sort_by,
            "sort_order": sort_order,
        },
        "items": items,
        "available_columns": LEDGER_AVAILABLE_COLUMNS,
        "default_columns": LEDGER_DEFAULT_COLUMNS,
        "pagination": paginate(total, page, page_size),
    }


def get_invoice_detail(session: Session, invoice_id: int) -> dict[str, Any]:
    invoice = session.get(Invoice, invoice_id)
    if invoice is None:
        raise ValueError("台账记录不存在")
    job_uuid = session.scalar(select(VerificationJob.job_uuid).where(VerificationJob.id == invoice.latest_job_id))
    return {
        "invoice_id": invoice.id,
        "screenshot": {
            "preview_url": f"/api/files/invoices/{invoice.id}/screenshot" if invoice.result_screenshot_path else None,
            "fullscreen_url": f"/api/files/invoices/{invoice.id}/screenshot" if invoice.result_screenshot_path else None,
        },
        "actions": {
            "export_detail_pdf_enabled": True,
            "view_source_job_enabled": True,
        },
        "source_job": {"job_id": job_uuid, "label": f"任务 {job_uuid}"} if job_uuid else None,
        "core_fields": {
            "invoice_number": invoice.invoice_number,
            "invoice_date": invoice.invoice_date,
            "invoice_type": invoice.invoice_type,
            "pretax_amount": invoice.pretax_amount,
            "tax_amount": invoice.tax_amount,
            "total_amount": invoice.total_amount,
        },
        "party_fields": {
            "seller_name": invoice.seller_name,
            "buyer_name": invoice.buyer_name,
        },
        "system_fields": {
            "verified_at": invoice.verified_at,
            "first_verified_at": invoice.first_verified_at,
            "last_verified_at": invoice.last_verified_at,
            "created_at": invoice.created_at,
            "updated_at": invoice.updated_at,
        },
    }


def create_export(session: Session, user: User, export_type: str, filters: dict[str, Any] | None, invoice_id: int | None) -> Export:
    export_uuid = f"exp_{datetime.now().strftime('%Y%m%d_%H%M%S')}_{uuid.uuid4().hex[:6]}"
    record = Export(
        export_uuid=export_uuid,
        created_by_user_id=user.id,
        export_type=export_type,
        status="queued",
        filters_json=json_text(filters or {}),
        invoice_id=invoice_id,
    )
    session.add(record)
    session.flush()
    return record


def _query_export_rows(session: Session, export: Export) -> list[Invoice]:
    filters = parse_json(export.filters_json, {})
    query = select(Invoice)
    query = apply_ledger_filters(
        query,
        invoice_number=filters.get("invoice_number"),
        date_from=date.fromisoformat(filters["date_from"]) if filters.get("date_from") else None,
        date_to=date.fromisoformat(filters["date_to"]) if filters.get("date_to") else None,
        seller_name=filters.get("seller_name"),
        buyer_name=filters.get("buyer_name"),
    )
    sort_by = filters.get("sort_by") or "last_verified_at"
    sort_order = filters.get("sort_order") or "desc"
    sort_column = {
        "last_verified_at": Invoice.last_verified_at,
        "invoice_date": Invoice.invoice_date,
        "invoice_number": Invoice.invoice_number,
    }.get(sort_by, Invoice.last_verified_at)
    sort_expr = sort_column.desc() if sort_order != "asc" else sort_column.asc()
    return session.scalars(query.order_by(sort_expr)).all()


def _register_chinese_font() -> str:
    font_name = "STSong-Light"
    try:
        pdfmetrics.getFont(font_name)
    except KeyError:
        pdfmetrics.registerFont(UnicodeCIDFont(font_name))
    return font_name


def export_invoice_list_excel(file_path: Path, invoices: Iterable[Invoice]) -> None:
    workbook = Workbook()
    sheet = workbook.active
    sheet.title = "Invoices"
    headers = ["发票号码", "开票日期", "发票类型", "税前金额", "税额", "价税合计", "销售方", "购买方", "最近核验时间"]
    sheet.append(headers)
    for row in invoices:
        sheet.append([
            row.invoice_number,
            row.invoice_date,
            row.invoice_type,
            row.pretax_amount,
            row.tax_amount,
            row.total_amount,
            row.seller_name,
            row.buyer_name,
            row.last_verified_at.isoformat(),
        ])
    workbook.save(file_path)


def export_invoice_list_summary_pdf(file_path: Path, invoices: Iterable[Invoice]) -> None:
    font_name = _register_chinese_font()
    pdf = canvas.Canvas(str(file_path), pagesize=A4)
    pdf.setFont(font_name, 10)
    pdf.drawString(20 * mm, 285 * mm, "发票台账汇总")
    y = 275 * mm
    for index, row in enumerate(invoices, start=1):
        pdf.drawString(15 * mm, y, f"{index}. {row.invoice_number} | {row.invoice_date} | {row.total_amount or row.pretax_amount} | {row.seller_name or '-'}")
        y -= 8 * mm
        if y < 20 * mm:
            pdf.showPage()
            pdf.setFont(font_name, 10)
            y = 280 * mm
    pdf.save()


def export_invoice_detail_pdf(file_path: Path, invoice: Invoice) -> None:
    font_name = _register_chinese_font()
    pdf = canvas.Canvas(str(file_path), pagesize=A4)
    pdf.setFont(font_name, 12)
    pdf.drawString(20 * mm, 285 * mm, "发票详情")
    pdf.setFont(font_name, 10)
    lines = [
        f"发票号码：{invoice.invoice_number}",
        f"开票日期：{invoice.invoice_date}",
        f"发票类型：{invoice.invoice_type or '-'}",
        f"税前金额：{invoice.pretax_amount}",
        f"税额：{invoice.tax_amount or '-'}",
        f"价税合计：{invoice.total_amount or '-'}",
        f"销售方：{invoice.seller_name or '-'}",
        f"购买方：{invoice.buyer_name or '-'}",
        f"最近核验时间：{invoice.last_verified_at.isoformat()}",
    ]
    y = 270 * mm
    for line in lines:
        pdf.drawString(20 * mm, y, line)
        y -= 10 * mm
    pdf.save()


def process_export(export_uuid: str, session_factory, settings: AppSettings) -> None:
    logger.info("Export processing started: %s", export_uuid)
    with session_scope(session_factory) as session:
        export = session.scalar(select(Export).where(Export.export_uuid == export_uuid))
        if export is None:
            raise ValueError("export not found")
        export.status = "running"
    try:
        with session_scope(session_factory) as session:
            export = session.scalar(select(Export).where(Export.export_uuid == export_uuid))
            assert export is not None
            target_dir = settings.exports_dir / export.export_uuid
            target_dir.mkdir(parents=True, exist_ok=True)
            if export.export_type == "invoice_list_excel":
                invoices = _query_export_rows(session, export)
                file_path = target_dir / "invoice-list.xlsx"
                export_invoice_list_excel(file_path, invoices)
            elif export.export_type == "invoice_list_summary_pdf":
                invoices = _query_export_rows(session, export)
                file_path = target_dir / "invoice-list-summary.pdf"
                export_invoice_list_summary_pdf(file_path, invoices)
            elif export.export_type == "invoice_detail_pdf":
                invoice = session.get(Invoice, export.invoice_id)
                if invoice is None:
                    raise ValueError("invoice not found")
                file_path = target_dir / f"invoice-{invoice.id}.pdf"
                export_invoice_detail_pdf(file_path, invoice)
            else:
                raise ValueError("unsupported export type")
            export.status = "completed"
            export.finished_at = utcnow()
            export.file_name = file_path.name
            export.file_path = str(file_path)
            export.file_size = file_path.stat().st_size
            export.error_message = None
            logger.info(
                "Export completed: export=%s type=%s file=%s size=%s",
                export_uuid,
                export.export_type,
                export.file_path,
                export.file_size,
            )
    except Exception as exc:
        logger.exception("Export processing failed: %s", export_uuid)
        with session_scope(session_factory) as session:
            export = session.scalar(select(Export).where(Export.export_uuid == export_uuid))
            if export is None:
                return
            export.status = "failed"
            export.finished_at = utcnow()
            export.error_message = str(exc)


def list_exports(session: Session, page: int, page_size: int) -> dict[str, Any]:
    total = session.scalar(select(func.count()).select_from(Export)) or 0
    rows = session.scalars(
        select(Export).order_by(Export.created_at.desc()).offset((page - 1) * page_size).limit(page_size)
    ).all()
    items = []
    for row in rows:
        items.append(
            {
                "export_id": row.export_uuid,
                "export_type": row.export_type,
                "status": row.status,
                "created_at": row.created_at,
                "finished_at": row.finished_at,
                "file_name": row.file_name,
                "file_size": row.file_size,
                "open_url": f"/api/files/exports/{row.export_uuid}/open" if row.file_path else None,
                "download_url": f"/api/files/exports/{row.export_uuid}/download" if row.file_path else None,
                "share_enabled": bool(row.file_path),
            }
        )
    return {"items": items, "pagination": paginate(total, page, page_size)}


def safe_resolve_path(path_value: str | None, base_dir: Path) -> Path:
    if not path_value:
        raise FileNotFoundError("file path missing")
    resolved = Path(path_value).expanduser().resolve()
    resolved_base_dir = base_dir.expanduser().resolve()
    if resolved_base_dir not in resolved.parents and resolved != resolved_base_dir:
        raise FileNotFoundError("invalid file path")
    if not resolved.exists():
        raise FileNotFoundError("file does not exist")
    return resolved
