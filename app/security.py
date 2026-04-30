from __future__ import annotations

import base64
import hashlib
import hmac
import json
import secrets
from datetime import datetime, timedelta, timezone


PBKDF2_ITERATIONS = 120_000


def hash_password(password: str, salt: str | None = None) -> str:
    salt_value = salt or secrets.token_hex(16)
    digest = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt_value.encode("utf-8"), PBKDF2_ITERATIONS)
    return f"pbkdf2_sha256${PBKDF2_ITERATIONS}${salt_value}${digest.hex()}"


def verify_password(password: str, encoded: str) -> bool:
    try:
        algorithm, iterations, salt, stored_hash = encoded.split("$", 3)
    except ValueError:
        return False
    if algorithm != "pbkdf2_sha256":
        return False
    digest = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt.encode("utf-8"), int(iterations))
    return hmac.compare_digest(digest.hex(), stored_hash)


def _sign(payload: bytes, secret_key: str) -> str:
    return hmac.new(secret_key.encode("utf-8"), payload, hashlib.sha256).hexdigest()


def create_access_token(user_id: int, role: str, secret_key: str, expire_days: int) -> str:
    payload = {
        "sub": user_id,
        "role": role,
        "exp": int((datetime.now(timezone.utc) + timedelta(days=expire_days)).timestamp()),
    }
    raw = json.dumps(payload, separators=(",", ":"), sort_keys=True).encode("utf-8")
    signed = {"payload": base64.urlsafe_b64encode(raw).decode("ascii"), "sig": _sign(raw, secret_key)}
    return base64.urlsafe_b64encode(json.dumps(signed, separators=(",", ":")).encode("utf-8")).decode("ascii")


def decode_access_token(token: str, secret_key: str) -> dict[str, int | str]:
    raw_token = base64.urlsafe_b64decode(token.encode("ascii"))
    signed = json.loads(raw_token.decode("utf-8"))
    payload_bytes = base64.urlsafe_b64decode(signed["payload"].encode("ascii"))
    if not hmac.compare_digest(signed["sig"], _sign(payload_bytes, secret_key)):
        raise ValueError("invalid token signature")
    payload = json.loads(payload_bytes.decode("utf-8"))
    if int(payload["exp"]) < int(datetime.now(timezone.utc).timestamp()):
        raise ValueError("token expired")
    return payload
