#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# boot-picoclaw.sh — Bulletproof auto-start on device boot
# =============================================================================
# Executed by Termux:Boot on every device reboot.
# Starts ALL services and installs the watchdog cron for permanent monitoring.
# =============================================================================

export SSL_CERT_FILE=/data/data/com.termux/files/usr/etc/tls/cert.pem
export PATH="$HOME/bin:$PATH"

# 1. SSH server — MUST start first for remote access
sshd

# 2. Wake lock — prevent Android from killing Termux
termux-wake-lock

# 3. ADB self-bridge — elevated shell access via loopback
setprop service.adb.tcp.port 5555 2>/dev/null
stop adbd 2>/dev/null; start adbd 2>/dev/null
sleep 3
adb start-server 2>/dev/null
adb connect localhost:5555 2>/dev/null
# Retry in background
(sleep 15 && adb connect localhost:5555 2>/dev/null) &

# 4. PicoClaw gateway — Telegram/WhatsApp/CLI
tmux kill-session -t picoclaw 2>/dev/null
sleep 1
tmux new-session -d -s picoclaw \
    "$HOME/picoclaw.bin gateway > $HOME/.picoclaw/gateway.log 2>&1"

# 5. Install watchdog cron (idempotent — won't duplicate)
(crontab -l 2>/dev/null | grep -v watchdog; echo "* * * * * $HOME/bin/watchdog.sh >> $HOME/watchdog.log 2>&1") | crontab -

# 6. Start crond if not running
pgrep crond >/dev/null 2>&1 || crond

# Log boot event
echo "[$(date '+%Y-%m-%d %H:%M:%S')] BOOT COMPLETE" >> "$HOME/watchdog.log"
