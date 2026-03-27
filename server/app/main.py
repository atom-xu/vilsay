import datetime as dt
import logging
import secrets
import uuid

from fastapi import APIRouter, Depends, FastAPI, Header, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from jose import JWTError
from sqlalchemy import func, select, text
from sqlalchemy.orm import Session

from app.asr_routes import asr_router
from app.config import get_settings
from app.db import Base, engine, get_db
from app.email_service import send_reset_email, send_verification_email
from app.models import UsageEvent, User
from app.oauth_util import (
    decode_jwt_payload_no_verify,
    exchange_google_authorization_code,
    exchange_wechat_authorization_code,
    oauth_dev_email,
)
from app.schemas import (
    AppleAuthBody,
    ForgotPasswordBody,
    ForgotPasswordResponse,
    GoogleAuthBody,
    LoginBody,
    MessageResponse,
    RegisterBody,
    RegisterResponse,
    RefreshBody,
    ResetPasswordBody,
    TokenResponse,
    UsageCurrentResponse,
    UsageHistoryItem,
    UsageHistoryResponse,
    UsageRecordBody,
    UsageRecordResponse,
    UserOut,
    VerifyEmailBody,
    VerifyStatusResponse,
    WechatAuthBody,
)
from app.security import (
    create_access_token,
    create_refresh_token,
    decode_token,
    get_user_from_token,
    hash_password,
    verify_password,
)

settings = get_settings()
logger = logging.getLogger(__name__)

app = FastAPI(title="Vilsay API", version="0.4.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

api = APIRouter(prefix="/api/v1")


def _migrate_sqlite() -> None:
    """SQLite 旧库补列（幂等 try/except）。"""
    if not str(engine.url).startswith("sqlite"):
        return
    alters = [
        "ALTER TABLE users ADD COLUMN verification_token VARCHAR(128)",
        "ALTER TABLE users ADD COLUMN reset_token VARCHAR(128)",
        "ALTER TABLE users ADD COLUMN reset_token_expires_at DATETIME",
        "ALTER TABLE usage_events ADD COLUMN duration_ms INTEGER",
    ]
    with engine.connect() as conn:
        for sql in alters:
            try:
                conn.execute(text(sql))
                conn.commit()
            except Exception:
                conn.rollback()


@app.on_event("startup")
def _startup() -> None:
    Base.metadata.create_all(bind=engine)
    _migrate_sqlite()


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


def _month_start_utc() -> dt.datetime:
    now = dt.datetime.now(dt.UTC)
    return now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)


def _year_month_str() -> str:
    now = dt.datetime.now(dt.UTC)
    return f"{now.year:04d}-{now.month:02d}"


def _usage_count(db: Session, user_id: int) -> int:
    start = _month_start_utc()
    stmt = select(func.count()).where(
        UsageEvent.user_id == user_id,
        UsageEvent.created_at >= start,
    )
    return int(db.execute(stmt).scalar_one())


def _reset_at_iso() -> str:
    tz = dt.timezone(dt.timedelta(hours=8))
    now = dt.datetime.now(tz)
    y, m = now.year, now.month
    if m == 12:
        nxt = dt.datetime(y + 1, 1, 1, 0, 0, 0, tzinfo=tz)
    else:
        nxt = dt.datetime(y, m + 1, 1, 0, 0, 0, tzinfo=tz)
    return nxt.isoformat()


def _month_range_utc(month: str) -> tuple[dt.datetime, dt.datetime]:
    y, m = map(int, month.split("-"))
    start = dt.datetime(y, m, 1, tzinfo=dt.UTC)
    if m == 12:
        end = dt.datetime(y + 1, 1, 1, tzinfo=dt.UTC)
    else:
        end = dt.datetime(y, m + 1, 1, tzinfo=dt.UTC)
    return start, end


def _auth_header_token(authorization: str | None) -> str:
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(status_code=401, detail="missing bearer token")
    return authorization.split(" ", 1)[1].strip()


def _token_response_for_user(u: User) -> TokenResponse:
    access = create_access_token(u.id, u.email)
    refresh = create_refresh_token(u.id, u.email)
    return TokenResponse(access_token=access, refresh_token=refresh, user=UserOut(email=u.email))


def get_current_user(
    authorization: str | None = Header(None),
    db: Session = Depends(get_db),
) -> User:
    token = _auth_header_token(authorization)
    user = get_user_from_token(db, token)
    if user is None:
        raise HTTPException(status_code=401, detail="invalid token")
    return user


@api.post("/auth/register", response_model=RegisterResponse)
def register(body: RegisterBody, db: Session = Depends(get_db)) -> RegisterResponse:
    exists = db.execute(select(User).where(User.email == body.email.lower())).scalar_one_or_none()
    if exists is not None:
        raise HTTPException(status_code=400, detail="email already registered")
    vtok = secrets.token_urlsafe(32)
    u = User(
        email=body.email.lower(),
        password_hash=hash_password(body.password),
        email_verified=False,
        verification_token=vtok,
    )
    db.add(u)
    db.commit()
    if settings.smtp_host:
        try:
            send_verification_email(settings, u.email, vtok)
        except Exception:
            logger.exception("register: SMTP send_verification failed")
    return RegisterResponse(
        message="registered",
        verification_token=vtok if settings.dev_expose_verification_token else None,
    )


