#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# watchdog.sh — Keep PicoClaw alive permanently
# =============================================================================
# Monitors and restarts all critical services:
#   - sshd (SSH server)
#   - PicoClaw gateway (Telegram/WhatsApp)
#   - ADB self-bridge (localhost:5555)
#   - Wake lock (prevent Android from killing Termux)
#
# Runs every minute via cron. If ANY service is down, restarts it.
#
# Install:
#   crontab -e  →  * * * * * ~/bin/watchdog.sh >> ~/watchdog.log 2>&1
# =============================================================================

export SSL_CERT_FILE=/data/data/com.termux/files/usr/etc/tls/cert.pem
export PATH="$HOME/bin:$PATH"

LOG_LINE="[$(date '+%H:%M:%S')]"
RESTART_NEEDED=false

# --- 1. SSH Server ---
if ! pgrep -x sshd >/dev/null 2>&1; then
    sshd
    LOG_LINE="$LOG_LINE sshd:RESTARTED"
    RESTART_NEEDED=true
fi

# --- 2. Wake Lock ---
# termux-wake-lock is idempotent — safe to call every time
termux-wake-lock 2>/dev/null

# --- 3. ADB Self-Bridge ---
if ! adb -s localhost:5555 shell echo ok >/dev/null 2>&1; then
    adb start-server >/dev/null 2>&1
    setprop service.adb.tcp.port 5555 2>/dev/null
    stop adbd 2>/dev/null; start adbd 2>/dev/null
    sleep 3
    adb connect localhost:5555 >/dev/null 2>&1
    LOG_LINE="$LOG_LINE adb:RECONNECTED"
    RESTART_NEEDED=true
fi

# --- 4. PicoClaw Gateway (in tmux) ---
if ! tmux has-session -t picoclaw 2>/dev/null; then
    tmux new-session -d -s picoclaw \
        "$HOME/picoclaw.bin gateway > $HOME/.picoclaw/gateway.log 2>&1"
    LOG_LINE="$LOG_LINE gateway:RESTARTED"
    RESTART_NEEDED=true
else
    # Check if the gateway process inside tmux is actually alive
    if ! pgrep -f "picoclaw.bin gateway" >/dev/null 2>&1; then
        tmux kill-session -t picoclaw 2>/dev/null
        sleep 1
        tmux new-session -d -s picoclaw \
            "$HOME/picoclaw.bin gateway > $HOME/.picoclaw/gateway.log 2>&1"
        LOG_LINE="$LOG_LINE gateway:RESPAWNED"
        RESTART_NEEDED=true
    fi
fi

# --- Log only if something was restarted ---
if [ "$RESTART_NEEDED" = "true" ]; then
    echo "$LOG_LINE"
fi
