"""
云端 ASR：本地上传 → OSS 临时对象 → 签名 URL → DashScope Paraformer 异步任务（与 macOS 客户端 `DashScopeASRClient` 同路径）。
"""

from __future__ import annotations

import json
import time
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

# DashScope 录音文件识别（与客户端一致）
_SUBMIT = "https://dashscope.aliyuncs.com/api/v1/services/audio/asr/transcription"


def _http_json(
    url: str,
    method: str,
    *,
    headers: dict[str, str],
    body: bytes | None = None,
    timeout: float = 120.0,
) -> dict[str, Any]:
    req = Request(url, data=body, method=method)
    for k, v in headers.items():
        req.add_header(k, v)
    with urlopen(req, timeout=timeout) as resp:
        raw = resp.read()
    return json.loads(raw.decode("utf-8"))


def submit_paraformer_task(api_key: str, file_url: str, *, model: str = "paraformer-v2") -> str:
    payload = {
        "model": model,
        "input": {"file_urls": [file_url]},
        "parameters": {"channel_id": [0], "language_hints": ["zh", "en"]},
    }
    body = json.dumps(payload).encode("utf-8")
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
        "X-DashScope-Async": "enable",
    }
    data = _http_json(_SUBMIT, "POST", headers=headers, body=body)
    out = data.get("output") or {}
    task_id = out.get("task_id")
    if not task_id:
        raise RuntimeError(f"no task_id in response: {data}")
    return str(task_id)


def poll_task_output(api_key: str, task_id: str) -> dict[str, Any]:
    task_url = f"https://dashscope.aliyuncs.com/api/v1/tasks/{task_id}"
    post_headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
    }

    def fetch_output() -> dict[str, Any]:
        try:
            data = _http_json(task_url, "POST", headers=post_headers, body=b"")
        except (HTTPError, URLError, json.JSONDecodeError, TimeoutError, OSError):
            req = Request(task_url, method="GET")
            req.add_header("Authorization", f"Bearer {api_key}")
            with urlopen(req, timeout=60.0) as resp:
                raw = resp.read()
            data = json.loads(raw.decode("utf-8"))
        out = data.get("output")
        if not isinstance(out, dict):
            raise RuntimeError(f"unexpected task response: {data}")
        return out

    for _ in range(120):
        out = fetch_output()
        status = out.get("task_status")
        if status == "FAILED":
            raise RuntimeError(f"task FAILED: {out}")
        if status == "SUCCEEDED":
            return out
        time.sleep(0.5)
    raise TimeoutError("DashScope task polling timeout")


def download_transcription_text(transcription_url: str) -> str:
    req = Request(transcription_url, method="GET")
    with urlopen(req, timeout=60.0) as resp:
        raw = resp.read()
    data = json.loads(raw.decode("utf-8"))
    transcripts = data.get("transcripts")
    if not transcripts or not isinstance(transcripts, list):
        raise RuntimeError(f"no transcripts in {data}")
    first = transcripts[0]
    text = first.get("text") if isinstance(first, dict) else None
    if not text or not isinstance(text, str):
        raise RuntimeError(f"no text in transcript: {data}")
    return text.strip()


def transcribe_public_file_url(*, api_key: str, file_url: str, model: str = "paraformer-v2") -> str:
    task_id = submit_paraformer_task(api_key, file_url, model=model)
    output = poll_task_output(api_key, task_id)
    results = output.get("results")
    if not results or not isinstance(results, list):
        raise RuntimeError(f"no results in task output: {output}")
    for r in results:
        if not isinstance(r, dict):
            continue
        if r.get("subtask_status") != "SUCCEEDED":
            continue
        url_str = r.get("transcription_url")
        if isinstance(url_str, str) and url_str:
            return download_transcription_text(url_str)
    raise RuntimeError(f"no SUCCEEDED subtask: {output}")


def upload_bytes_to_oss(
    *,
    access_key_id: str,
    access_key_secret: str,
    endpoint: str,
    bucket: str,
    data: bytes,
    object_key: str,
) -> str:
    import oss2  # type: ignore[import-untyped]

    auth = oss2.Auth(access_key_id, access_key_secret)
    bucket_inst = oss2.Bucket(auth, endpoint, bucket)
    bucket_inst.put_object(object_key, data)
    # 预签名 GET，供 DashScope 拉取（无需 bucket 公共读）
    url = bucket_inst.sign_url("GET", object_key, 3600, slash_safe=True)
    return str(url)
