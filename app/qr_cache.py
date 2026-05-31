from __future__ import annotations

import hashlib
import json
import logging
from typing import Any

logger = logging.getLogger(__name__)


class QrInvoiceCache:
    def __init__(self, redis_url: str | None, ttl_seconds: int) -> None:
        self.ttl_seconds = ttl_seconds
        self._client = None
        if not redis_url:
            return
        try:
            import redis

            self._client = redis.Redis.from_url(redis_url, decode_responses=True)
            self._client.ping()
        except Exception as exc:
            logger.warning("Redis QR cache disabled: %s", exc)
            self._client = None

    @property
    def enabled(self) -> bool:
        return self._client is not None

    def get(self, raw_text: str) -> dict[str, Any] | None:
        if self._client is None:
            return None
        cached = self._client.get(self._key(raw_text))
        if not cached:
            return None
        try:
            data = json.loads(cached)
        except json.JSONDecodeError:
            return None
        return data if isinstance(data, dict) else None

    def set(self, raw_text: str, value: dict[str, Any]) -> None:
        if self._client is None:
            return
        self._client.setex(
            self._key(raw_text),
            self.ttl_seconds,
            json.dumps(value, ensure_ascii=False),
        )

    @staticmethod
    def _key(raw_text: str) -> str:
        digest = hashlib.sha256(raw_text.strip().encode("utf-8")).hexdigest()
        return f"invoice_qr:parse:{digest}"


class InvoiceInfoCache:
    def __init__(self, redis_url: str | None, ttl_seconds: int) -> None:
        self.ttl_seconds = ttl_seconds
        self._client = None
        if not redis_url:
            return
        try:
            import redis

            self._client = redis.Redis.from_url(redis_url, decode_responses=True)
            self._client.ping()
        except Exception as exc:
            logger.warning("Redis invoice info cache disabled: %s", exc)
            self._client = None

    def get(self, invoice_key: str) -> dict[str, Any] | None:
        if self._client is None:
            return None
        cached = self._client.get(self._key(invoice_key))
        if not cached:
            return None
        try:
            data = json.loads(cached)
        except json.JSONDecodeError:
            return None
        return data if isinstance(data, dict) else None

    def set(self, invoice_key: str, value: dict[str, Any]) -> None:
        if self._client is None:
            return
        self._client.setex(
            self._key(invoice_key),
            self.ttl_seconds,
            json.dumps(value, ensure_ascii=False, default=str),
        )

    @staticmethod
    def _key(invoice_key: str) -> str:
        digest = hashlib.sha256(invoice_key.encode("utf-8")).hexdigest()
        return f"invoice:info:{digest}"
