from __future__ import annotations

import queue
import threading

from app.config import AppSettings
from app.worker import WorkerManager


def test_worker_concurrency_can_process_multiple_jobs(monkeypatch, tmp_path) -> None:
    monkeypatch.setenv("APP_WORKER_CONCURRENCY", "2")
    settings = AppSettings.from_env(root_dir=tmp_path)
    started: queue.Queue[str] = queue.Queue()
    release = threading.Event()

    def fake_process_job(job_uuid: str, session_factory, settings) -> None:
        _ = session_factory, settings
        started.put(job_uuid)
        release.wait(timeout=2)

    monkeypatch.setattr("app.worker.process_job", fake_process_job)
    monkeypatch.setattr(WorkerManager, "_enqueue_unfinished_jobs", lambda self: None)

    manager = WorkerManager(lambda: None, settings)
    manager.start()
    try:
        manager.enqueue_job("job_a")
        manager.enqueue_job("job_b")

        first = started.get(timeout=1)
        second = started.get(timeout=1)
        assert {first, second} == {"job_a", "job_b"}
    finally:
        release.set()
        manager.stop()


def test_worker_defaults_to_single_background_thread(tmp_path) -> None:
    settings = AppSettings.from_env(root_dir=tmp_path)
    assert settings.worker_concurrency == 1
