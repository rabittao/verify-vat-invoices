from __future__ import annotations

import logging
from logging.handlers import RotatingFileHandler

from app.config import AppSettings


def configure_logging(settings: AppSettings) -> None:
    settings.logs_dir.mkdir(parents=True, exist_ok=True)
    log_format = "%(asctime)s %(levelname)s [%(name)s] %(message)s"
    formatter = logging.Formatter(log_format)

    root_logger = logging.getLogger()
    root_logger.setLevel(logging.INFO)

    log_file = settings.logs_dir / "app.log"
    if not any(isinstance(handler, RotatingFileHandler) and handler.baseFilename == str(log_file) for handler in root_logger.handlers):
        file_handler = RotatingFileHandler(log_file, maxBytes=5 * 1024 * 1024, backupCount=5, encoding="utf-8")
        file_handler.setFormatter(formatter)
        root_logger.addHandler(file_handler)

    if not any(getattr(handler, "_verify_vat_console", False) for handler in root_logger.handlers):
        console_handler = logging.StreamHandler()
        console_handler.setFormatter(formatter)
        console_handler._verify_vat_console = True
        root_logger.addHandler(console_handler)
