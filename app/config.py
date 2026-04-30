from __future__ import annotations

import os
import secrets
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path


def load_local_env_file(env_path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    if not env_path.exists():
        return values
    for line in env_path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        values[key.strip()] = value.strip()
    return values


@dataclass(frozen=True)
class AppSettings:
    root_dir: Path
    data_dir: Path
    uploads_dir: Path
    jobs_dir: Path
    exports_dir: Path
    logs_dir: Path
    database_url: str
    api_secret_key: str
    api_secret_key_generated: bool
    token_expire_days: int
    admin_username: str
    admin_password: str
    admin_password_generated: bool
    inline_jobs: bool
    env_file_path: Path
    allowed_upload_extensions: tuple[str, ...] = (".pdf",)
    max_upload_files: int = 10
    max_total_upload_bytes: int = 50 * 1024 * 1024
    max_single_upload_bytes: int = 15 * 1024 * 1024

    @classmethod
    def from_env(cls, root_dir: Path | None = None) -> "AppSettings":
        root = (root_dir or Path(__file__).resolve().parent.parent).resolve()
        env_file = root / ".env"
        env_defaults = load_local_env_file(env_file)

        def read(name: str, default: str) -> str:
            return os.environ.get(name) or env_defaults.get(name) or default

        data_dir = Path(read("APP_DATA_DIR", str(root / "app_data"))).expanduser().resolve()
        database_url = read("APP_DATABASE_URL", f"sqlite:///{data_dir / 'app.db'}")
        api_secret_key = os.environ.get("API_SECRET_KEY") or env_defaults.get("API_SECRET_KEY") or secrets.token_urlsafe(32)
        api_secret_key_generated = "API_SECRET_KEY" not in os.environ and "API_SECRET_KEY" not in env_defaults
        admin_password = os.environ.get("APP_ADMIN_PASSWORD") or env_defaults.get("APP_ADMIN_PASSWORD") or secrets.token_urlsafe(16)
        admin_password_generated = "APP_ADMIN_PASSWORD" not in os.environ and "APP_ADMIN_PASSWORD" not in env_defaults
        return cls(
            root_dir=root,
            data_dir=data_dir,
            uploads_dir=data_dir / "uploads",
            jobs_dir=data_dir / "jobs",
            exports_dir=data_dir / "exports",
            logs_dir=data_dir / "logs",
            database_url=database_url,
            api_secret_key=api_secret_key,
            api_secret_key_generated=api_secret_key_generated,
            token_expire_days=int(read("APP_TOKEN_EXPIRE_DAYS", "30")),
            admin_username=read("APP_ADMIN_USERNAME", "admin"),
            admin_password=admin_password,
            admin_password_generated=admin_password_generated,
            inline_jobs=read("APP_INLINE_JOBS", "false").lower() in {"1", "true", "yes", "on"},
            env_file_path=env_file,
        )

    def ensure_directories(self) -> None:
        for path in (self.data_dir, self.uploads_dir, self.jobs_dir, self.exports_dir, self.logs_dir):
            path.mkdir(parents=True, exist_ok=True)


@lru_cache(maxsize=1)
def get_settings() -> AppSettings:
    settings = AppSettings.from_env()
    settings.ensure_directories()
    return settings
