#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# boot-picoclaw.sh — Bulletproof auto-start on device boot
# =============================================================================
# Executed by Termux:Boot on every device reboot.
# Starts ALL services and installs the watchdog cron for permanent monitoring.
# =============================================================================

export SSL_CERT_FILE=/data/data/com.termux/files/usr/etc/tls/cert.pem
export PATH="$HOME/bin:$PATH"

# 0. Wait for network to be up (WiFi, mobile data, or ethernet — any)
for i in $(seq 1 30); do
    if ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1; then break; fi
    sleep 2
done

# 1. SSH server — MUST start first for remote access
sshd

# 2. Wake lock — prevent Android from killing Termux
termux-wake-lock

# 2.5. Network state baseline + initial interface detection
[ -x "$HOME/bin/network-recovery.sh" ] && "$HOME/bin/network-recovery.sh" >/dev/null 2>&1

# 3. ADB self-bridge — elevated shell access via loopback
# Uses adb-connect.sh for smart port detection (handles dynamic ports after reboot)
if [ -x "$HOME/bin/adb-connect.sh" ]; then
    "$HOME/bin/adb-connect.sh" >/dev/null 2>&1
    # Retry in background (ADB daemon may take a moment after boot)
    (sleep 15 && "$HOME/bin/adb-connect.sh" >/dev/null 2>&1) &
    (sleep 30 && "$HOME/bin/adb-connect.sh" >/dev/null 2>&1) &
else
    adb start-server 2>/dev/null
    adb connect localhost:5555 2>/dev/null
    (sleep 15 && adb connect localhost:5555 2>/dev/null) &
fi

# 4. LLM failover check — pick best available provider BEFORE starting gateway
if [ -x "$HOME/bin/auto-failover.sh" ]; then
    "$HOME/bin/auto-failover.sh" --quiet 2>&1 | head -5 >> "$HOME/watchdog.log" || true
fi

# 4.5. Webhook server (with env loaded from .picoclaw_keys)
if [ -x "$HOME/bin/webhook-start.sh" ]; then
    tmux new-session -d -s webhook "$HOME/bin/webhook-start.sh > $HOME/webhook-server.log 2>&1"
fi

# 4.6. Cloudflare Tunnel (if token configured)
if [ -f "$HOME/.cloudflared/token" ] && [ -x "$HOME/bin/cloudflare-tool.sh" ]; then
    "$HOME/bin/cloudflare-tool.sh" daemon >/dev/null 2>&1 &
fi

# 5. PicoClaw gateway — Telegram/WhatsApp/CLI
# SSL_CERT_FILE is set explicitly in the tmux command for reliability
tmux kill-session -t picoclaw 2>/dev/null
sleep 1
tmux new-session -d -s picoclaw \
    "SSL_CERT_FILE=$SSL_CERT_FILE $HOME/picoclaw.bin gateway > $HOME/.picoclaw/gateway.log 2>&1"

# 5. Install watchdog cron (idempotent — won't duplicate)
(crontab -l 2>/dev/null | grep -v watchdog; echo "* * * * * $HOME/bin/watchdog.sh >> $HOME/watchdog.log 2>&1") | crontab -

# 6. Start crond if not running
pgrep crond >/dev/null 2>&1 || crond

# Log boot event
echo "[$(date '+%Y-%m-%d %H:%M:%S')] BOOT COMPLETE" >> "$HOME/watchdog.log"
