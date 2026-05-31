from __future__ import annotations

import json
import subprocess
from datetime import datetime, timedelta, timezone

from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker

from app.config import AppSettings
from app.database import Base
from app.invoice_qr import parse_invoice_qr
from app.models import Export, Invoice, User, VerificationJob, VerificationJobItem
from app.security import hash_password
from app.services import (
    QR_INVOICE_SOURCE_FILE,
    build_invoice_info_cache_payload,
    build_qr_extracted_record,
    create_qr_invoice_job,
    create_retry_job,
    execute_qr_invoice_pipeline,
    list_exports,
    list_invoices,
    parse_verified_timestamp,
    persist_pipeline_results,
    prefer_modal_screenshot_path,
)


def build_session() -> Session:
    engine = create_engine(
        "sqlite:///:memory:",
        future=True,
        connect_args={"check_same_thread": False},
    )
    Base.metadata.create_all(bind=engine)
    factory = sessionmaker(bind=engine, autoflush=False, autocommit=False, expire_on_commit=False, class_=Session)
    return factory()


def seed_user(session: Session) -> User:
    user = User(
        username="tester",
        password_hash=hash_password("secret"),
        role="admin",
        display_name="Tester",
        is_active=True,
    )
    session.add(user)
    session.flush()
    return user


def seed_job(session: Session, user: User, job_uuid: str) -> VerificationJob:
    job = VerificationJob(
        job_uuid=job_uuid,
        created_by_user_id=user.id,
        source_files_json="[]",
        uploads_dir="/tmp/uploads",
        output_root_path="/tmp/output",
        status="succeeded",
        stage="completed",
        progress_percent=100,
        total_records=1,
        success_count=1,
        failed_count=0,
        skipped_count=0,
    )
    session.add(job)
    session.flush()
    return job


def seed_invoice(
    session: Session,
    *,
    job: VerificationJob,
    invoice_key: str,
    invoice_number: str,
    invoice_date: str,
    verified_at: datetime,
) -> None:
    item = VerificationJobItem(
        job_id=job.id,
        invoice_key=invoice_key,
        invoice_number=invoice_number,
        invoice_date=invoice_date,
        pretax_amount="100.00",
        total_amount="100.00",
        verification_status="success",
        verified_at=verified_at,
    )
    session.add(item)
    session.flush()
    invoice = Invoice(
        invoice_key=invoice_key,
        latest_job_id=job.id,
        latest_job_item_id=item.id,
        invoice_type="电子发票（普通发票）",
        invoice_number=invoice_number,
        invoice_date=invoice_date,
        pretax_amount="100.00",
        total_amount="100.00",
        verification_status="success",
        verified_at=verified_at,
        first_verified_at=verified_at,
        last_verified_at=verified_at,
    )
    session.add(invoice)


def test_list_invoices_applies_recent_7_days_quick_range() -> None:
    session = build_session()
    user = seed_user(session)
    job = seed_job(session, user, "job_recent")
    now = datetime.now(timezone.utc)
    within_range = now.date().isoformat()
    outside_range = (now.date() - timedelta(days=40)).isoformat()
    seed_invoice(
        session,
        job=job,
        invoice_key="recent-key",
        invoice_number="11111111",
        invoice_date=within_range,
        verified_at=now,
    )
    seed_invoice(
        session,
        job=job,
        invoice_key="old-key",
        invoice_number="22222222",
        invoice_date=outside_range,
        verified_at=now - timedelta(days=40),
    )
    session.commit()

    result = list_invoices(
        session,
        page=1,
        page_size=20,
        invoice_number=None,
        date_from=None,
        date_to=None,
        seller_name=None,
        buyer_name=None,
        quick_range="recent_7_days",
        sort_by="last_verified_at",
        sort_order="desc",
    )

    assert result["filters"]["quick_range"] == "recent_7_days"
    assert len(result["items"]) == 1
    assert result["items"][0]["invoice_number"] == "11111111"


def test_list_exports_includes_error_message() -> None:
    session = build_session()
    user = seed_user(session)
    export = Export(
        export_uuid="exp_001",
        created_by_user_id=user.id,
        export_type="invoice_list_excel",
        status="failed",
        error_message="生成文件失败",
    )
    session.add(export)
    session.commit()

    result = list_exports(session, page=1, page_size=20)

    assert len(result["items"]) == 1
    assert result["items"][0]["error_message"] == "生成文件失败"


