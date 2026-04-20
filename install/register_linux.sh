#!/usr/bin/env bash
# ============================================================
#  IP Change Notifier — Linux / macOS Startup Registration
# ============================================================
#  Detects whether the system uses systemd or cron and registers
#  ip_notifier.py to run at boot / login.
#
#  Usage:  bash install/register_linux.sh
#  Remove: systemctl --user disable ip-change-notifier
#          or edit crontab -e and delete the @reboot line
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
NOTIFIER="$SCRIPT_DIR/ip_notifier.py"
PYTHON="$(command -v python3 || command -v python)"
SERVICE_NAME="ip-change-notifier"

if [ ! -f "$NOTIFIER" ]; then
    echo "ERROR: ip_notifier.py not found at $NOTIFIER"
    exit 1
fi

if [ -z "$PYTHON" ]; then
    echo "ERROR: python3 not found. Please install Python 3.8+."
    exit 1
fi

echo ""
echo "============================================================"
echo "  IP Change Notifier — Startup Registration"
echo "============================================================"
echo ""

# --- Try systemd first ---
if command -v systemctl &>/dev/null && systemctl --user status &>/dev/null 2>&1; then
    echo "Detected systemd. Creating user service..."

    SERVICE_DIR="$HOME/.config/systemd/user"
    mkdir -p "$SERVICE_DIR"

    SERVICE_FILE="$SERVICE_DIR/${SERVICE_NAME}.service"

    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=IP Change Notifier
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$PYTHON $NOTIFIER
WorkingDirectory=$SCRIPT_DIR

[Install]
WantedBy=default.target
EOF

    systemctl --user daemon-reload
    systemctl --user enable "$SERVICE_NAME"

    echo ""
    echo "Service installed at: $SERVICE_FILE"
    echo "Enabled to run at login via systemd."
    echo ""
    echo "Useful commands:"
    echo "  systemctl --user start $SERVICE_NAME    # Run now"
    echo "  systemctl --user status $SERVICE_NAME   # Check status"
    echo "  systemctl --user disable $SERVICE_NAME  # Remove from startup"
    echo ""

else
    echo "systemd not available. Falling back to cron @reboot..."

    CRON_CMD="@reboot $PYTHON $NOTIFIER"

    # Check if entry already exists
    if crontab -l 2>/dev/null | grep -qF "$NOTIFIER"; then
        echo "Cron entry already exists. Skipping."
    else
        (crontab -l 2>/dev/null; echo "$CRON_CMD") | crontab -
        echo "Added to crontab:"
        echo "  $CRON_CMD"
    fi

    echo ""
    echo "The notifier will run at every reboot."
    echo "To remove, run: crontab -e  and delete the @reboot line."
    echo ""
fi

echo "Done!"
