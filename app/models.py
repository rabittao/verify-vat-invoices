from __future__ import annotations

from sqlalchemy import Boolean, DateTime, ForeignKey, Integer, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base, utcnow


class TimestampMixin:
    created_at: Mapped[DateTime] = mapped_column(DateTime(timezone=True), default=utcnow, nullable=False)
    updated_at: Mapped[DateTime] = mapped_column(DateTime(timezone=True), default=utcnow, onupdate=utcnow, nullable=False)


class User(Base, TimestampMixin):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    username: Mapped[str] = mapped_column(Text, unique=True, nullable=False)
    password_hash: Mapped[str] = mapped_column(Text, nullable=False)
    role: Mapped[str] = mapped_column(Text, default="user", nullable=False)
    display_name: Mapped[str | None] = mapped_column(Text, nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)


class SystemSetting(Base):
    __tablename__ = "system_settings"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    setting_key: Mapped[str] = mapped_column(Text, unique=True, nullable=False)
    setting_value: Mapped[str | None] = mapped_column(Text, nullable=True)
    is_sensitive: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    updated_by_user_id: Mapped[int | None] = mapped_column(ForeignKey("users.id"), nullable=True)
    updated_at: Mapped[DateTime] = mapped_column(DateTime(timezone=True), default=utcnow, onupdate=utcnow, nullable=False)


