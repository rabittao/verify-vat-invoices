from __future__ import annotations

from fastapi.testclient import TestClient

from app.config import AppSettings
from app.invoice_qr import build_invoice_key, parse_invoice_qr
from app.main import create_app


def test_parse_digital_invoice_qr_extracts_core_fields() -> None:
    parsed = parse_invoice_qr("01,20,26317000001011694315,20260328,330.19")

    assert parsed.invoice_type == "数电票/全电发票"
    assert parsed.invoice_code is None
    assert parsed.invoice_number == "26317000001011694315"
    assert parsed.invoice_date == "2026-03-28"
    assert parsed.pretax_amount == "330.19"
    assert parsed.confidence == "high"
    assert build_invoice_key(
        parsed.invoice_code,
        parsed.invoice_number,
        parsed.invoice_date,
        parsed.pretax_amount,
    ) == "|26317000001011694315|2026-03-28|330.19"


def test_parse_vat_ordinary_invoice_qr_extracts_code_number_and_check_code() -> None:
    parsed = parse_invoice_qr(
        "01,10,033002100111,80678174,330.19,20260328,12345678901234567890"
    )

    assert parsed.invoice_type == "增值税普通发票"
    assert parsed.invoice_code == "033002100111"
    assert parsed.invoice_number == "80678174"
    assert parsed.invoice_date == "2026-03-28"
    assert parsed.pretax_amount == "330.19"
    assert parsed.check_code == "567890"
    assert parsed.confidence == "high"


def test_parse_invoice_qr_supports_tax_url_query_aliases() -> None:
    parsed = parse_invoice_qr(
        "https://example.invalid/fpqr?fpdm=033002100111&fphm=80678174"
        "&kprq=20260328&je=330.19&jym=12345678901234567890"
    )

    assert parsed.invoice_code == "033002100111"
    assert parsed.invoice_number == "80678174"
    assert parsed.invoice_date == "2026-03-28"
    assert parsed.pretax_amount == "330.19"
    assert parsed.check_code == "567890"
    assert parsed.confidence == "high"


def test_parse_invoice_qr_endpoint_requires_auth_and_returns_invoice_fields(tmp_path) -> None:
    settings = AppSettings.from_env(root_dir=tmp_path)
    with TestClient(create_app(settings)) as client:
        unauthenticated = client.post(
            "/api/qr-invoices/parse",
            json={"raw_text": "01,20,26317000001011694315,20260328,330.19"},
        )
        assert unauthenticated.status_code == 401

        login = client.post(
            "/api/auth/login",
            json={
                "username": settings.admin_username,
                "password": settings.admin_password,
            },
        )
        assert login.status_code == 200
        token = login.json()["access_token"]

        response = client.post(
            "/api/qr-invoices/parse",
            json={"raw_text": "01,20,26317000001011694315,20260328,330.19"},
            headers={"Authorization": f"Bearer {token}"},
        )

    assert response.status_code == 200
    data = response.json()
    assert data["invoice_number"] == "26317000001011694315"
    assert data["invoice_date"] == "2026-03-28"
    assert data["pretax_amount"] == "330.19"
    assert data["invoice_key"] == "|26317000001011694315|2026-03-28|330.19"
    assert data["validation_status"] == "pass"
    assert data["cache_hit"] is False


def test_parse_invoice_qr_endpoint_returns_cache_hit_on_repeated_content(
    monkeypatch,
    tmp_path,
) -> None:
    class FakeQrCache:
        def __init__(self, redis_url, ttl_seconds) -> None:
            self.values = {}

        def get(self, raw_text: str):
            return self.values.get(raw_text)

        def set(self, raw_text: str, value: dict) -> None:
            self.values[raw_text] = dict(value)

    monkeypatch.setattr("app.main.QrInvoiceCache", FakeQrCache)
    settings = AppSettings.from_env(root_dir=tmp_path)
    raw_text = "01,20,26317000001011694315,20260328,330.19"

    with TestClient(create_app(settings)) as client:
        login = client.post(
            "/api/auth/login",
            json={
                "username": settings.admin_username,
                "password": settings.admin_password,
            },
        )
        token = login.json()["access_token"]
        headers = {"Authorization": f"Bearer {token}"}

        first = client.post(
            "/api/qr-invoices/parse",
            json={"raw_text": raw_text},
            headers=headers,
        )
        second = client.post(
            "/api/qr-invoices/parse",
            json={"raw_text": raw_text},
            headers=headers,
        )

    assert first.status_code == 200
    assert first.json()["cache_hit"] is False
    assert second.status_code == 200
    assert second.json()["cache_hit"] is True
    assert second.json()["invoice_number"] == "26317000001011694315"


