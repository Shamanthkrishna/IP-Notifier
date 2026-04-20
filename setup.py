#!/usr/bin/env python3
"""Interactive CLI setup wizard for IP Change Notifier.

Run once to generate config.json with user-specific settings.
"""

import json
import socket
import sys
from pathlib import Path


BASE_DIR = Path(__file__).resolve().parent
CONFIG_PATH = BASE_DIR / "config.json"


def ask(prompt: str, default: str = "") -> str:
    """Prompt the user for input with an optional default value."""
    suffix = f" [{default}]" if default else ""
    value = input(f"{prompt}{suffix}: ").strip()
    return value if value else default


def ask_yes_no(prompt: str, default: bool = True) -> bool:
    """Prompt the user for a yes/no answer."""
    hint = "Y/n" if default else "y/N"
    value = input(f"{prompt} ({hint}): ").strip().lower()
    if not value:
        return default
    return value in ("y", "yes")


def run_setup() -> None:
    """Run the interactive setup wizard and write config.json."""
    print("=" * 50)
    print("  IP Change Notifier — Setup Wizard")
    print("=" * 50)
    print()

    # Check for existing config
    if CONFIG_PATH.exists():
        overwrite = ask_yes_no("Config already exists. Overwrite?", default=False)
        if not overwrite:
            print("Setup cancelled. Existing config.json kept.")
            sys.exit(0)

    # Gather user inputs
    print("Answer the following questions to configure the notifier.\n")

    user_name = ask("Your name (shown in notifications)", "")
    while not user_name:
        print("  Name cannot be empty.")
        user_name = ask("Your name (shown in notifications)", "")

    default_hostname = socket.gethostname()
    hostname_label = ask("Label for this machine", default_hostname)

    print()
    print("  To create a Google Chat webhook:")
    print("  1. Open the Google Chat space where you want notifications.")
    print("  2. Click the space name → Manage webhooks → Add webhook.")
    print("  3. Copy the webhook URL and paste it below.")
    print()
    webhook_url = ask("Google Chat webhook URL", "")
    while not webhook_url:
        print("  Webhook URL cannot be empty.")
        webhook_url = ask("Google Chat webhook URL", "")

    include_public = ask_yes_no("Include public/external IP in notifications?", default=True)

    # Build config
    config = {
        "user_name": user_name,
        "hostname_label": hostname_label,
        "google_chat_webhook_url": webhook_url,
        "include_public_ip": include_public,
        "retry_count": 5,
        "retry_delay_seconds": 10,
        "cooldown_minutes": 5,
        "cache_file": "ip_cache.txt",
        "log_file": "ip_history.log",
    }

    # Write config.json
    CONFIG_PATH.write_text(
        json.dumps(config, indent=2, ensure_ascii=False), encoding="utf-8"
    )

    print()
    print("=" * 50)
    print("  Setup complete!")
    print("=" * 50)
    print()
    print(f"  Config saved to: {CONFIG_PATH}")
    print()
    print("  Next steps:")
    print("    Windows : Run  install\\register_windows.bat")
    print("    Linux/macOS : Run  bash install/register_linux.sh")
    print()
    print("  This will register the notifier to run automatically at startup.")
    print()


if __name__ == "__main__":
    run_setup()