@api.get("/auth/profile", response_model=UserOut)
def auth_profile(user: User = Depends(get_current_user)) -> UserOut:
    """网页端 / 客户端读取当前登录邮箱（Bearer access token）。"""
    return UserOut(email=user.email)


@api.post("/auth/login", response_model=TokenResponse)
def login(body: LoginBody, db: Session = Depends(get_db)) -> TokenResponse:
    u = db.execute(select(User).where(User.email == body.email.lower())).scalar_one_or_none()
    if u is None or not verify_password(body.password, u.password_hash):
        raise HTTPException(status_code=401, detail="invalid email or password")
    return _token_response_for_user(u)


@api.post("/auth/refresh", response_model=TokenResponse)
def refresh_token(body: RefreshBody, db: Session = Depends(get_db)) -> TokenResponse:
    try:
        data = decode_token(body.refresh_token)
    except JWTError:
        raise HTTPException(status_code=401, detail="invalid refresh token") from None
    if data.get("typ") != "refresh":
        raise HTTPException(status_code=401, detail="not a refresh token")
    uid = int(data.get("sub", 0))
    u = db.get(User, uid)
    if u is None:
        raise HTTPException(status_code=401, detail="user not found")
    return _token_response_for_user(u)


@api.post("/auth/apple", response_model=TokenResponse)
def auth_apple(body: AppleAuthBody, db: Session = Depends(get_db)) -> TokenResponse:
    try:
        payload = decode_jwt_payload_no_verify(body.identity_token)
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"invalid identity token: {e}") from e
    sub = str(payload.get("sub", "")).strip()
    if not sub:
        raise HTTPException(status_code=400, detail="missing sub in apple token")
    raw_email = payload.get("email")
    email = str(raw_email).lower() if raw_email else f"apple_{sub}@oauth.vilsay.local"
    u = db.execute(select(User).where(User.email == email)).scalar_one_or_none()
    if u is None:
        u = User(
            email=email,
            password_hash=hash_password(secrets.token_hex(16)),
            email_verified=True,
            verification_token=None,
        )
        db.add(u)
        db.commit()
        db.refresh(u)
    else:
        if not u.email_verified:
            u.email_verified = True
            db.commit()
            db.refresh(u)
    return _token_response_for_user(u)


@api.post("/auth/google", response_model=TokenResponse)
def auth_google(body: GoogleAuthBody, db: Session = Depends(get_db)) -> TokenResponse:
    if not settings.google_client_id or not settings.google_client_secret:
        raise HTTPException(
            status_code=400,
            detail={"error": "oauth_not_configured", "message": "Google 登录未配置"},
        )
    code = body.code.strip()
    if not code:
        raise HTTPException(status_code=400, detail="missing code")
    try:
        email = exchange_google_authorization_code(
            code,
            settings.google_client_id,
            settings.google_client_secret,
            settings.google_oauth_redirect_uri,
        )
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"google oauth failed: {e}") from e
    u = db.execute(select(User).where(User.email == email)).scalar_one_or_none()
    if u is None:
        u = User(
            email=email,
            password_hash=hash_password(secrets.token_hex(16)),
            email_verified=True,
            verification_token=None,
        )
        db.add(u)
        db.commit()
        db.refresh(u)
    else:
        if not u.email_verified:
            u.email_verified = True
            db.commit()
            db.refresh(u)
    return _token_response_for_user(u)


@api.post("/auth/wechat", response_model=TokenResponse)
def auth_wechat(body: WechatAuthBody, db: Session = Depends(get_db)) -> TokenResponse:
    if not settings.wechat_app_id or not settings.wechat_app_secret:
        raise HTTPException(
            status_code=400,
            detail={"error": "oauth_not_configured", "message": "微信登录未配置"},
        )
    code = body.code.strip()
    if not code:
        raise HTTPException(status_code=400, detail="missing code")
    try:
        openid = exchange_wechat_authorization_code(code, settings.wechat_app_id, settings.wechat_app_secret)
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"wechat oauth failed: {e}") from e
    email = f"wechat_{openid}@oauth.vilsay.local"
    u = db.execute(select(User).where(User.email == email)).scalar_one_or_none()
    if u is None:
        u = User(
            email=email,
            password_hash=hash_password(secrets.token_hex(16)),
            email_verified=True,
            verification_token=None,
        )
        db.add(u)
        db.commit()
        db.refresh(u)
    return _token_response_for_user(u)


@api.get("/auth/verify-status", response_model=VerifyStatusResponse)
def verify_status(email: str, db: Session = Depends(get_db)) -> VerifyStatusResponse:
    u = db.execute(select(User).where(User.email == email.lower())).scalar_one_or_none()
    if u is None:
        raise HTTPException(status_code=404, detail="not found")
    return VerifyStatusResponse(verified=u.email_verified)


