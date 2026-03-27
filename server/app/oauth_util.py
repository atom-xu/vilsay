"""OAuth 开发期占位：生产环境应验证 Apple/Google/微信 服务端签名与 code 换 token。"""

import base64
import hashlib
import json


def decode_jwt_payload_no_verify(token: str) -> dict:
    parts = token.split(".")
    if len(parts) != 3:
        raise ValueError("invalid jwt")
    payload = parts[1]
    pad = "=" * ((4 - len(payload) % 4) % 4)
    data = base64.urlsafe_b64decode(payload + pad)
    return json.loads(data.decode("utf-8"))


def oauth_dev_email(provider: str, key: str) -> str:
    h = hashlib.sha256(key.encode()).hexdigest()[:24]
    return f"{provider}_{h}@oauth.vilsay.local"


def exchange_google_authorization_code(code: str, client_id: str, client_secret: str, redirect_uri: str) -> str:
    """用授权码换 Google id_token，校验后返回 email。"""
    import requests
    from google.auth.transport import requests as google_requests
    from google.oauth2 import id_token

    r = requests.post(
        "https://oauth2.googleapis.com/token",
        data={
            "code": code,
            "client_id": client_id,
            "client_secret": client_secret,
            "redirect_uri": redirect_uri,
            "grant_type": "authorization_code",
        },
        timeout=30,
    )
    if r.status_code != 200:
        raise ValueError(f"google token http {r.status_code}: {r.text[:500]}")
    j = r.json()
    id_tok = j.get("id_token")
    if not id_tok:
        raise ValueError("no id_token in google token response")
    idinfo = id_token.verify_oauth2_token(id_tok, google_requests.Request(), client_id)
    email = idinfo.get("email")
    if not email:
        raise ValueError("no email in google id_token")
    return str(email).lower().strip()


def exchange_wechat_authorization_code(code: str, app_id: str, secret: str) -> str:
    """微信网页授权 code → openid。"""
    import requests

    r = requests.get(
        "https://api.weixin.qq.com/sns/oauth2/access_token",
        params={
            "appid": app_id,
            "secret": secret,
            "code": code,
            "grant_type": "authorization_code",
        },
        timeout=30,
    )
    j = r.json()
    if j.get("errcode"):
        raise ValueError(f"wechat api errcode={j.get('errcode')} msg={j.get('errmsg')}")
    oid = j.get("openid")
    if not oid:
        raise ValueError("no openid in wechat response")
    return str(oid)
