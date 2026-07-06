import base64
import hashlib
import hmac
import time

from app.core.config import settings

PASSWORD_SCHEME = "pbkdf2_sha256"
PASSWORD_ITERATIONS = 260000
SESSION_COOKIE_NAME = "tm_session"
SESSION_TTL_SECONDS = 60 * 60 * 12


def hash_password(password: str, salt: str = "telecom-manager-admin") -> str:
    digest = hashlib.pbkdf2_hmac(
        "sha256",
        password.encode("utf-8"),
        salt.encode("utf-8"),
        PASSWORD_ITERATIONS,
    ).hex()
    return f"{PASSWORD_SCHEME}${PASSWORD_ITERATIONS}${salt}${digest}"


def verify_password(password: str, password_hash: str) -> bool:
    try:
        scheme, iterations, salt, digest = password_hash.split("$", 3)
    except ValueError:
        return False

    if scheme != PASSWORD_SCHEME:
        return False

    candidate = hashlib.pbkdf2_hmac(
        "sha256",
        password.encode("utf-8"),
        salt.encode("utf-8"),
        int(iterations),
    ).hex()
    return hmac.compare_digest(candidate, digest)


def create_session_token(user_id: int) -> str:
    expires_at = int(time.time()) + SESSION_TTL_SECONDS
    payload = f"{user_id}.{expires_at}"
    signature = hmac.new(
        settings.app_secret_key.encode("utf-8"),
        payload.encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()
    raw_token = f"{payload}.{signature}".encode("utf-8")
    return base64.urlsafe_b64encode(raw_token).decode("ascii")


def verify_session_token(token: str | None) -> int | None:
    if not token:
        return None

    try:
        raw_token = base64.urlsafe_b64decode(token.encode("ascii")).decode("utf-8")
        user_id, expires_at, signature = raw_token.split(".", 2)
    except (ValueError, UnicodeDecodeError):
        return None

    payload = f"{user_id}.{expires_at}"
    expected_signature = hmac.new(
        settings.app_secret_key.encode("utf-8"),
        payload.encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()
    if not hmac.compare_digest(signature, expected_signature):
        return None
    if int(expires_at) < int(time.time()):
        return None
    return int(user_id)
