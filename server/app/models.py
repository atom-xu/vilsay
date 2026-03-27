import datetime as dt

from sqlalchemy import Boolean, DateTime, ForeignKey, Integer, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db import Base


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    email: Mapped[str] = mapped_column(String(320), unique=True, index=True)
    password_hash: Mapped[str] = mapped_column(String(255))
    email_verified: Mapped[bool] = mapped_column(Boolean, default=False)
    verification_token: Mapped[str | None] = mapped_column(String(128), nullable=True, index=True)
    reset_token: Mapped[str | None] = mapped_column(String(128), nullable=True, index=True)
    reset_token_expires_at: Mapped[dt.datetime | None] = mapped_column(DateTime, nullable=True)
    created_at: Mapped[dt.datetime] = mapped_column(DateTime, default=lambda: dt.datetime.now(dt.UTC))

    usage_events: Mapped[list["UsageEvent"]] = relationship(back_populates="user")


class UsageEvent(Base):
    __tablename__ = "usage_events"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    created_at: Mapped[dt.datetime] = mapped_column(DateTime, default=lambda: dt.datetime.now(dt.UTC))
    kind: Mapped[str] = mapped_column(String(32), default="polish")
    duration_ms: Mapped[int | None] = mapped_column(Integer, nullable=True)

    user: Mapped[User] = relationship(back_populates="usage_events")
