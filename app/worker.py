from __future__ import annotations

import logging
import queue
import threading
import traceback

from sqlalchemy import select

from app.config import AppSettings
from app.database import session_scope
from app.models import VerificationJob
from app.services import process_export, process_job

logger = logging.getLogger(__name__)


class WorkerManager:
    def __init__(self, session_factory, settings: AppSettings) -> None:
        self.session_factory = session_factory
        self.settings = settings
        self.inline = settings.inline_jobs
        self._queue: queue.Queue[tuple[str, str]] = queue.Queue()
        self._stop_event = threading.Event()
        self._thread: threading.Thread | None = None
        self._queued_jobs: set[str] = set()
        self._lock = threading.Lock()

    def start(self) -> None:
        if self.inline:
            logger.info("Worker inline mode enabled; jobs will run in request thread")
            return
        if self._thread is not None and self._thread.is_alive():
            return
        self._thread = None
        self._stop_event.clear()
        self._thread = threading.Thread(target=self._run, name="invoice-worker", daemon=True)
        self._thread.start()
        logger.info("Worker thread started")
        self._enqueue_unfinished_jobs()

    def stop(self) -> None:
        if self.inline:
            return
        self._stop_event.set()
        self._queue.put(("stop", ""))
        logger.info("Worker stop requested")
        if self._thread is not None:
            self._thread.join(timeout=3)
            self._thread = None

    def enqueue_job(self, job_uuid: str) -> None:
        if self.inline:
            process_job(job_uuid, self.session_factory, self.settings)
            return
        with self._lock:
            if job_uuid in self._queued_jobs:
                logger.info("Job already queued; skip duplicate enqueue: %s", job_uuid)
                return
            self._queued_jobs.add(job_uuid)
        self._queue.put(("job", job_uuid))
        logger.info("Job queued: %s", job_uuid)

    def enqueue_export(self, export_uuid: str) -> None:
        if self.inline:
            process_export(export_uuid, self.session_factory, self.settings)
            return
        self._queue.put(("export", export_uuid))
        logger.info("Export queued: %s", export_uuid)

    def _enqueue_unfinished_jobs(self) -> None:
        with session_scope(self.session_factory) as session:
            job_ids = session.scalars(
                select(VerificationJob.job_uuid)
                .where(VerificationJob.status.in_(["queued", "running"]))
                .order_by(VerificationJob.created_at.asc())
            ).all()
        for job_uuid in job_ids:
            self.enqueue_job(job_uuid)
        if job_ids:
            logger.info("Re-enqueued unfinished jobs: %s", ", ".join(job_ids))

    def wake_unfinished_jobs(self) -> None:
        if self.inline:
            return
        self.start()
        self._enqueue_unfinished_jobs()

    def _run(self) -> None:
        while not self._stop_event.is_set():
            task_type, identifier = self._queue.get()
            if task_type == "stop":
                break
            try:
                if task_type == "job":
                    logger.info("Worker picked job: %s", identifier)
                    process_job(identifier, self.session_factory, self.settings)
                elif task_type == "export":
                    logger.info("Worker picked export: %s", identifier)
                    process_export(identifier, self.session_factory, self.settings)
            except Exception:
                logger.exception("Worker task crashed: type=%s id=%s", task_type, identifier)
                traceback.print_exc()
            finally:
                if task_type == "job":
                    with self._lock:
                        self._queued_jobs.discard(identifier)
