import datetime as dt

from jose import JWTError, jwt
from passlib.context import CryptContext
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.config import get_settings
from app.models import User

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
settings = get_settings()


def hash_password(raw: str) -> str:
    return pwd_context.hash(raw)


def verify_password(raw: str, hashed: str) -> bool:
    return pwd_context.verify(raw, hashed)


def create_access_token(user_id: int, email: str) -> str:
    now = dt.datetime.now(dt.UTC)
    exp = now + dt.timedelta(days=settings.jwt_access_days)
    payload = {"sub": str(user_id), "email": email, "exp": exp, "iat": now}
    return jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)


def create_refresh_token(user_id: int, email: str) -> str:
    now = dt.datetime.now(dt.UTC)
    exp = now + dt.timedelta(days=settings.jwt_refresh_days)
    payload = {"sub": str(user_id), "email": email, "exp": exp, "iat": now, "typ": "refresh"}
    return jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)


def decode_token(token: str) -> dict:
    return jwt.decode(token, settings.jwt_secret, algorithms=[settings.jwt_algorithm])


def get_user_from_token(db: Session, token: str) -> User | None:
    try:
        data = decode_token(token)
        if data.get("typ") == "refresh":
            return None
        uid = int(data.get("sub", 0))
    except (JWTError, ValueError, TypeError):
        return None
    if uid <= 0:
        return None
    return db.execute(select(User).where(User.id == uid)).scalar_one_or_none()
