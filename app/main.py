from __future__ import annotations

from contextlib import asynccontextmanager
from datetime import date
from typing import Annotated

from fastapi import Depends, FastAPI, File, Header, HTTPException, Query, UploadFile
from fastapi.responses import FileResponse
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.config import AppSettings, get_settings
from app.database import build_session_factory, init_database, session_scope
from app.logging_config import configure_logging
from app.models import Export, Invoice, User, VerificationJob, VerificationJobItem
from app.schemas import (
    ApiMessage,
    ConfigValidationItem,
    CreateExportRequest,
    CreateExportResponse,
    CreateTaskResponse,
    ExportListResponse,
    LedgerDetailResponse,
    LedgerListResponse,
    LoginRequest,
    LoginResponse,
    RetryFileResponse,
    SystemConfigResponse,
    TaskDetailResponse,
    TaskItemDetailResponse,
    TaskListResponse,
    UpdateSystemConfigRequest,
    UserProfileResponse,
    ValidateSystemConfigResponse,
)
from app.security import create_access_token, decode_access_token
from app.services import (
    authenticate_user,
    create_export,
    create_job,
    create_retry_job,
    delete_completed_job,
    ensure_admin_user,
    get_invoice_detail,
    get_job_detail,
    get_job_item_detail,
    get_system_config,
    list_exports,
    list_invoices,
    list_jobs,
    safe_resolve_path,
    update_system_config,
    validate_system_config,
)
from app.worker import WorkerManager


