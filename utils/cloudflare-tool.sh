#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# cloudflare-tool.sh -- Cloudflare Tunnel integration (token + named tunnels)
# =============================================================================
# Expose the local webhook server via Cloudflare Tunnel. Supports THREE modes:
#
#   1. Token mode (simplest)      -- from Cloudflare dashboard, one string
#   2. Named tunnel mode          -- created with `cloudflared tunnel create`
#   3. Quick tunnel               -- anonymous *.trycloudflare.com
#
# Token can be set from:
#   - Environment: CLOUDFLARE_TUNNEL_TOKEN=eyJ...
#   - File:        ~/.cloudflared/token
#   - ~/.picoclaw_keys: CLOUDFLARE_TUNNEL_TOKEN="eyJ..."
#   - Chat:        "configure cloudflare with token eyJ..." (agent -> token-set)
#   - Manual:      ~/bin/cloudflare-tool.sh token-set <token>
#
# Usage:
#   ~/bin/cloudflare-tool.sh token-set <token>        # Store token persistently
#   ~/bin/cloudflare-tool.sh token-show               # Print stored token (last 20 chars)
#   ~/bin/cloudflare-tool.sh token-clear              # Remove stored token
#   ~/bin/cloudflare-tool.sh run                      # Start tunnel (auto-detect token)
#   ~/bin/cloudflare-tool.sh daemon                   # Start in background (tmux)
#   ~/bin/cloudflare-tool.sh stop                     # Stop tunnel
#   ~/bin/cloudflare-tool.sh status                   # Check if running
#   ~/bin/cloudflare-tool.sh logs                     # Recent tunnel logs
#   ~/bin/cloudflare-tool.sh quick [port]             # Quick tunnel (anonymous)
#   ~/bin/cloudflare-tool.sh login                    # Interactive CF auth (named)
#   ~/bin/cloudflare-tool.sh list                     # List named tunnels (needs login)
# =============================================================================

set -eu
CLOUDFLARED="${CLOUDFLARED_BIN:-$HOME/bin/cloudflared}"
CONFIG_DIR="$HOME/.cloudflared"
TOKEN_FILE="$CONFIG_DIR/token"
LOG="$HOME/cloudflare.log"
DEFAULT_PORT="${WEBHOOK_PORT:-18791}"

mkdir -p "$CONFIG_DIR"
chmod 700 "$CONFIG_DIR"

command -v "$CLOUDFLARED" >/dev/null 2>&1 || [ -x "$CLOUDFLARED" ] || {
    echo "ERROR: cloudflared not installed at $CLOUDFLARED"
    echo "Install: curl -sL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64 -o $CLOUDFLARED && chmod +x $CLOUDFLARED"
    exit 1
}

# --- Token resolution order: arg > env > file > picoclaw_keys ---
resolve_token() {
    # 1. Env var
    if [ -n "${CLOUDFLARE_TUNNEL_TOKEN:-}" ]; then
        echo "$CLOUDFLARE_TUNNEL_TOKEN"
        return
    fi
    # 2. File
    if [ -r "$TOKEN_FILE" ]; then
        cat "$TOKEN_FILE"
        return
    fi
    # 3. ~/.picoclaw_keys
    if [ -r "$HOME/.picoclaw_keys" ]; then
        local t
        t=$(grep -E '^CLOUDFLARE_TUNNEL_TOKEN=' "$HOME/.picoclaw_keys" 2>/dev/null | cut -d= -f2- | tr -d '"' | head -1)
        if [ -n "$t" ]; then echo "$t"; return; fi
    fi
    echo ""
}

