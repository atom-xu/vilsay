"""SMTP 发信（验证邮件 / 密码重置）。失败仅打日志，不抛给 HTTP。"""

from __future__ import annotations

import logging
import smtplib
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText

from app.config import Settings

logger = logging.getLogger(__name__)


def _send_html(
    settings: Settings,
    to_addr: str,
    subject: str,
    html_body: str,
) -> None:
    if not settings.smtp_host or not settings.smtp_user or not settings.smtp_password:
        logger.debug("SMTP 未完整配置，跳过发信")
        return
    msg = MIMEMultipart("alternative")
    msg["Subject"] = subject
    msg["From"] = settings.smtp_from
    msg["To"] = to_addr
    msg.attach(MIMEText(html_body, "html", "utf-8"))

    port = int(settings.smtp_port)
    with smtplib.SMTP(settings.smtp_host, port, timeout=30) as smtp:
        smtp.starttls()
        smtp.login(settings.smtp_user, settings.smtp_password)
        smtp.sendmail(settings.smtp_from, [to_addr], msg.as_string())


def send_verification_email(settings: Settings, to_addr: str, token: str) -> None:
    """注册后验证链接：`vilsay://auth/verify?token=...`"""
    link = f"vilsay://auth/verify?token={token}"
    html = f"""
    <html><body>
    <p>请点击以下链接完成邮箱验证（将打开 Vilsay）：</p>
    <p><a href="{link}">{link}</a></p>
    <p>若无法点击，请复制到浏览器或终端：<code>open "{link}"</code></p>
    </body></html>
    """
    try:
        _send_html(settings, to_addr, "验证您的 Vilsay 邮箱", html)
    except Exception:
        logger.exception("send_verification_email failed to=%s", to_addr)


def send_reset_email(settings: Settings, to_addr: str, token: str) -> None:
    """密码重置：`vilsay://auth/reset-password?token=...`（客户端可接）。"""
    link = f"vilsay://auth/reset-password?token={token}"
    html = f"""
    <html><body>
    <p>您申请了重置 Vilsay 密码，请点击：</p>
    <p><a href="{link}">{link}</a></p>
    <p>链接 1 小时内有效。若非本人操作请忽略。</p>
    </body></html>
    """
    try:
        _send_html(settings, to_addr, "重置您的 Vilsay 密码", html)
    except Exception:
        logger.exception("send_reset_email failed to=%s", to_addr)
