import uuid
import logging
from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, EmailStr
from sqlalchemy.orm import Session

from db.models import User
from auth.deps import hash_password, verify_password, create_access_token, get_current_user

log = logging.getLogger("loreweaver.auth")
router = APIRouter(prefix="/auth", tags=["auth"])


# ─── Schemas ──────────────────────────────────────────────────────────────────
class AuthRequest(BaseModel):
    email: str
    password: str

class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user_id: str
    email: str


# ─── Dependency injected from main.py ─────────────────────────────────────────
def get_db():
    raise NotImplementedError("Override via app.dependency_overrides")


# ─── Routes ───────────────────────────────────────────────────────────────────
@router.post("/check-email")
def check_email(body: dict, db: Session = Depends(get_db)):
    """Returns whether the email is already registered."""
    email = body.get("email", "").lower().strip()
    exists = db.query(User).filter_by(email=email).first() is not None
    return {"exists": exists}


@router.post("/register", response_model=TokenResponse, status_code=201)
def register(req: AuthRequest, db: Session = Depends(get_db)):
    email = req.email.lower().strip()
    if db.query(User).filter_by(email=email).first():
        raise HTTPException(status_code=400, detail="Email already registered")

    user = User(
        id=str(uuid.uuid4()),
        email=email,
        hashed_password=hash_password(req.password),
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    log.info(f"[register] New user: {email}")

    token = create_access_token({"sub": user.id, "email": user.email})
    return TokenResponse(access_token=token, user_id=user.id, email=user.email)


@router.post("/login", response_model=TokenResponse)
def login(req: AuthRequest, db: Session = Depends(get_db)):
    email = req.email.lower().strip()
    user = db.query(User).filter_by(email=email).first()
    if not user or not verify_password(req.password, user.hashed_password):
        raise HTTPException(status_code=401, detail="Invalid email or password")

    log.info(f"[login] User logged in: {email}")
    token = create_access_token({"sub": user.id, "email": user.email})
    return TokenResponse(access_token=token, user_id=user.id, email=user.email)


@router.get("/me")
def me(current_user: dict = Depends(get_current_user)):
    return current_user
