from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: str = "sqlite:///./vilsay.db"
    jwt_secret: str = "dev-change-me-use-openssl-rand-hex-32"
    jwt_algorithm: str = "HS256"
    jwt_access_days: int = 7
    jwt_refresh_days: int = 30
    free_monthly_quota: int = 500
    dev_expose_verification_token: bool = True

    # SMTP（注册验证 / 密码重置）
    smtp_host: str | None = None
    smtp_port: int = 587
    smtp_user: str | None = None
    smtp_password: str | None = None
    smtp_from: str = "noreply@vilsay.com"

    # Google / 微信 OAuth（服务端换 token）
    google_client_id: str | None = None
    google_client_secret: str | None = None
    google_oauth_redirect_uri: str = "vilsay://auth/callback"

    wechat_app_id: str | None = None
    wechat_app_secret: str | None = None

    # 云端 ASR 代理（`/api/v1/asr/transcribe`）：DashScope + OSS
    dashscope_api_key: str | None = None
    oss_access_key_id: str | None = None
    oss_access_key_secret: str | None = None
    oss_endpoint: str | None = None
    oss_bucket: str | None = None
    asr_internal_key: str | None = None


@lru_cache
def get_settings() -> Settings:
    return Settings()