@api.post("/auth/verify-email", response_model=TokenResponse)
def verify_email(body: VerifyEmailBody, db: Session = Depends(get_db)) -> TokenResponse:
    u = db.execute(select(User).where(User.verification_token == body.token)).scalar_one_or_none()
    if u is None:
        raise HTTPException(status_code=400, detail="invalid or expired verification token")
    u.email_verified = True
    u.verification_token = None
    db.commit()
    db.refresh(u)
    return _token_response_for_user(u)


@api.post("/auth/logout", response_model=MessageResponse)
def logout(user: User = Depends(get_current_user)) -> MessageResponse:
    return MessageResponse(message="logged_out")


@api.post("/auth/forgot-password", response_model=ForgotPasswordResponse)
def forgot_password(body: ForgotPasswordBody, db: Session = Depends(get_db)) -> ForgotPasswordResponse:
    msg = "if_account_exists_email_sent"
    u = db.execute(select(User).where(User.email == body.email.lower())).scalar_one_or_none()
    if u is None:
        return ForgotPasswordResponse(message=msg)
    tok = secrets.token_urlsafe(32)
    u.reset_token = tok
    u.reset_token_expires_at = dt.datetime.now(dt.UTC) + dt.timedelta(hours=1)
    db.commit()
    dev_tok: str | None = None
    if settings.smtp_host:
        try:
            send_reset_email(settings, u.email, tok)
        except Exception:
            logger.exception("forgot_password: SMTP send_reset failed")
    if settings.dev_expose_verification_token:
        dev_tok = tok
    return ForgotPasswordResponse(message=msg, reset_token=dev_tok)


@api.post("/auth/reset-password", response_model=MessageResponse)
def reset_password(body: ResetPasswordBody, db: Session = Depends(get_db)) -> MessageResponse:
    u = db.execute(select(User).where(User.reset_token == body.token)).scalar_one_or_none()
    if u is None:
        raise HTTPException(status_code=400, detail="invalid or expired token")
    exp = u.reset_token_expires_at
    now_utc = dt.datetime.now(dt.UTC)
    if exp is None:
        raise HTTPException(status_code=400, detail="invalid or expired token")
    if exp.tzinfo is None:
        exp = exp.replace(tzinfo=dt.UTC)
    if exp < now_utc:
        raise HTTPException(status_code=400, detail="invalid or expired token")
    u.password_hash = hash_password(body.new_password)
    u.reset_token = None
    u.reset_token_expires_at = None
    db.commit()
    return MessageResponse(message="password_reset")


@api.get("/usage/current", response_model=UsageCurrentResponse)
def usage_current(user: User = Depends(get_current_user), db: Session = Depends(get_db)) -> UsageCurrentResponse:
    used = _usage_count(db, user.id)
    return UsageCurrentResponse(used=used, quota=settings.free_monthly_quota, year_month=_year_month_str())


@api.get("/usage/history", response_model=UsageHistoryResponse)
def usage_history(
    page: int = 1,
    per_page: int = 20,
    month: str | None = None,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> UsageHistoryResponse:
    base = select(UsageEvent).where(UsageEvent.user_id == user.id)
    count_base = select(func.count()).select_from(UsageEvent).where(UsageEvent.user_id == user.id)
    if month:
        start, end = _month_range_utc(month)
        base = base.where(UsageEvent.created_at >= start, UsageEvent.created_at < end)
        count_base = count_base.where(UsageEvent.created_at >= start, UsageEvent.created_at < end)
    total = int(db.execute(count_base).scalar_one())
    offset = max(0, (page - 1) * per_page)
    stmt = base.order_by(UsageEvent.created_at.desc()).offset(offset).limit(per_page)
    rows = db.execute(stmt).scalars().all()
    data = [
        UsageHistoryItem(
            id=r.id,
            type=r.kind,
            created_at=r.created_at.replace(tzinfo=dt.UTC).isoformat() if r.created_at.tzinfo is None else r.created_at.isoformat(),
            duration_ms=r.duration_ms,
        )
        for r in rows
    ]
    total_pages = max(1, (total + per_page - 1) // per_page) if total > 0 else 1
    return UsageHistoryResponse(
        data=data,
        pagination={
            "page": page,
            "per_page": per_page,
            "total": total,
            "total_pages": total_pages,
        },
    )


@api.post("/usage/record", response_model=UsageRecordResponse)
def usage_record(
    body: UsageRecordBody,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> UsageRecordResponse:
    used = _usage_count(db, user.id)
    if used >= settings.free_monthly_quota:
        raise HTTPException(
            status_code=402,
            detail={
                "error": "quota_exceeded",
                "message": "本月免费次数已用完",
                "detail": None,
                "request_id": str(uuid.uuid4()),
                "upgrade_url": "https://vilsay.com/pricing",
            },
        )
    db.add(UsageEvent(user_id=user.id, kind=body.type, duration_ms=body.duration_ms))
    db.commit()
    new_used = used + 1
    remaining = max(0, settings.free_monthly_quota - new_used)
    return UsageRecordResponse(
        remaining=remaining,
        total=settings.free_monthly_quota,
        reset_at=_reset_at_iso(),
    )


api.include_router(asr_router)
app.include_router(api)