def test_parse_verified_timestamp_accepts_utc_z_suffix() -> None:
    parsed = parse_verified_timestamp("2026-05-29T03:31:42.056Z")

    assert parsed == datetime(2026, 5, 29, 3, 31, 42, 56000, tzinfo=timezone.utc)


def test_prefer_modal_screenshot_path_for_result_sibling(tmp_path) -> None:
    result_path = tmp_path / "invoice-attempt-1-retry-2-result.png"
    modal_path = tmp_path / "invoice-attempt-1-retry-2-modal.png"
    result_path.write_bytes(b"full-page")
    modal_path.write_bytes(b"modal")

    assert prefer_modal_screenshot_path(str(result_path)) == str(modal_path)


def test_prefer_modal_screenshot_path_keeps_result_without_sibling(tmp_path) -> None:
    result_path = tmp_path / "invoice-attempt-1-retry-2-result.png"
    result_path.write_bytes(b"full-page")

    assert prefer_modal_screenshot_path(str(result_path)) == str(result_path)


def test_build_invoice_info_cache_payload_includes_uploaded_invoice_fields() -> None:
    session = build_session()
    user = seed_user(session)
    job = seed_job(session, user, "job_cache")
    verified_at = datetime(2026, 5, 30, 9, 0, tzinfo=timezone.utc)
    item = VerificationJobItem(
        job_id=job.id,
        invoice_key="033002100111|80678174|2026-03-28|330.19",
        invoice_type="增值税普通发票",
        invoice_code="033002100111",
        invoice_number="80678174",
        invoice_date="2026-03-28",
        pretax_amount="330.19",
        total_amount="350.00",
        check_code="567890",
        verification_status="success",
        verified_at=verified_at,
        source_pdf="01_住宿费.pdf",
        page_number=1,
    )

    payload = build_invoice_info_cache_payload(job, item)

    assert payload["invoice_key"] == "033002100111|80678174|2026-03-28|330.19"
    assert payload["invoice_number"] == "80678174"
    assert payload["pretax_amount"] == "330.19"
    assert payload["check_code"] == "567890"
    assert payload["source_pdf"] == "01_住宿费.pdf"
    assert payload["source_job_id"] == "job_cache"
    assert payload["verified_at"] == "2026-05-30T09:00:00+00:00"


def test_persist_pipeline_results_caches_successful_uploaded_invoice(
    monkeypatch,
    tmp_path,
) -> None:
    session = build_session()
    user = seed_user(session)
    job = seed_job(session, user, "job_cache_write")
    invoice_key = "033002100111|80678174|2026-03-28|330.19"
    extracted_json = tmp_path / "extracted.json"
    verified_json = tmp_path / "verified.json"
    captured: dict[str, dict] = {}

    extracted_json.write_text(
        """
{
  "records": [
    {
      "source_pdf": "01_住宿费.pdf",
      "page_number": 1,
      "invoice_type": "增值税普通发票",
      "invoice_code": "033002100111",
      "invoice_number": "80678174",
      "invoice_date": "2026-03-28",
      "pretax_amount": "330.19",
      "total_amount": "350.00",
      "check_code": "12345678901234567890",
      "extraction_status": "success",
      "validation_status": "pass",
      "validation_errors": [],
      "record_id": "record-1",
      "invoice_key": "033002100111|80678174|2026-03-28|330.19",
      "needs_verification": true
    }
  ]
}
""",
        encoding="utf-8",
    )
    verified_json.write_text(
        """
{
  "results_by_key": {
    "033002100111|80678174|2026-03-28|330.19": {
      "invoice_key": "033002100111|80678174|2026-03-28|330.19",
      "verification_status": "success",
      "verification_message": "查验成功",
      "verified_at": "2026-05-30T09:00:00.000Z",
      "result_screenshot": null,
      "result_text": null
    }
  }
}
""",
        encoding="utf-8",
    )

    class FakeInvoiceInfoCache:
        def __init__(self, redis_url, ttl_seconds) -> None:
            assert redis_url == "redis://example.invalid/0"
            assert ttl_seconds == 60

        def set(self, key: str, value: dict) -> None:
            captured[key] = value

    monkeypatch.setattr("app.services.InvoiceInfoCache", FakeInvoiceInfoCache)
    monkeypatch.setenv("REDIS_URL", "redis://example.invalid/0")
    monkeypatch.setenv("QR_CACHE_TTL_SECONDS", "60")
    settings = AppSettings.from_env(root_dir=tmp_path)

    persist_pipeline_results(session, job, extracted_json, verified_json, settings)

    assert invoice_key in captured
    assert captured[invoice_key]["invoice_number"] == "80678174"
    assert captured[invoice_key]["source_pdf"] == "01_住宿费.pdf"
    assert captured[invoice_key]["verification_status"] == "success"


