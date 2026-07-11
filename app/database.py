from __future__ import annotations

from contextlib import contextmanager
from datetime import datetime, timezone

from sqlalchemy import create_engine
from sqlalchemy.orm import Session, declarative_base, sessionmaker

from app.config import AppSettings, get_settings


Base = declarative_base()


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


def build_engine(settings: AppSettings | None = None):
    resolved = settings or get_settings()
    connect_args = {"check_same_thread": False} if resolved.database_url.startswith("sqlite") else {}
    return create_engine(resolved.database_url, future=True, connect_args=connect_args)


def build_session_factory(settings: AppSettings | None = None):
    engine = build_engine(settings)
    return sessionmaker(bind=engine, autoflush=False, autocommit=False, expire_on_commit=False, class_=Session)


def init_database(session_factory) -> None:
    engine = session_factory.kw["bind"]
    Base.metadata.create_all(bind=engine)


@contextmanager
def session_scope(session_factory):
    session = session_factory()
    try:
        yield session
        session.commit()
    except Exception:
        session.rollback()
        raise
    finally:
        session.close()
