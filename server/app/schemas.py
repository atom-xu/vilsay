from pydantic import BaseModel, EmailStr, Field


class RegisterBody(BaseModel):
    email: EmailStr
    password: str = Field(min_length=8, max_length=128)


class LoginBody(BaseModel):
    email: EmailStr
    password: str


class UserOut(BaseModel):
    email: str


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    user: UserOut | None = None


class RefreshBody(BaseModel):
    refresh_token: str


class UsageCurrentResponse(BaseModel):
    used: int
    quota: int
    year_month: str
    plan: str = "free"


class MessageResponse(BaseModel):
    message: str


class AsrTranscribeResponse(BaseModel):
    text: str


class RegisterResponse(BaseModel):
    message: str
    verification_token: str | None = None


class UsageRecordBody(BaseModel):
    type: str = "polish"
    duration_ms: int
    asr_provider: str
    client_version: str


class UsageRecordResponse(BaseModel):
    remaining: int
    total: int
    reset_at: str


class AppleAuthBody(BaseModel):
    identity_token: str
    authorization_code: str | None = None


class GoogleAuthBody(BaseModel):
    code: str


class WechatAuthBody(BaseModel):
    code: str


class VerifyEmailBody(BaseModel):
    token: str


class VerifyStatusResponse(BaseModel):
    verified: bool


class ForgotPasswordBody(BaseModel):
    email: EmailStr


class ForgotPasswordResponse(BaseModel):
    message: str
    reset_token: str | None = None


class ResetPasswordBody(BaseModel):
    token: str
    new_password: str = Field(min_length=8, max_length=128)


class UsageHistoryItem(BaseModel):
    id: int
    type: str
    created_at: str
    duration_ms: int | None = None


class UsageHistoryResponse(BaseModel):
    data: list[UsageHistoryItem]
    pagination: dict
