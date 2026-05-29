from __future__ import annotations

from datetime import datetime, timedelta, timezone

from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker

from app.database import Base
from app.models import Export, Invoice, User, VerificationJob, VerificationJobItem
from app.security import hash_password
from app.services import list_exports, list_invoices, parse_verified_timestamp


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
