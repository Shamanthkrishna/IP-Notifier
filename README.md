# IP Change Notifier

A lightweight, cross-platform Python tool that detects when your machine's IP address changes and sends a notification to a Google Chat space via webhook. Designed for office teams where each colleague runs it on their own Windows, Linux, or macOS machine.

## Requirements

- **Python 3.8+**
- **pip** (Python package manager)

## Installation

```bash
git clone <your-repo-url>
cd ip-change-notifier
pip install -r requirements.txt
```

## Setup

Run the interactive setup wizard once:

```bash
python setup.py
```

You will be asked for:
1. Your name
2. A label for your machine (defaults to hostname)
3. Google Chat webhook URL
4. Whether to include public IP in notifications

This creates a `config.json` file in the project directory.

## Register at Startup

### Windows

Open an **Administrator Command Prompt**, navigate to the project folder, and run:

```cmd
install\register_windows.bat
```

This creates a Task Scheduler entry that runs the notifier at every logon.

### Linux / macOS

```bash
bash install/register_linux.sh
```

This registers a **systemd user service** (if available) or a **cron @reboot** job.

## How It Works

1. On startup (or logon), the script runs automatically.
2. It detects the machine's **local/private IP** (and optionally the **public IP**).
3. It compares the current IP against the last known IP stored in `ip_cache.txt`.
4. If the IP has changed (or it's the first run), it sends a **Google Chat card notification** to the configured webhook.
5. A **cooldown** prevents duplicate notifications within a configurable window (default: 5 minutes).
6. Every change is logged to `ip_history.log` in NDJSON format.

## Config Reference

| Field                    | Type   | Default          | Description                                      |
|--------------------------|--------|------------------|--------------------------------------------------|
| `user_name`              | string | —                | Your name, shown in notifications                |
| `hostname_label`         | string | system hostname  | Label for this machine                           |
| `google_chat_webhook_url`| string | —                | Google Chat incoming webhook URL (**required**)   |
| `include_public_ip`      | bool   | `true`           | Fetch and include public IP in notifications     |
| `retry_count`            | int    | `5`              | Number of IP detection retries at boot           |
| `retry_delay_seconds`    | int    | `10`             | Seconds between retries                          |
| `cooldown_minutes`       | int    | `5`              | Minimum minutes between notifications            |
| `cache_file`             | string | `ip_cache.txt`   | File storing the last known IP                   |
| `log_file`               | string | `ip_history.log` | File for IP change history                       |

## Log File Format

`ip_history.log` uses **NDJSON** (one JSON object per line):

```json
{"timestamp": "2026-04-20T09:14:00", "hostname": "DESKTOP-01", "prev_ip": "192.168.1.31", "new_local_ip": "192.168.1.47", "new_public_ip": "103.21.45.12", "status": "changed"}
```

Possible `status` values: `first_run`, `changed`, `no_change`, `error`.

## How to Create a Google Chat Webhook

1. Open **Google Chat** and go to the space where you want notifications.
2. Click the **space name** at the top → **Manage webhooks**.
3. Click **Add webhook**, give it a name (e.g., "IP Notifier"), and click **Save**.
4. Copy the generated **webhook URL**.
5. Paste it when prompted during `python setup.py`.

> Google documentation: [https://developers.google.com/chat/how-tos/webhooks](https://developers.google.com/chat/how-tos/webhooks)

## Troubleshooting

| Issue | Solution |
|-------|----------|
| **"Config not found"** | Run `python setup.py` to create `config.json`. |
| **Network not ready at boot** | The script retries up to 5 times (configurable). Increase `retry_count` or `retry_delay_seconds` in `config.json` if needed. |
| **Webhook returns 4xx/5xx** | Verify the webhook URL is correct and the Chat space still exists. Check `ip_history.log` for error entries. |
| **Permission denied on Linux** | Make sure `register_linux.sh` is run with your user (not root). Check file permissions on the project directory. |
| **Task Scheduler error on Windows** | Run `register_windows.bat` from an Administrator Command Prompt. |
| **Public IP not showing** | Ensure `include_public_ip` is `true` in `config.json`. The ipify service may be temporarily unavailable. |

## For Teams / Colleagues

Each colleague can set up their own instance:

1. Clone or copy the project folder to their machine.
2. Run `pip install -r requirements.txt`.
3. Run `python setup.py` and enter their own details.
4. Run the appropriate startup registration script for their OS.

Each person gets their own `config.json` — notifications identify the sender by name and hostname.
