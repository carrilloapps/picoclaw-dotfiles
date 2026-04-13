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

# --- 2.5. Network recovery (detect WiFi/mobile/ethernet changes) ---
if [ -x "$HOME/bin/network-recovery.sh" ]; then
    NET_CHANGE=$("$HOME/bin/network-recovery.sh" 2>&1 | head -1)
    if [ -n "$NET_CHANGE" ]; then
        LOG_LINE="$LOG_LINE $NET_CHANGE"
        RESTART_NEEDED=true
    fi
fi

# --- 3. ADB Self-Bridge (auto-detect port) ---
if [ -x "$HOME/bin/adb-connect.sh" ]; then
    if ! "$HOME/bin/adb-connect.sh" --check >/dev/null 2>&1; then
        RESULT=$("$HOME/bin/adb-connect.sh" 2>/dev/null)
        if echo "$RESULT" | grep -q "^connected:"; then
            LOG_LINE="$LOG_LINE adb:RECONNECTED(${RESULT#connected:})"
            RESTART_NEEDED=true
        fi
    fi
elif command -v adb >/dev/null 2>&1; then
    # Fallback: simple connect
    if ! adb -s localhost:5555 shell echo ok >/dev/null 2>&1; then
        adb start-server >/dev/null 2>&1
        adb connect localhost:5555 >/dev/null 2>&1
        sleep 2
        if adb -s localhost:5555 shell echo ok >/dev/null 2>&1; then
            LOG_LINE="$LOG_LINE adb:RECONNECTED"
            RESTART_NEEDED=true
        fi
    fi
fi

# --- 3.5. Webhook server (with env loaded) ---
if [ -x "$HOME/bin/webhook-start.sh" ]; then
    if ! pgrep -f "webhook-server.py" >/dev/null 2>&1; then
        tmux kill-session -t webhook 2>/dev/null
        tmux new-session -d -s webhook "$HOME/bin/webhook-start.sh > $HOME/webhook-server.log 2>&1"
        LOG_LINE="$LOG_LINE webhook:RESTARTED"
        RESTART_NEEDED=true
    fi
fi

# --- 3.6. Cloudflare Tunnel ---
if [ -f "$HOME/.cloudflared/token" ] && [ -x "$HOME/bin/cloudflare-tool.sh" ]; then
    if ! pgrep -f "cloudflared tunnel" >/dev/null 2>&1; then
        "$HOME/bin/cloudflare-tool.sh" daemon >/dev/null 2>&1
        LOG_LINE="$LOG_LINE cloudflared:RESTARTED"
        RESTART_NEEDED=true
    fi
fi

# --- 4. PicoClaw Gateway (in tmux) ---
GW_CMD="SSL_CERT_FILE=$SSL_CERT_FILE $HOME/picoclaw.bin gateway > $HOME/.picoclaw/gateway.log 2>&1"
if ! tmux has-session -t picoclaw 2>/dev/null; then
    tmux new-session -d -s picoclaw "$GW_CMD"
    LOG_LINE="$LOG_LINE gateway:RESTARTED"
    RESTART_NEEDED=true
else
    # Check if the gateway process inside tmux is actually alive
    if ! pgrep -f "picoclaw.bin gateway" >/dev/null 2>&1; then
        tmux kill-session -t picoclaw 2>/dev/null
        sleep 1
        tmux new-session -d -s picoclaw "$GW_CMD"
        LOG_LINE="$LOG_LINE gateway:RESPAWNED"
        RESTART_NEEDED=true
    fi
fi

# --- 5. LLM provider failover (detect recent 429/503/500 errors) ---
# If gateway log shows recent provider errors, try switching to next available
if [ -f "$HOME/.picoclaw/gateway.log" ] && [ -x "$HOME/bin/auto-failover.sh" ]; then
    # Look for errors in the last 200 lines (~ recent activity)
    RECENT_ERRORS=$(tail -200 "$HOME/.picoclaw/gateway.log" 2>/dev/null | \
        grep -cE '"code": (429|500|503)|"code":(429|500|503)|Status: (429|500|503)' 2>/dev/null | tr -d '\n ' || echo 0)
    RECENT_ERRORS="${RECENT_ERRORS:-0}"
    # Track last failover to avoid spam — only run if >2 errors AND no recent failover
    LAST_FAILOVER_FILE="$HOME/.last_failover"
    NOW=$(date +%s)
    LAST_RUN=0
    [ -f "$LAST_FAILOVER_FILE" ] && LAST_RUN=$(cat "$LAST_FAILOVER_FILE" 2>/dev/null || echo 0)
    COOLDOWN=300  # 5 minutes between failover attempts
    if [ "$RECENT_ERRORS" -gt 2 ] && [ $((NOW - LAST_RUN)) -gt $COOLDOWN ]; then
        echo "$NOW" > "$LAST_FAILOVER_FILE"
        "$HOME/bin/auto-failover.sh" --quiet >> "$HOME/failover.log" 2>&1 &
        LOG_LINE="$LOG_LINE llm:FAILOVER_TRIGGERED($RECENT_ERRORS errors)"
        RESTART_NEEDED=true
    fi
fi

# --- Log only if something was restarted ---
if [ "$RESTART_NEEDED" = "true" ]; then
    echo "$LOG_LINE"
fi
