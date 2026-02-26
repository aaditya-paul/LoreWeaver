import os
import bcrypt
from datetime import datetime, timedelta, timezone
from jose import JWTError, jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer

_oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/login")


def _get_secret():
    return os.environ.get("JWT_SECRET", "changeme")

def _get_algorithm():
    return os.environ.get("JWT_ALGORITHM", "HS256")

def _get_expire_minutes():
    return int(os.environ.get("JWT_EXPIRE_MINUTES", "10080"))


# ─── Password hashing (pure bcrypt, no passlib) ───────────────────────────────
def hash_password(plain: str) -> str:
    return bcrypt.hashpw(plain.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")

def verify_password(plain: str, hashed: str) -> bool:
    return bcrypt.checkpw(plain.encode("utf-8"), hashed.encode("utf-8"))


# ─── JWT ──────────────────────────────────────────────────────────────────────
def create_access_token(data: dict) -> str:
    payload = data.copy()
    expire = datetime.now(timezone.utc) + timedelta(minutes=_get_expire_minutes())
    payload.update({"exp": expire})
    return jwt.encode(payload, _get_secret(), algorithm=_get_algorithm())

def decode_token(token: str) -> dict:
    return jwt.decode(token, _get_secret(), algorithms=[_get_algorithm()])


# ─── FastAPI dependency ───────────────────────────────────────────────────────
def get_current_user(token: str = Depends(_oauth2_scheme)):
    """Returns the decoded JWT payload dict {user_id, email}."""
    credentials_exc = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Invalid or expired token",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = decode_token(token)
        user_id: str = payload.get("sub")
        if not user_id:
            raise credentials_exc
        return {"user_id": user_id, "email": payload.get("email")}
    except JWTError:
        raise credentials_exc
