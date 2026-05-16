from __future__ import annotations

from fastapi.testclient import TestClient

from app.config import AppSettings
from app.main import create_app


def test_health_endpoint_reports_ready(tmp_path) -> None:
    settings = AppSettings.from_env(root_dir=tmp_path)
    with TestClient(create_app(settings)) as client:
        response = client.get("/api/health")

    assert response.status_code == 200
    assert response.json() == {
        "status": "ok",
        "database": "ok",
        "worker": "running",
    }