def test_verify_invoice_qr_endpoint_requires_auth(monkeypatch, tmp_path) -> None:
    class FakeWorker:
        def __init__(self, session_factory, settings) -> None:
            self.enqueued: list[str] = []

        def start(self) -> None:
            pass

        def stop(self) -> None:
            pass

        def enqueue_job(self, job_uuid: str) -> None:
            self.enqueued.append(job_uuid)

        def wake_unfinished_jobs(self) -> None:
            pass

    monkeypatch.setattr("app.main.WorkerManager", FakeWorker)
    settings = AppSettings.from_env(root_dir=tmp_path)
    with TestClient(create_app(settings)) as client:
        response = client.post(
            "/api/qr-invoices/verify",
            json={"raw_text": "01,20,26317000001011694315,20260328,330.19"},
        )

    assert response.status_code == 401


def test_verify_invoice_qr_endpoint_rejects_missing_fields(monkeypatch, tmp_path) -> None:
    class FakeWorker:
        def __init__(self, session_factory, settings) -> None:
            self.enqueued: list[str] = []

        def start(self) -> None:
            pass

        def stop(self) -> None:
            pass

        def enqueue_job(self, job_uuid: str) -> None:
            self.enqueued.append(job_uuid)

        def wake_unfinished_jobs(self) -> None:
            pass

    monkeypatch.setattr("app.main.WorkerManager", FakeWorker)
    settings = AppSettings.from_env(root_dir=tmp_path)
    with TestClient(create_app(settings)) as client:
        login = client.post(
            "/api/auth/login",
            json={
                "username": settings.admin_username,
                "password": settings.admin_password,
            },
        )
        token = login.json()["access_token"]
        response = client.post(
            "/api/qr-invoices/verify",
            json={"raw_text": "01,20,26317000001011694315"},
            headers={"Authorization": f"Bearer {token}"},
        )

    assert response.status_code == 400
    assert response.json()["detail"]["validation_errors"] == [
        "Missing required field: invoice_date",
        "Missing required field: pretax_amount",
    ]


def test_verify_invoice_qr_endpoint_creates_qr_job_and_enqueues(monkeypatch, tmp_path) -> None:
    workers: list[FakeWorker] = []

    class FakeWorker:
        def __init__(self, session_factory, settings) -> None:
            self.enqueued: list[str] = []
            workers.append(self)

        def start(self) -> None:
            pass

        def stop(self) -> None:
            pass

        def enqueue_job(self, job_uuid: str) -> None:
            self.enqueued.append(job_uuid)

        def wake_unfinished_jobs(self) -> None:
            pass

    monkeypatch.setattr("app.main.WorkerManager", FakeWorker)
    settings = AppSettings.from_env(root_dir=tmp_path)
    with TestClient(create_app(settings)) as client:
        login = client.post(
            "/api/auth/login",
            json={
                "username": settings.admin_username,
                "password": settings.admin_password,
            },
        )
        token = login.json()["access_token"]
        response = client.post(
            "/api/qr-invoices/verify",
            json={"raw_text": "01,20,26317000001011694315,20260328,330.19"},
            headers={"Authorization": f"Bearer {token}"},
        )

    assert response.status_code == 200
    data = response.json()
    assert data["job_id"].startswith("job_")
    assert data["source_file_count"] == 1
    assert workers[0].enqueued == [data["job_id"]]
