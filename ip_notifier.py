#!/usr/bin/env python3
"""IP Change Notifier — detects local/public IP changes and sends Google Chat notifications."""

import json
import logging
import os
import platform
import socket
import sys
import time
from datetime import datetime, timedelta
from pathlib import Path
from typing import Optional

import requests

# ---------------------------------------------------------------------------
# Logging setup
# ---------------------------------------------------------------------------
LOG_LEVEL = os.environ.get("LOG_LEVEL", "INFO").upper()
logging.basicConfig(
    level=getattr(logging, LOG_LEVEL, logging.INFO),
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger(__name__)

BASE_DIR = Path(__file__).resolve().parent


# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
def load_config() -> dict:
    """Load and validate config.json; exit with a friendly message if missing."""
    config_path = BASE_DIR / "config.json"
    if not config_path.exists():
        print("Config not found. Please run: python setup.py")
        sys.exit(1)

    with open(config_path, "r", encoding="utf-8") as fh:
        config: dict = json.load(fh)

    webhook = config.get("google_chat_webhook_url", "").strip()
    if not webhook:
        logger.error("google_chat_webhook_url is missing or empty in config.json.")
        sys.exit(1)

    # Defaults for optional keys
    config.setdefault("include_public_ip", True)
    config.setdefault("retry_count", 5)
    config.setdefault("retry_delay_seconds", 10)
    config.setdefault("cooldown_minutes", 5)
    config.setdefault("cache_file", "ip_cache.txt")
    config.setdefault("log_file", "ip_history.log")
    return config


# ---------------------------------------------------------------------------
# IP detection helpers
# ---------------------------------------------------------------------------
def get_local_ip() -> str:
    """Return the local/private IP address of the active network interface."""
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            # Connecting to a public address (no data sent) to find the active interface
            s.connect(("8.8.8.8", 80))
            return s.getsockname()[0]
    except OSError as exc:
        logger.warning("Failed to detect local IP: %s", exc)
        raise


def get_public_ip(timeout: int = 5) -> Optional[str]:
    """Fetch the public/external IP via ipify. Returns None on failure."""
    try:
        resp = requests.get(
            "https://api.ipify.org?format=json", timeout=timeout
        )
        resp.raise_for_status()
        return resp.json().get("ip")
    except (requests.RequestException, ValueError, KeyError) as exc:
        logger.warning("Failed to fetch public IP: %s", exc)
        return None


def detect_ip_with_retries(
    retry_count: int, retry_delay: int
) -> Optional[str]:
    """Try to detect the local IP with retries (useful at boot time)."""
    for attempt in range(1, retry_count + 1):
        try:
            local_ip = get_local_ip()
            logger.info("Local IP detected on attempt %d: %s", attempt, local_ip)
            return local_ip
        except OSError:
            logger.info(
                "Attempt %d/%d failed. Retrying in %ds…",
                attempt,
                retry_count,
                retry_delay,
            )
            if attempt < retry_count:
                time.sleep(retry_delay)
    return None


# ---------------------------------------------------------------------------
# Cache helpers
# ---------------------------------------------------------------------------
def read_cache(cache_path: Path) -> tuple[Optional[str], Optional[datetime]]:
    """Read the cached IP and last-notification timestamp from the cache file.

    Returns:
        (cached_ip, last_notified_dt) — either may be None.
    """
    if not cache_path.exists():
        return None, None

    try:
        data = json.loads(cache_path.read_text(encoding="utf-8"))
        cached_ip = data.get("ip")
        ts_str = data.get("last_notified")
        last_notified = (
            datetime.fromisoformat(ts_str) if ts_str else None
        )
        return cached_ip, last_notified
    except (json.JSONDecodeError, ValueError, OSError) as exc:
        logger.warning("Cache file unreadable, treating as first run: %s", exc)
        return None, None


def write_cache(
    cache_path: Path, ip: str, last_notified: datetime
) -> None:
    """Persist the current IP and notification timestamp to the cache file."""
    data = {
        "ip": ip,
        "last_notified": last_notified.isoformat(),
    }
    cache_path.write_text(json.dumps(data), encoding="utf-8")
    logger.debug("Cache updated: %s", data)


# ---------------------------------------------------------------------------
# History log
# ---------------------------------------------------------------------------
def append_log(
    log_path: Path,
    hostname: str,
    prev_ip: Optional[str],
    new_local_ip: Optional[str],
    new_public_ip: Optional[str],
    status: str,
) -> None:
    """Append an NDJSON entry to the IP history log."""
    entry = {
        "timestamp": datetime.now().isoformat(timespec="seconds"),
        "hostname": hostname,
        "prev_ip": prev_ip or "",
        "new_local_ip": new_local_ip or "",
        "new_public_ip": new_public_ip or "",
        "status": status,
    }
    with open(log_path, "a", encoding="utf-8") as fh:
        fh.write(json.dumps(entry) + "\n")
    logger.debug("Log entry appended: %s", entry)


# ---------------------------------------------------------------------------
# Google Chat notification
# ---------------------------------------------------------------------------
def build_chat_card(
    hostname: str,
    prev_ip: Optional[str],
    new_local_ip: str,
    public_ip: Optional[str],
    changed_at: str,
) -> dict:
    """Build a Google Chat Cards v2 payload for the REST API endpoint."""
    widgets = [
        {"decoratedText": {"topLabel": "Hostname", "text": hostname}},
        {"decoratedText": {"topLabel": "Previous IP", "text": prev_ip or "N/A"}},
        {"decoratedText": {"topLabel": "New Local IP", "text": new_local_ip}},
    ]
    if public_ip:
        widgets.append(
            {"decoratedText": {"topLabel": "Public IP", "text": public_ip}}
        )
    widgets.append(
        {"decoratedText": {"topLabel": "Changed at", "text": changed_at}}
    )

    return {
        "cardsV2": [
            {
                "cardId": "ip-change-notification",
                "card": {
                    "header": {
                        "title": "IP Address Changed",
                        "subtitle": f"{hostname} · {changed_at}",
                    },
                    "sections": [{"widgets": widgets}],
                },
            }
        ]
    }


def send_notification(webhook_url: str, payload: dict) -> bool:
    """POST the card payload to a Google Chat webhook. Returns True on success."""
    try:
        resp = requests.post(
            webhook_url,
            json=payload,
            headers={"Content-Type": "application/json; charset=UTF-8"},
            timeout=10,
        )
        resp.raise_for_status()
        logger.info("Notification sent successfully.")
        return True
    except requests.RequestException as exc:
        logger.error("Failed to send notification: %s", exc)
        return False


# ---------------------------------------------------------------------------
# Main workflow
# ---------------------------------------------------------------------------
def main() -> None:
    """Entry point — detect IP changes and notify via Google Chat."""
    config = load_config()

    hostname = config.get("hostname_label") or socket.gethostname()
    cache_path = BASE_DIR / config["cache_file"]
    log_path = BASE_DIR / config["log_file"]
    cooldown = timedelta(minutes=config["cooldown_minutes"])
    include_public = config["include_public_ip"]
    webhook_url = config["google_chat_webhook_url"]

    # --- Detect local IP with retries ---
    local_ip = detect_ip_with_retries(
        config["retry_count"], config["retry_delay_seconds"]
    )
    if local_ip is None:
        logger.error("Could not detect local IP after all retries.")
        append_log(log_path, hostname, None, None, None, "error")
        sys.exit(1)

    # --- Read cache ---
    cached_ip, last_notified = read_cache(cache_path)
    now = datetime.now()

    if cached_ip is None:
        status = "first_run"
        logger.info("First run detected — no cache found.")
    elif cached_ip == local_ip:
        status = "no_change"
        logger.info("IP unchanged (%s). Nothing to do.", local_ip)
        return
    else:
        status = "changed"
        logger.info("IP changed: %s → %s", cached_ip, local_ip)

    # --- Cooldown check ---
    if last_notified and (now - last_notified) < cooldown:
        remaining = cooldown - (now - last_notified)
        logger.info(
            "Cooldown active (%s remaining). Skipping notification.",
            remaining,
        )
        # Still update cache and log
        write_cache(cache_path, local_ip, last_notified)
        append_log(log_path, hostname, cached_ip, local_ip, None, status)
        return

    # --- Fetch public IP if configured ---
    public_ip = get_public_ip() if include_public else None

    # --- Format timestamp ---
    changed_at = now.strftime("%d %b %Y, %I:%M %p")

    # --- Send Google Chat notification ---
    payload = build_chat_card(hostname, cached_ip, local_ip, public_ip, changed_at)
    sent = send_notification(webhook_url, payload)

    # --- Update cache & log ---
    write_cache(cache_path, local_ip, now)
    append_log(
        log_path,
        hostname,
        cached_ip,
        local_ip,
        public_ip,
        status if sent else "error",
    )


if __name__ == "__main__":
    main()