class VerificationJob(Base, TimestampMixin):
    __tablename__ = "verification_jobs"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    job_uuid: Mapped[str] = mapped_column(Text, unique=True, nullable=False)
    created_by_user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), nullable=False)
    source_files_json: Mapped[str] = mapped_column(Text, nullable=False)
    uploads_dir: Mapped[str] = mapped_column(Text, nullable=False)
    output_root_path: Mapped[str] = mapped_column(Text, nullable=False)
    status: Mapped[str] = mapped_column(Text, nullable=False, default="queued")
    stage: Mapped[str] = mapped_column(Text, nullable=False, default="uploaded")
    progress_percent: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    total_records: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    success_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    failed_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    skipped_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    started_at: Mapped[DateTime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    finished_at: Mapped[DateTime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    error_message: Mapped[str | None] = mapped_column(Text, nullable=True)


class VerificationJobItem(Base, TimestampMixin):
    __tablename__ = "verification_job_items"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    job_id: Mapped[int] = mapped_column(ForeignKey("verification_jobs.id"), nullable=False, index=True)
    record_id: Mapped[str | None] = mapped_column(Text, nullable=True)
    invoice_key: Mapped[str | None] = mapped_column(Text, nullable=True, index=True)
    file_id: Mapped[str | None] = mapped_column(Text, nullable=True)
    source_pdf: Mapped[str | None] = mapped_column(Text, nullable=True)
    page_number: Mapped[int | None] = mapped_column(Integer, nullable=True)
    invoice_index: Mapped[int | None] = mapped_column(Integer, nullable=True)
    invoice_type: Mapped[str | None] = mapped_column(Text, nullable=True)
    invoice_code: Mapped[str | None] = mapped_column(Text, nullable=True)
    invoice_number: Mapped[str | None] = mapped_column(Text, nullable=True, index=True)
    invoice_date: Mapped[str | None] = mapped_column(Text, nullable=True)
    pretax_amount: Mapped[str | None] = mapped_column(Text, nullable=True)
    tax_amount: Mapped[str | None] = mapped_column(Text, nullable=True)
    total_amount: Mapped[str | None] = mapped_column(Text, nullable=True)
    seller_name: Mapped[str | None] = mapped_column(Text, nullable=True)
    buyer_name: Mapped[str | None] = mapped_column(Text, nullable=True)
    check_code: Mapped[str | None] = mapped_column(Text, nullable=True)
    extraction_status: Mapped[str | None] = mapped_column(Text, nullable=True)
    extraction_message: Mapped[str | None] = mapped_column(Text, nullable=True)
    extraction_method: Mapped[str | None] = mapped_column(Text, nullable=True)
    validation_status: Mapped[str | None] = mapped_column(Text, nullable=True)
    validation_errors_json: Mapped[str | None] = mapped_column(Text, nullable=True)
    validation_warnings_json: Mapped[str | None] = mapped_column(Text, nullable=True)
    needs_verification: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    verification_status: Mapped[str | None] = mapped_column(Text, nullable=True, index=True)
    verification_message: Mapped[str | None] = mapped_column(Text, nullable=True)
    verification_amount_type: Mapped[str | None] = mapped_column(Text, nullable=True)
    verification_amount_used: Mapped[str | None] = mapped_column(Text, nullable=True)
    captcha_attempts: Mapped[int | None] = mapped_column(Integer, nullable=True)
    verified_at: Mapped[DateTime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    extract_screenshot_path: Mapped[str | None] = mapped_column(Text, nullable=True)
    verify_screenshot_path: Mapped[str | None] = mapped_column(Text, nullable=True)
    result_text: Mapped[str | None] = mapped_column(Text, nullable=True)
    raw_extracted_json: Mapped[str | None] = mapped_column(Text, nullable=True)
    raw_verified_json: Mapped[str | None] = mapped_column(Text, nullable=True)


class Invoice(Base, TimestampMixin):
    __tablename__ = "invoices"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    invoice_key: Mapped[str] = mapped_column(Text, unique=True, nullable=False)
    latest_job_id: Mapped[int] = mapped_column(ForeignKey("verification_jobs.id"), nullable=False)
    latest_job_item_id: Mapped[int] = mapped_column(ForeignKey("verification_job_items.id"), nullable=False)
    invoice_type: Mapped[str | None] = mapped_column(Text, nullable=True)
    invoice_code: Mapped[str | None] = mapped_column(Text, nullable=True)
    invoice_number: Mapped[str] = mapped_column(Text, nullable=False, index=True)
    invoice_date: Mapped[str] = mapped_column(Text, nullable=False)
    pretax_amount: Mapped[str] = mapped_column(Text, nullable=False)
    tax_amount: Mapped[str | None] = mapped_column(Text, nullable=True)
    total_amount: Mapped[str | None] = mapped_column(Text, nullable=True)
    seller_name: Mapped[str | None] = mapped_column(Text, nullable=True)
    buyer_name: Mapped[str | None] = mapped_column(Text, nullable=True)
    check_code: Mapped[str | None] = mapped_column(Text, nullable=True)
    verification_status: Mapped[str] = mapped_column(Text, nullable=False)
    verification_message: Mapped[str | None] = mapped_column(Text, nullable=True)
    verification_amount_type: Mapped[str | None] = mapped_column(Text, nullable=True)
    verification_amount_used: Mapped[str | None] = mapped_column(Text, nullable=True)
    verified_at: Mapped[DateTime] = mapped_column(DateTime(timezone=True), nullable=False)
    source_pdf: Mapped[str | None] = mapped_column(Text, nullable=True)
    page_number: Mapped[int | None] = mapped_column(Integer, nullable=True)
    result_screenshot_path: Mapped[str | None] = mapped_column(Text, nullable=True)
    first_verified_at: Mapped[DateTime] = mapped_column(DateTime(timezone=True), nullable=False)
    last_verified_at: Mapped[DateTime] = mapped_column(DateTime(timezone=True), nullable=False)


class Export(Base, TimestampMixin):
    __tablename__ = "exports"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    export_uuid: Mapped[str] = mapped_column(Text, unique=True, nullable=False)
    created_by_user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), nullable=False)
    export_type: Mapped[str] = mapped_column(Text, nullable=False)
    status: Mapped[str] = mapped_column(Text, nullable=False, default="queued")
    filters_json: Mapped[str | None] = mapped_column(Text, nullable=True)
    invoice_id: Mapped[int | None] = mapped_column(ForeignKey("invoices.id"), nullable=True)
    file_name: Mapped[str | None] = mapped_column(Text, nullable=True)
    file_path: Mapped[str | None] = mapped_column(Text, nullable=True)
    file_size: Mapped[int | None] = mapped_column(Integer, nullable=True)
    error_message: Mapped[str | None] = mapped_column(Text, nullable=True)
    finished_at: Mapped[DateTime | None] = mapped_column(DateTime(timezone=True), nullable=True)