case "${1:-help}" in
    token-set)
        TOKEN="${2:?Usage: cloudflare-tool.sh token-set <token>}"
        echo "$TOKEN" > "$TOKEN_FILE"
        chmod 600 "$TOKEN_FILE"
        echo "Token saved: $TOKEN_FILE (last 20 chars: ...${TOKEN: -20})"
        echo "Run: ~/bin/cloudflare-tool.sh daemon"
        ;;
    token-show)
        TOKEN=$(resolve_token)
        if [ -n "$TOKEN" ]; then
            echo "Token source: $([ -n "${CLOUDFLARE_TUNNEL_TOKEN:-}" ] && echo env || [ -f "$TOKEN_FILE" ] && echo file || echo picoclaw_keys)"
            echo "Token: ...${TOKEN: -20}"
        else
            echo "No token configured"
            exit 1
        fi
        ;;
    token-clear)
        rm -f "$TOKEN_FILE"
        echo "Token file removed. Env var (if set) still takes effect."
        ;;
    run)
        TOKEN=$(resolve_token)
        if [ -z "$TOKEN" ]; then
            echo "ERROR: no token configured. Use: cloudflare-tool.sh token-set <token>"
            exit 1
        fi
        # Termux fix: bind a working resolv.conf at /etc/resolv.conf via proot
        # so cloudflared can resolve SRV records (Bionic doesn't, Go's resolver fails).
        printf 'nameserver 1.1.1.1\nnameserver 1.0.0.1\nnameserver 8.8.8.8\n' > "$CONFIG_DIR/resolv.conf"
        if command -v proot >/dev/null 2>&1; then
            exec proot -b "$CONFIG_DIR/resolv.conf:/etc/resolv.conf" \
                "$CLOUDFLARED" tunnel --edge-ip-version 4 --protocol http2 run --token "$TOKEN"
        else
            exec "$CLOUDFLARED" tunnel --edge-ip-version 4 --protocol http2 run --token "$TOKEN"
        fi
        ;;
    daemon)
        TOKEN=$(resolve_token)
        if [ -z "$TOKEN" ]; then
            echo "ERROR: no token configured."
            exit 1
        fi
        # Termux fix: proot bind /etc/resolv.conf
        printf 'nameserver 1.1.1.1\nnameserver 1.0.0.1\nnameserver 8.8.8.8\n' > "$CONFIG_DIR/resolv.conf"
        tmux kill-session -t cloudflared 2>/dev/null || true
        sleep 1
        if command -v proot >/dev/null 2>&1; then
            CMD="proot -b $CONFIG_DIR/resolv.conf:/etc/resolv.conf $CLOUDFLARED tunnel --edge-ip-version 4 --protocol http2 run --token '$TOKEN'"
        else
            CMD="$CLOUDFLARED tunnel --edge-ip-version 4 --protocol http2 run --token '$TOKEN'"
        fi
        tmux new-session -d -s cloudflared "$CMD 2>&1 | tee -a '$LOG'"
        sleep 3
        if tmux has-session -t cloudflared 2>/dev/null; then
            echo "Cloudflare tunnel: RUNNING (tmux session 'cloudflared')"
            echo "Logs: $LOG"
        else
            echo "ERROR: tunnel failed to start. Last log:"
            tail -10 "$LOG"
            exit 1
        fi
        ;;
    stop)
        tmux kill-session -t cloudflared 2>/dev/null || true
        pkill -f "cloudflared tunnel run" 2>/dev/null || true
        echo "Cloudflare tunnel: STOPPED"
        ;;
    status)
        # Detect both direct cloudflared and proot-wrapped cloudflared
        if pgrep -f "cloudflared tunnel.*run" >/dev/null 2>&1; then
            CONN=$(grep -c 'Registered tunnel connection' "$LOG" 2>/dev/null || echo 0)
            ACTIVE=$(tail -50 "$LOG" 2>/dev/null | grep -c 'Registered tunnel connection' || echo 0)
            echo "Cloudflare tunnel: RUNNING (${ACTIVE} connections registered recently)"
            echo "Process count: $(pgrep -f cloudflared | wc -l)"
            echo "--- Last connections ---"
            tail -30 "$LOG" 2>/dev/null | grep -E "Registered|Starting tunnel|tunnelID" | tail -5
        else
            echo "Cloudflare tunnel: STOPPED"
            if [ -n "$(resolve_token)" ]; then
                echo "Token: configured (start with: cloudflare-tool.sh daemon)"
            else
                echo "Token: NOT configured (set with: cloudflare-tool.sh token-set <token>)"
            fi
        fi
        ;;
    logs)
        N="${2:-30}"
        tail -n "$N" "$LOG" 2>/dev/null || echo "No logs yet"
        ;;
    url)
        # Print the current webhook URL (from config, trycloudflare log, or env)
        URL_FILE="$CONFIG_DIR/webhook-url"
        if [ -f "$URL_FILE" ]; then
            cat "$URL_FILE"
        elif [ -n "${WEBHOOK_PUBLIC_URL:-}" ]; then
            echo "$WEBHOOK_PUBLIC_URL"
        else
            # Try to extract from trycloudflare log (quick tunnel)
            URL=$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' "$LOG" 2>/dev/null | tail -1)
            if [ -n "$URL" ]; then
                echo "$URL"
            else
                echo "No webhook URL configured. Set with: cloudflare-tool.sh url-set <url>" >&2
                exit 1
            fi
        fi
        ;;
    url-set)
        URL="${2:?Usage: cloudflare-tool.sh url-set <https://your-domain.com>}"
        mkdir -p "$CONFIG_DIR"
        echo "$URL" > "$CONFIG_DIR/webhook-url"
        chmod 600 "$CONFIG_DIR/webhook-url"
        echo "Webhook URL saved: $URL"
        # Also update .picoclaw_keys for other tools
        if [ -f "$HOME/.picoclaw_keys" ]; then
            grep -v "^WEBHOOK_PUBLIC_URL=" "$HOME/.picoclaw_keys" > "$HOME/.picoclaw_keys.tmp" || true
            mv "$HOME/.picoclaw_keys.tmp" "$HOME/.picoclaw_keys"
        fi
        echo "WEBHOOK_PUBLIC_URL=\"$URL\"" >> "$HOME/.picoclaw_keys"
        chmod 600 "$HOME/.picoclaw_keys"
        ;;
    url-test)
        URL=$("$0" url 2>/dev/null)
        [ -z "$URL" ] && { echo "No URL configured"; exit 1; }
        echo "Testing $URL/health ..."
        curl -sfL --max-time 15 "$URL/health" && echo "" && echo "OK" || echo "FAILED"
        ;;
    url-discover)
        # Try to query Cloudflare API with the token to discover the tunnel's hostname
        TOKEN=$(resolve_token)
        if [ -z "$TOKEN" ]; then
            echo "No token configured"; exit 1
        fi
        # Decode the JWT-like token to get tunnel_id
        TUNNEL_ID=$(python3 -c "
import base64, json, sys
try:
    tok = '''$TOKEN'''
    # Token format: eyJhIjoi<accountId>IiwidCI6i<tunnelId>IiwicyI6i...
    # It's base64url JSON
    padded = tok + '=' * ((4 - len(tok) % 4) % 4)
    data = json.loads(base64.urlsafe_b64decode(padded))
    print(data.get('t', ''))
except Exception as e:
    print('', file=sys.stderr)
" 2>/dev/null)
        echo "Tunnel ID: $TUNNEL_ID"
        echo ""
        echo "To find your public hostname:"
        echo "  1. Go to https://one.dash.cloudflare.com > Zero Trust > Networks > Tunnels"
        echo "  2. Click on tunnel ID: $TUNNEL_ID"
        echo "  3. Find the public hostname under 'Public Hostname' tab"
        echo "  4. Save it: ~/bin/cloudflare-tool.sh url-set <https://your-hostname>"
        ;;
    quick)
        PORT="${2:-$DEFAULT_PORT}"
        echo "Starting quick tunnel to 127.0.0.1:$PORT (anonymous *.trycloudflare.com URL)..."
        echo "Press Ctrl+C to stop. URL will be printed below."
        "$CLOUDFLARED" tunnel --edge-ip-version 4 --protocol http2 --url "http://localhost:$PORT" 2>&1 | tee "$LOG"
        ;;
    quick-daemon)
        PORT="${2:-$DEFAULT_PORT}"
        tmux kill-session -t cf-quick 2>/dev/null || true
        sleep 1
        tmux new-session -d -s cf-quick "$CLOUDFLARED tunnel --edge-ip-version 4 --protocol http2 --url 'http://localhost:$PORT' 2>&1 | tee -a '$LOG'"
        echo "Quick tunnel starting in tmux (session 'cf-quick'). Wait 10s for URL:"
        sleep 12
        URL=$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' "$LOG" | tail -1)
        if [ -n "$URL" ]; then
            echo "Public URL: $URL"
            echo "Test: curl -sf $URL/health"
        else
            echo "URL not yet ready. Check: tmux attach -t cf-quick"
        fi
        ;;
    print-host-script)
        # Generates a one-liner the user can run on a PC/VPS to start the tunnel
        TOKEN=$(resolve_token)
        if [ -z "$TOKEN" ]; then echo "ERROR: no token configured"; exit 1; fi
        cat <<HOSTSCRIPT
# Run this on a Linux/macOS host (NOT Termux) where DNS supports SRV records:
# Requires cloudflared installed: https://github.com/cloudflare/cloudflared/releases

cloudflared tunnel run --token $TOKEN

# Or as a systemd service:
# sudo cloudflared service install $TOKEN
HOSTSCRIPT
        ;;
    login)
        "$CLOUDFLARED" tunnel login
        ;;
    list)
        "$CLOUDFLARED" tunnel list
        ;;
    help|*)
        head -32 "$0" | tail -30 | sed 's/^# //;s/^#//'
        ;;
esac
