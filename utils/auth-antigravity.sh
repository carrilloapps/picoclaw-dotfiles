#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# auth-antigravity.sh — Authenticate Antigravity (Google Cloud) from Telegram
# =============================================================================
# Starts the OAuth device-code flow and sends the auth URL to the user
# via Telegram. The user opens the URL on any device (phone, PC), logs
# in with Google, and pastes back the redirect URL. The script completes
# the authentication automatically.
#
# Usage from PicoClaw (exec tool):
#   ~/bin/auth-antigravity.sh start    # Start auth, returns URL
#   ~/bin/auth-antigravity.sh paste "http://localhost:51121/auth/callback?code=..."
#   ~/bin/auth-antigravity.sh status   # Check auth status
#   ~/bin/auth-antigravity.sh refresh  # Force token refresh
# =============================================================================

export SSL_CERT_FILE=/data/data/com.termux/files/usr/etc/tls/cert.pem
export PATH="$HOME/bin:/data/data/com.termux/files/usr/bin:$PATH"

AUTH_LOG="$HOME/.picoclaw/auth_antigravity.log"
AUTH_PID="$HOME/.picoclaw/auth_antigravity.pid"

case "$1" in
    start)
        # Kill any existing auth process
        [ -f "$AUTH_PID" ] && kill "$(cat "$AUTH_PID")" 2>/dev/null
        rm -f "$AUTH_LOG" "$AUTH_PID"

        # Backup config BEFORE auth (picoclaw auth changes default model)
        cp "$HOME/.picoclaw/config.json" "$HOME/.picoclaw/config.json.pre-auth" 2>/dev/null

        # Start auth in background, capture output
        nohup $HOME/picoclaw.bin auth login --provider antigravity --device-code \
            > "$AUTH_LOG" 2>&1 &
        echo $! > "$AUTH_PID"

        # Wait for the URL to appear in the log
        for i in $(seq 1 15); do
            sleep 2
            if grep -q "accounts.google.com" "$AUTH_LOG" 2>/dev/null; then
                # Extract the URL
                URL=$(grep -oP 'https://accounts\.google\.com[^\s]*' "$AUTH_LOG" | head -1)
                echo "AUTH_URL=$URL"
                echo ""
                echo "INSTRUCTIONS:"
                echo "1. Open this URL in any browser (phone, PC, tablet)"
                echo "2. Sign in with your Google account"
                echo "3. After login, the browser will redirect to localhost:51121 (it will fail to load)"
                echo "4. Copy the FULL URL from your browser's address bar"
                echo "5. Send it to me here with: auth-antigravity.sh paste \"URL\""
                exit 0
            fi
        done

        echo "ERROR: Timeout waiting for auth URL"
        cat "$AUTH_LOG" 2>/dev/null
        exit 1
        ;;

    paste)
        CALLBACK_URL="$2"
        if [ -z "$CALLBACK_URL" ]; then
            echo "Usage: auth-antigravity.sh paste \"http://localhost:51121/auth/callback?code=...\""
            exit 1
        fi

        # Check if auth process is running
        if [ ! -f "$AUTH_PID" ]; then
            echo "ERROR: No auth process running. Run 'auth-antigravity.sh start' first."
            exit 1
        fi

        PID=$(cat "$AUTH_PID")
        if ! kill -0 "$PID" 2>/dev/null; then
            echo "ERROR: Auth process died. Run 'auth-antigravity.sh start' again."
            exit 1
        fi

        # Find the tmux pane or screen where auth is running and send the URL
        # Since it's a background process reading stdin, we use a different approach:
        # Kill the current auth and restart with the code extracted from URL
        kill "$PID" 2>/dev/null
        sleep 1

        # Extract the authorization code from the callback URL
        CODE=$(echo "$CALLBACK_URL" | grep -oP 'code=([^&]+)' | head -1 | sed 's/code=//')

        if [ -z "$CODE" ]; then
            echo "ERROR: Could not extract authorization code from URL"
            echo "URL should contain: code=4/0Axx..."
            exit 1
        fi

        # Start auth in a tmux session where we can paste the URL
        tmux kill-session -t picoclaw-auth 2>/dev/null
        tmux new-session -d -s picoclaw-auth \
            "$HOME/picoclaw.bin auth login --provider antigravity --device-code 2>&1 | tee $AUTH_LOG"
        sleep 8

        # Paste the callback URL into the tmux session
        tmux send-keys -t picoclaw-auth "$CALLBACK_URL" Enter
        sleep 5

        # Check result
        if grep -q "successful" "$AUTH_LOG" 2>/dev/null; then
            EMAIL=$(grep -oP 'Email: \K.*' "$AUTH_LOG")
            PROJECT=$(grep -oP 'Project: \K.*' "$AUTH_LOG")

            # CRITICAL: picoclaw auth login changes default model to gemini-flash
            # Restore correct priority: Azure -> Ollama -> Groq -> Antigravity (always last)
            python3 -c "
import json
cfg_path = '$HOME/.picoclaw/config.json'
with open(cfg_path) as f:
    c = json.load(f)
azure = ollama = groq = anti = None
for m in c.get('model_list', []):
    model = m.get('model', '')
    name = m.get('model_name', '')
    if 'azure' in model: azure = name
    elif 'antigravity' in model or 'gemini' in model: anti = name
    elif 'groq' in model: groq = name
    else: ollama = name
if azure:
    c['agents']['defaults']['model_name'] = azure
    fb = []
    if ollama: fb.append(ollama)
    if groq: fb.append(groq)
    if anti: fb.append(anti)  # Antigravity always last (needs auth)
    c['agents']['defaults']['model_fallbacks'] = fb
    with open(cfg_path, 'w') as f:
        json.dump(c, f, indent=2, ensure_ascii=False)
    print(f'Restored: {azure} -> {fb}')
" 2>/dev/null

            echo "AUTH_SUCCESS"
            echo "Email: $EMAIL"
            echo "Project: $PROJECT"
            echo "Model priority preserved: Azure -> Ollama -> Antigravity"
            # Cleanup
            tmux kill-session -t picoclaw-auth 2>/dev/null
            rm -f "$AUTH_PID"
        else
            echo "AUTH_PENDING — check status in a few seconds"
            echo "Run: auth-antigravity.sh status"
        fi
        ;;

    status)
        $HOME/picoclaw.bin auth status 2>&1 | grep -v '█' | grep -v '╗' | grep -v '╝' | grep -v '╚' | grep -v '║' | grep -v '^$' | grep -v 'PicoClaw'
        ;;

    refresh)
        # Force re-auth
        $HOME/picoclaw.bin auth logout --provider antigravity 2>/dev/null
        echo "Logged out. Run: auth-antigravity.sh start"
        ;;

    *)
        echo "Usage: auth-antigravity.sh <start|paste URL|status|refresh>"
        echo ""
        echo "  start          Start OAuth flow, returns Google login URL"
        echo "  paste URL      Complete auth with the redirect URL from browser"
        echo "  status         Check current authentication status"
        echo "  refresh        Logout and start fresh"
        ;;
esac
