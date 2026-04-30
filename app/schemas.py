from __future__ import annotations

from datetime import date, datetime

from pydantic import BaseModel, Field


class Pagination(BaseModel):
    page: int
    page_size: int
    total: int
    total_pages: int
    has_next: bool
    has_prev: bool


class SourceJobRef(BaseModel):
    job_id: str
    label: str


class LoginRequest(BaseModel):
    username: str
    password: str


class UserProfileResponse(BaseModel):
    user_id: int
    username: str
    display_name: str | None
    role: str


class LoginResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: UserProfileResponse


class TaskCardFile(BaseModel):
    file_name: str


class TaskCardResponse(BaseModel):
    job_id: str
    status: str
    stage: str
    progress_percent: int
    source_file_count: int
    total_records: int
    success_count: int
    failed_count: int
    skipped_count: int
    created_at: datetime
    updated_at: datetime
    finished_at: datetime | None
    display_title: str
    source_files: list[TaskCardFile]
    deletable: bool = False
    delete_block_reason: str | None = None


class RunningSummary(BaseModel):
    count: int


class TaskListResponse(BaseModel):
    running_items: list[TaskCardResponse]
    completed_items: list[TaskCardResponse]
    running_summary: RunningSummary
    completed_pagination: Pagination


class CreateTaskResponse(BaseModel):
    job_id: str
    status: str
    stage: str
    progress_percent: int
    source_file_count: int
    created_at: datetime


class TimelineStep(BaseModel):
    stage: str
    label: str
    done: bool
    current: bool


class TaskSummaryResponse(BaseModel):
    source_file_count: int
    total_records: int
    success_count: int
    failed_count: int
    skipped_count: int


class TaskItemSummaryResponse(BaseModel):
    job_item_id: int
    invoice_key: str | None
    invoice_number: str | None
    invoice_date: str | None
    amount: str | None
    status: str
    status_label: str
    failure_summary: str | None


class FileGroupResponse(BaseModel):
    file_id: str
    file_name: str
    source_pdf: str
    status: str
    record_count: int
    success_count: int
    failed_count: int
    skipped_count: int
    retryable: bool
    items: list[TaskItemSummaryResponse]


class TaskDetailResponse(BaseModel):
    job_id: str
    status: str
    stage: str
    progress_percent: int
    created_at: datetime
    started_at: datetime | None
    finished_at: datetime | None
    timeline: list[TimelineStep]
    summary: TaskSummaryResponse
    file_groups: list[FileGroupResponse]


class BasicInvoiceInfo(BaseModel):
    invoice_type: str | None
    invoice_code: str | None
    invoice_number: str | None
    invoice_date: str | None
    pretax_amount: str | None
    tax_amount: str | None
    total_amount: str | None
    seller_name: str | None
    buyer_name: str | None
    check_code: str | None


class ProcessingInfo(BaseModel):
    extraction_status: str | None
    extraction_message: str | None
    validation_status: str | None
    verification_status: str | None
    verification_message: str | None
    human_summary: str | None


class EvidenceInfo(BaseModel):
    extract_screenshot_url: str | None
    verify_screenshot_url: str | None


class TechnicalDetails(BaseModel):
    result_text: str | None
    validation_errors: list[str]


class TaskItemDetailResponse(BaseModel):
    job_item_id: int
    invoice_key: str | None
    basic_info: BasicInvoiceInfo
    processing_info: ProcessingInfo
    evidence: EvidenceInfo
    technical_details: TechnicalDetails


class RetryFileResponse(BaseModel):
    job_id: str
    status: str
    stage: str
    progress_percent: int
    source_file_count: int
    created_at: datetime
    retry_of_job_id: str
    retry_of_file_id: str


class LedgerFiltersResponse(BaseModel):
    invoice_number: str | None
    date_from: date | None
    date_to: date | None
    seller_name: str | None
    buyer_name: str | None
    quick_range: str | None
    sort_by: str
    sort_order: str


class LedgerInvoiceSummaryResponse(BaseModel):
    invoice_id: int
    invoice_key: str
    invoice_type: str | None
    invoice_code: str | None
    invoice_number: str
    invoice_date: str
    pretax_amount: str
    tax_amount: str | None
    total_amount: str | None
    seller_name: str | None
    buyer_name: str | None
    last_verified_at: datetime
    source_job: SourceJobRef | None
    has_screenshot: bool


class LedgerListResponse(BaseModel):
    filters: LedgerFiltersResponse
    items: list[LedgerInvoiceSummaryResponse]
    available_columns: list[str]
    default_columns: list[str]
    pagination: Pagination


class ScreenshotResponse(BaseModel):
    preview_url: str | None
    fullscreen_url: str | None


class LedgerActionsResponse(BaseModel):
    export_detail_pdf_enabled: bool
    view_source_job_enabled: bool


class CoreFieldsResponse(BaseModel):
    invoice_number: str
    invoice_date: str
    invoice_type: str | None
    pretax_amount: str
    tax_amount: str | None
    total_amount: str | None


class PartyFieldsResponse(BaseModel):
    seller_name: str | None
    buyer_name: str | None


class SystemFieldsResponse(BaseModel):
    verified_at: datetime
    first_verified_at: datetime
    last_verified_at: datetime
    created_at: datetime
    updated_at: datetime


class LedgerDetailResponse(BaseModel):
    invoice_id: int
    screenshot: ScreenshotResponse
    actions: LedgerActionsResponse
    source_job: SourceJobRef | None
    core_fields: CoreFieldsResponse
    party_fields: PartyFieldsResponse
    system_fields: SystemFieldsResponse


class ExportFilters(BaseModel):
    invoice_number: str | None = None
    date_from: date | None = None
    date_to: date | None = None
    seller_name: str | None = None
    buyer_name: str | None = None
    sort_by: str = "last_verified_at"
    sort_order: str = "desc"


class CreateExportRequest(BaseModel):
    export_type: str
    filters: ExportFilters | None = None
    invoice_id: int | None = None


class CreateExportResponse(BaseModel):
    export_id: str
    status: str
    export_type: str
    created_at: datetime


class ExportRecordResponse(BaseModel):
    export_id: str
    export_type: str
    status: str
    created_at: datetime
    finished_at: datetime | None
    file_name: str | None
    file_size: int | None
    open_url: str | None
    download_url: str | None
    share_enabled: bool


class ExportListResponse(BaseModel):
    items: list[ExportRecordResponse]
    pagination: Pagination


class SecretConfigField(BaseModel):
    is_configured: bool
    masked_value: str | None


class SystemConfigResponse(BaseModel):
    qwen_api_key: SecretConfigField
    qwen_invoice_model: str
    openrouter_api_key: SecretConfigField
    openrouter_captcha_model: str


class UpdateSystemConfigRequest(BaseModel):
    qwen_api_key: str | None = Field(default=None)
    qwen_invoice_model: str | None = Field(default=None)
    openrouter_api_key: str | None = Field(default=None)
    openrouter_captcha_model: str | None = Field(default=None)


class ConfigValidationItem(BaseModel):
    key: str
    ok: bool
    message: str


class ValidateSystemConfigResponse(BaseModel):
    items: list[ConfigValidationItem]
    all_ok: bool


class ApiMessage(BaseModel):
    message: str
