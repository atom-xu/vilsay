"""云端 ASR：接收本机上传的音频 → OSS 签名 URL → Paraformer。"""

from __future__ import annotations

import uuid

from fastapi import APIRouter, File, Form, Header, HTTPException, UploadFile

from app.asr_service import transcribe_public_file_url, upload_bytes_to_oss
from app.config import get_settings
from app.schemas import AsrTranscribeResponse

asr_router = APIRouter(prefix="/asr", tags=["asr"])


def _verify_asr_access(
    authorization: str | None,
    x_vilsay_asr_key: str | None,
) -> None:
    settings = get_settings()
    if settings.asr_internal_key and x_vilsay_asr_key == settings.asr_internal_key:
        return
    if settings.dashscope_api_key and authorization:
        auth = authorization.strip()
        if auth.lower().startswith("bearer "):
            token = auth.split(" ", 1)[1].strip()
            if token == settings.dashscope_api_key:
                return
    raise HTTPException(
        status_code=401,
        detail="需要 X-Vilsay-Internal-ASR-Key（与 ASR_INTERNAL_KEY 一致）或 Authorization: Bearer（与 DASHSCOPE_API_KEY 一致）",
    )


@asr_router.post("/transcribe", response_model=AsrTranscribeResponse)
async def transcribe_uploaded_audio(
    file: UploadFile = File(...),
    model: str = Form("paraformer-v2"),
    authorization: str | None = Header(None),
    x_vilsay_asr_key: str | None = Header(None, alias="X-Vilsay-Internal-ASR-Key"),
) -> AsrTranscribeResponse:
    _verify_asr_access(authorization, x_vilsay_asr_key)
    settings = get_settings()
    if not settings.dashscope_api_key:
        raise HTTPException(
            status_code=503,
            detail="DASHSCOPE_API_KEY not set on server",
        )
    
    # 🔧 测试模式：如果 OSS 未配置，使用模拟转写（仅用于诊断）
    oss_configured = (
        settings.oss_access_key_id
        and settings.oss_access_key_secret
        and settings.oss_endpoint
        and settings.oss_bucket
    )
    
    if not oss_configured:
        # 测试模式：直接返回固定文本（验证 API Key 有效）
        return AsrTranscribeResponse(
            text="【测试模式】OSS 未配置，使用模拟结果。请配置 OSS_ACCESS_KEY_ID 等环境变量以启用真实云端 ASR。"
        )

    raw = await file.read()
    if not raw:
        raise HTTPException(status_code=400, detail="empty file")

    suffix = ".wav"
    name = (file.filename or "").lower()
    if name.endswith(".caf"):
        suffix = ".caf"
    elif name.endswith(".mp3"):
        suffix = ".mp3"
    elif name.endswith(".m4a"):
        suffix = ".m4a"

    key = f"asr-temp/{uuid.uuid4().hex}{suffix}"
    try:
        public_url = upload_bytes_to_oss(
            access_key_id=settings.oss_access_key_id,
            access_key_secret=settings.oss_access_key_secret,
            endpoint=settings.oss_endpoint,
            bucket=settings.oss_bucket,
            data=raw,
            object_key=key,
        )
        text = transcribe_public_file_url(
            api_key=settings.dashscope_api_key,
            file_url=public_url,
            model=model,
        )
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"ASR failed: {e!s}") from e

    if not text.strip():
        raise HTTPException(status_code=502, detail="ASR returned empty text")
    return AsrTranscribeResponse(text=text)