def test_build_qr_extracted_record_uses_existing_verification_shape() -> None:
    parsed = parse_invoice_qr("01,20,26317000001011694315,20260328,330.19")

    record = build_qr_extracted_record(parsed)

    assert record["source_pdf"] == QR_INVOICE_SOURCE_FILE
    assert record["invoice_number"] == "26317000001011694315"
    assert record["invoice_date"] == "2026-03-28"
    assert record["pretax_amount"] == "330.19"
    assert record["extraction_status"] == "success"
    assert record["extraction_method"] == "qr-code"
    assert record["validation_status"] == "pass"
    assert record["invoice_key"] == "|26317000001011694315|2026-03-28|330.19"
    assert record["needs_verification"] is True


def test_execute_qr_invoice_pipeline_writes_extracted_json_and_runs_verify_only(
    monkeypatch,
    tmp_path,
) -> None:
    session = build_session()
    user = seed_user(session)
    settings = AppSettings.from_env(root_dir=tmp_path)
    parsed = parse_invoice_qr("01,20,26317000001011694315,20260328,330.19")
    job = create_qr_invoice_job(session, settings, user, parsed)
    session.commit()
    calls: list[tuple[str, list[str]]] = []

    def fake_run_command(command, cwd, env, *, log_path=None, label="command"):
        calls.append((label, command))
        output_json = command[command.index("--output-json") + 1]
        json_payload = {
            "results_by_key": {
                "|26317000001011694315|2026-03-28|330.19": {
                    "invoice_key": "|26317000001011694315|2026-03-28|330.19",
                    "verification_status": "success",
                    "verification_message": "查验成功",
                    "verified_at": "2026-05-30T09:00:00.000Z",
                    "result_screenshot": None,
                    "result_text": None,
                }
            }
        }
        tmp_output = tmp_path / "verified.json"
        tmp_output.write_text(json.dumps(json_payload), encoding="utf-8")
        # The production path is what the verification command receives.
        from pathlib import Path

        Path(output_json).write_text(json.dumps(json_payload), encoding="utf-8")
        return subprocess.CompletedProcess(command, 0, stdout="", stderr="")

    monkeypatch.setattr("app.services.run_command", fake_run_command)

    extracted_json, verified_json = execute_qr_invoice_pipeline(
        settings,
        {},
        job,
        tmp_path / "job-output",
    )

    extracted_payload = json.loads(extracted_json.read_text(encoding="utf-8"))
    assert extracted_payload["source_type"] == "qr_invoice"
    assert extracted_payload["records"][0]["invoice_number"] == "26317000001011694315"
    assert verified_json.exists()
    assert [label for label, _ in calls] == ["verify_invoices"]
    assert all("extract_invoices.py" not in " ".join(command) for _, command in calls)


def test_create_retry_job_rejects_qr_invoice_source(tmp_path) -> None:
    session = build_session()
    user = seed_user(session)
    settings = AppSettings.from_env(root_dir=tmp_path)
    parsed = parse_invoice_qr("01,20,26317000001011694315,20260328,330.19")
    job = create_qr_invoice_job(session, settings, user, parsed)

    try:
        create_retry_job(session, settings, user, job, "file_001")
    except ValueError as exc:
        assert "扫码发票任务不支持按文件重试" in str(exc)
    else:
        raise AssertionError("create_retry_job should reject QR invoice sources")