def create_app(settings: AppSettings | None = None) -> FastAPI:
    resolved_settings = settings or get_settings()
    configure_logging(resolved_settings)
    if resolved_settings.api_secret_key_generated:
        import logging
        logging.getLogger(__name__).warning(
            "API_SECRET_KEY 未配置，当前进程使用临时随机签名密钥。"
            " 重启后旧 token 会失效，建议尽快在 .env 中设置固定值。"
        )
    session_factory = build_session_factory(resolved_settings)
    init_database(session_factory)
    with session_scope(session_factory) as session:
        ensure_admin_user(session, resolved_settings)

    worker = WorkerManager(session_factory, resolved_settings)

    @asynccontextmanager
    async def lifespan(_: FastAPI):
        worker.start()
        yield
        worker.stop()

    app = FastAPI(title="verify-vat-invoices API", lifespan=lifespan)
    app.state.settings = resolved_settings
    app.state.session_factory = session_factory
    app.state.worker = worker

    def get_db():
        session = session_factory()
        try:
            yield session
        finally:
            session.close()

    def resolve_current_user(
        authorization: Annotated[str | None, Header(alias="Authorization")] = None,
        db: Session = Depends(get_db),
    ) -> User:
        if not authorization or not authorization.lower().startswith("bearer "):
            raise HTTPException(status_code=401, detail="missing bearer token")
        token = authorization.split(" ", 1)[1].strip()
        try:
            payload = decode_access_token(token, resolved_settings.api_secret_key)
        except ValueError as exc:
            raise HTTPException(status_code=401, detail=str(exc)) from exc
        user = db.get(User, int(payload["sub"]))
        if user is None or not user.is_active:
            raise HTTPException(status_code=401, detail="user not found")
        return user

    def resolve_admin_user(user: User = Depends(resolve_current_user)) -> User:
        if user.role != "admin":
            raise HTTPException(status_code=403, detail="admin required")
        return user

    @app.post("/api/auth/login", response_model=LoginResponse)
    def login(payload: LoginRequest, db: Session = Depends(get_db)) -> LoginResponse:
        user = authenticate_user(db, payload.username, payload.password)
        if user is None:
            raise HTTPException(status_code=401, detail="用户名或密码错误")
        token = create_access_token(user.id, user.role, resolved_settings.api_secret_key, resolved_settings.token_expire_days)
        return LoginResponse(
            access_token=token,
            user=UserProfileResponse(
                user_id=user.id,
                username=user.username,
                display_name=user.display_name,
                role=user.role,
            ),
        )

    @app.get("/api/tasks", response_model=TaskListResponse)
    def get_tasks(
        completed_page: int = Query(1, ge=1),
        completed_page_size: int = Query(20, ge=1, le=100),
        user: User = Depends(resolve_current_user),
        db: Session = Depends(get_db),
    ) -> TaskListResponse:
        _ = user
        worker.wake_unfinished_jobs()
        return TaskListResponse(**list_jobs(db, completed_page, completed_page_size))

    @app.post("/api/tasks", response_model=CreateTaskResponse)
    async def create_task(
        files: list[UploadFile] = File(...),
        user: User = Depends(resolve_current_user),
        db: Session = Depends(get_db),
    ) -> CreateTaskResponse:
        if not files:
            raise HTTPException(status_code=400, detail="至少上传一个 PDF 文件")
        if len(files) > resolved_settings.max_upload_files:
            raise HTTPException(status_code=400, detail=f"最多上传 {resolved_settings.max_upload_files} 个 PDF")
        uploads = []
        total_bytes = 0
        for file in files:
            suffix = file.filename.lower().rsplit(".", 1)[-1] if file.filename else ""
            if f".{suffix}" not in resolved_settings.allowed_upload_extensions:
                raise HTTPException(status_code=400, detail="仅支持 PDF 文件")
            content = await file.read()
            size = len(content)
            total_bytes += size
            if size > resolved_settings.max_single_upload_bytes:
                raise HTTPException(status_code=400, detail="单个文件大小超限")
            uploads.append({"filename": file.filename or "upload.pdf", "content": content})
        if total_bytes > resolved_settings.max_total_upload_bytes:
            raise HTTPException(status_code=400, detail="上传文件总大小超限")
        job = create_job(db, resolved_settings, user, uploads)
        db.commit()
        db.refresh(job)
        worker.enqueue_job(job.job_uuid)
        return CreateTaskResponse(
            job_id=job.job_uuid,
            status=job.status,
            stage=job.stage,
            progress_percent=job.progress_percent,
            source_file_count=len(uploads),
            created_at=job.created_at,
        )

    @app.get("/api/tasks/{job_uuid}", response_model=TaskDetailResponse)
    def task_detail(job_uuid: str, user: User = Depends(resolve_current_user), db: Session = Depends(get_db)) -> TaskDetailResponse:
        _ = user
        worker.wake_unfinished_jobs()
        try:
            return TaskDetailResponse(**get_job_detail(db, job_uuid))
        except ValueError as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc

    @app.get("/api/tasks/{job_uuid}/items/{job_item_id}", response_model=TaskItemDetailResponse)
    def task_item_detail(job_uuid: str, job_item_id: int, user: User = Depends(resolve_current_user), db: Session = Depends(get_db)) -> TaskItemDetailResponse:
        _ = user
        try:
            return TaskItemDetailResponse(**get_job_item_detail(db, job_uuid, job_item_id))
        except ValueError as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc

    @app.post("/api/tasks/{job_uuid}/files/{file_id}/retry", response_model=RetryFileResponse)
    def retry_job_file(job_uuid: str, file_id: str, user: User = Depends(resolve_current_user), db: Session = Depends(get_db)) -> RetryFileResponse:
        original_job = db.scalar(select(VerificationJob).where(VerificationJob.job_uuid == job_uuid))
        if original_job is None:
            raise HTTPException(status_code=404, detail="任务不存在")
        try:
            new_job = create_retry_job(db, resolved_settings, user, original_job, file_id)
        except ValueError as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        db.commit()
        db.refresh(new_job)
        worker.enqueue_job(new_job.job_uuid)
        return RetryFileResponse(
            job_id=new_job.job_uuid,
            status=new_job.status,
            stage=new_job.stage,
            progress_percent=new_job.progress_percent,
            source_file_count=1,
            created_at=new_job.created_at,
            retry_of_job_id=job_uuid,
            retry_of_file_id=file_id,
        )

    @app.delete("/api/tasks/{job_uuid}", response_model=ApiMessage)
    def delete_task(job_uuid: str, user: User = Depends(resolve_current_user), db: Session = Depends(get_db)) -> ApiMessage:
        _ = user
        try:
            delete_completed_job(db, job_uuid)
        except ValueError as exc:
            message = str(exc)
            status_code = 404 if message == "任务不存在" else 400
            raise HTTPException(status_code=status_code, detail=message) from exc
        db.commit()
        return ApiMessage(message="任务已删除")

    @app.get("/api/invoices", response_model=LedgerListResponse)
    def invoices(
        page: int = Query(1, ge=1),
        page_size: int = Query(20, ge=1, le=100),
        invoice_number: str | None = None,
        date_from: date | None = None,
        date_to: date | None = None,
        seller_name: str | None = None,
        buyer_name: str | None = None,
        quick_range: str | None = None,
        sort_by: str = "last_verified_at",
        sort_order: str = "desc",
        user: User = Depends(resolve_current_user),
        db: Session = Depends(get_db),
    ) -> LedgerListResponse:
        _ = user
        return LedgerListResponse(
            **list_invoices(
                db,
                page=page,
                page_size=page_size,
                invoice_number=invoice_number,
                date_from=date_from,
                date_to=date_to,
                seller_name=seller_name,
                buyer_name=buyer_name,
                quick_range=quick_range,
                sort_by=sort_by,
                sort_order=sort_order,
            )
        )

    @app.get("/api/invoices/{invoice_id}", response_model=LedgerDetailResponse)
    def invoice_detail(invoice_id: int, user: User = Depends(resolve_current_user), db: Session = Depends(get_db)) -> LedgerDetailResponse:
        _ = user
        try:
            return LedgerDetailResponse(**get_invoice_detail(db, invoice_id))
        except ValueError as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc

    @app.post("/api/exports", response_model=CreateExportResponse)
    def create_export_task(payload: CreateExportRequest, user: User = Depends(resolve_current_user), db: Session = Depends(get_db)) -> CreateExportResponse:
        record = create_export(
            db,
            user,
            export_type=payload.export_type,
            filters=payload.filters.model_dump() if payload.filters else None,
            invoice_id=payload.invoice_id,
        )
        db.commit()
        db.refresh(record)
        worker.enqueue_export(record.export_uuid)
        return CreateExportResponse(
            export_id=record.export_uuid,
            status=record.status,
            export_type=record.export_type,
            created_at=record.created_at,
        )

    @app.get("/api/exports", response_model=ExportListResponse)
    def exports(page: int = Query(1, ge=1), page_size: int = Query(20, ge=1, le=100), user: User = Depends(resolve_current_user), db: Session = Depends(get_db)) -> ExportListResponse:
        _ = user
        return ExportListResponse(**list_exports(db, page, page_size))

    @app.get("/api/admin/system-config", response_model=SystemConfigResponse)
    def system_config(admin: User = Depends(resolve_admin_user), db: Session = Depends(get_db)) -> SystemConfigResponse:
        _ = admin
        return SystemConfigResponse(**get_system_config(db, resolved_settings))

    @app.put("/api/admin/system-config", response_model=ApiMessage)
    def update_config(payload: UpdateSystemConfigRequest, admin: User = Depends(resolve_admin_user), db: Session = Depends(get_db)) -> ApiMessage:
        updates = {}
        mapping = {
            "qwen_api_key": "QWEN_API_KEY",
            "qwen_invoice_model": "QWEN_INVOICE_MODEL",
            "openrouter_api_key": "OPENROUTER_API_KEY",
            "openrouter_captcha_model": "OPENROUTER_CAPTCHA_MODEL",
        }
        for field_name, key in mapping.items():
            if field_name in payload.model_fields_set:
                updates[key] = getattr(payload, field_name)
        update_system_config(db, admin, updates)
        db.commit()
        return ApiMessage(message="配置已更新")

    @app.post("/api/admin/system-config/validate", response_model=ValidateSystemConfigResponse)
    def validate_config(admin: User = Depends(resolve_admin_user), db: Session = Depends(get_db)) -> ValidateSystemConfigResponse:
        _ = admin
        items = [ConfigValidationItem(**entry) for entry in validate_system_config(db, resolved_settings)]
        return ValidateSystemConfigResponse(items=items, all_ok=all(entry.ok for entry in items))

    @app.get("/api/files/job-items/{job_item_id}/extract-screenshot")
    def job_item_extract_screenshot(job_item_id: int, user: User = Depends(resolve_current_user), db: Session = Depends(get_db)) -> FileResponse:
        _ = user
        item = db.get(VerificationJobItem, job_item_id)
        if item is None:
            raise HTTPException(status_code=404, detail="记录不存在")
        try:
            path = safe_resolve_path(item.extract_screenshot_path, resolved_settings.data_dir)
        except FileNotFoundError as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        return FileResponse(path)

    @app.get("/api/files/job-items/{job_item_id}/verify-screenshot")
    def job_item_verify_screenshot(job_item_id: int, user: User = Depends(resolve_current_user), db: Session = Depends(get_db)) -> FileResponse:
        _ = user
        item = db.get(VerificationJobItem, job_item_id)
        if item is None:
            raise HTTPException(status_code=404, detail="记录不存在")
        try:
            path = safe_resolve_path(item.verify_screenshot_path, resolved_settings.data_dir)
        except FileNotFoundError as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        return FileResponse(path)

    @app.get("/api/files/invoices/{invoice_id}/screenshot")
    def invoice_screenshot(invoice_id: int, user: User = Depends(resolve_current_user), db: Session = Depends(get_db)) -> FileResponse:
        _ = user
        invoice = db.get(Invoice, invoice_id)
        if invoice is None:
            raise HTTPException(status_code=404, detail="记录不存在")
        try:
            path = safe_resolve_path(invoice.result_screenshot_path, resolved_settings.data_dir)
        except FileNotFoundError as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        return FileResponse(path)

    @app.get("/api/files/exports/{export_uuid}/open")
    def open_export(export_uuid: str, user: User = Depends(resolve_current_user), db: Session = Depends(get_db)) -> FileResponse:
        _ = user
        export = db.scalar(select(Export).where(Export.export_uuid == export_uuid))
        if export is None:
            raise HTTPException(status_code=404, detail="导出不存在")
        try:
            path = safe_resolve_path(export.file_path, resolved_settings.data_dir)
        except FileNotFoundError as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        return FileResponse(path)

    @app.get("/api/files/exports/{export_uuid}/download")
    def download_export(export_uuid: str, user: User = Depends(resolve_current_user), db: Session = Depends(get_db)) -> FileResponse:
        _ = user
        export = db.scalar(select(Export).where(Export.export_uuid == export_uuid))
        if export is None:
            raise HTTPException(status_code=404, detail="导出不存在")
        try:
            path = safe_resolve_path(export.file_path, resolved_settings.data_dir)
        except FileNotFoundError as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        return FileResponse(path, filename=export.file_name)

    return app


app = create_app()
