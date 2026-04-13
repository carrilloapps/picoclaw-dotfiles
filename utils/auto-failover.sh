#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# auto-failover.sh — Auto-detect and select the best available LLM provider
# =============================================================================
# Tests each provider in priority order and updates config.json to use the
# first one that responds. Runs at boot, via watchdog on errors, or on demand.
#
# Priority order (edit PROVIDERS array to customize):
#   1. Azure GPT-4o       (enterprise, most capable)
#   2. Ollama Cloud        (free, high quotas)
#   3. Antigravity         (Google OAuth, last resort)
#   4. Google AI Studio    (free API key, rate-limited)
#
# Usage:
#   ~/bin/auto-failover.sh             # Select best + update config + restart gateway
#   ~/bin/auto-failover.sh --check     # Just check + print, don't modify
#   ~/bin/auto-failover.sh --quiet     # No output unless change made
# =============================================================================

set -u
export SSL_CERT_FILE=/data/data/com.termux/files/usr/etc/tls/cert.pem

CONFIG="$HOME/.picoclaw/config.json"
SECURITY="$HOME/.picoclaw/.security.yml"
LOG="$HOME/failover.log"
QUIET=false
CHECK_ONLY=false

for arg in "$@"; do
    case "$arg" in
        --check) CHECK_ONLY=true ;;
        --quiet) QUIET=true ;;
    esac
done

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg" >> "$LOG"
    [ "$QUIET" = false ] && echo "$1"
}

# Priority order: (display_name, model_name, probe_command)
# Each probe returns HTTP 200 if the provider is healthy.
test_provider() {
    local name="$1"
    local probe="$2"
    local code
    code=$(eval "$probe" 2>/dev/null || echo "000")
    if [ "$code" = "200" ]; then
        return 0
    else
        log "  [FAIL $code] $name"
        return 1
    fi
}

# Get API keys from security.yml
get_key_for_model() {
    local model="$1"
    python3 -c "
import yaml, sys
try:
    data = yaml.safe_load(open('$SECURITY'))
    ml = data.get('model_list', {}) or {}
    key = ml.get('$model:0', {}).get('api_keys', [''])[0]
    print(key)
except Exception:
    print('')
" 2>/dev/null
}

# Get api_base for a model from config.json
get_base_for_model() {
    jq -r --arg m "$1" '.model_list[] | select(.model_name == $m) | .api_base // ""' "$CONFIG" 2>/dev/null | head -1
}

# Get the "model" field (provider/model_id) for a model_name
get_model_id() {
    jq -r --arg m "$1" '.model_list[] | select(.model_name == $m) | .model // ""' "$CONFIG" 2>/dev/null | head -1
}

# Test a specific model from config.json
test_model() {
    local model_name="$1"
    local api_base api_key model_id
    api_base=$(get_base_for_model "$model_name")
    api_key=$(get_key_for_model "$model_name")
    model_id=$(get_model_id "$model_name" | sed 's|^[^/]*/||')

    if [ -z "$api_base" ] || [ -z "$api_key" ] || [ -z "$model_id" ]; then
        return 1
    fi

    # Azure uses api-key header + deployment URL, others use Authorization: Bearer
    local probe
    if echo "$api_base" | grep -q "openai.azure.com"; then
        local ver
        ver=$(jq -r '.agents.defaults.azure_api_version // "2025-01-01-preview"' "$CONFIG" 2>/dev/null)
        [ "$ver" = "null" ] && ver="2025-01-01-preview"
        probe="curl -s -o /dev/null -w '%{http_code}' -X POST '${api_base}/openai/deployments/${model_id}/chat/completions?api-version=${ver}' -H 'api-key: ${api_key}' -H 'Content-Type: application/json' -d '{\"messages\":[{\"role\":\"user\",\"content\":\"ping\"}],\"max_tokens\":5}' --max-time 10"
    else
        probe="curl -s -o /dev/null -w '%{http_code}' -X POST '${api_base}/chat/completions' -H 'Authorization: Bearer ${api_key}' -H 'Content-Type: application/json' -d '{\"model\":\"${model_id}\",\"messages\":[{\"role\":\"user\",\"content\":\"ping\"}],\"max_tokens\":5}' --max-time 10"
    fi

    test_provider "$model_name" "$probe"
}

# Priority list: models to try in order
# Pulls the models present in config.json sorted by priority heuristic:
# Azure first, then Ollama, then Antigravity, then Google (last).
build_priority_list() {
    local priority=()

    # 1. Azure
    while IFS= read -r m; do
        [ -n "$m" ] && priority+=("$m")
    done < <(jq -r '.model_list[] | select(.api_base // "" | contains("azure.com")) | .model_name' "$CONFIG" 2>/dev/null)

    # 2. Ollama Cloud
    while IFS= read -r m; do
        [ -n "$m" ] && priority+=("$m")
    done < <(jq -r '.model_list[] | select(.api_base // "" | contains("ollama.com")) | .model_name' "$CONFIG" 2>/dev/null)

    # 3. Antigravity
    while IFS= read -r m; do
        [ -n "$m" ] && priority+=("$m")
    done < <(jq -r '.model_list[] | select(.model // "" | startswith("antigravity/")) | .model_name' "$CONFIG" 2>/dev/null)

    # 4. Google AI Studio (last resort)
    while IFS= read -r m; do
        [ -n "$m" ] && priority+=("$m")
    done < <(jq -r '.model_list[] | select(.api_base // "" | contains("generativelanguage.googleapis.com")) | .model_name' "$CONFIG" 2>/dev/null)

    printf '%s\n' "${priority[@]}"
}

# --- Main ---
CURRENT=$(jq -r '.agents.defaults.model_name' "$CONFIG" 2>/dev/null)
log "=== Auto-failover check (current: $CURRENT) ==="

mapfile -t PRIORITY < <(build_priority_list)
if [ "${#PRIORITY[@]}" -eq 0 ]; then
    log "No models configured. Exiting."
    exit 1
fi

log "Priority order: ${PRIORITY[*]}"

SELECTED=""
for model in "${PRIORITY[@]}"; do
    if test_model "$model"; then
        SELECTED="$model"
        log "  [OK] $model"
        break
    fi
done

if [ -z "$SELECTED" ]; then
    log "ERROR: All providers failed health check!"
    exit 1
fi

if [ "$CHECK_ONLY" = true ]; then
    echo "BEST_AVAILABLE: $SELECTED"
    exit 0
fi

if [ "$SELECTED" = "$CURRENT" ]; then
    log "Current provider is healthy — no change needed"
    exit 0
fi

# Update config.json
log "Switching default: $CURRENT -> $SELECTED"
tmp=$(mktemp)
jq --arg m "$SELECTED" '.agents.defaults.model_name = $m' "$CONFIG" > "$tmp" && mv "$tmp" "$CONFIG"
chmod 600 "$CONFIG"

# Restart gateway
if tmux has-session -t picoclaw 2>/dev/null; then
    tmux kill-session -t picoclaw 2>/dev/null
    sleep 1
fi
pkill -f "picoclaw.bin gateway" 2>/dev/null
sleep 2
tmux new-session -d -s picoclaw \
    "SSL_CERT_FILE=$SSL_CERT_FILE $HOME/picoclaw.bin gateway > $HOME/.picoclaw/gateway.log 2>&1"

sleep 4
if curl -sf http://127.0.0.1:18790/health >/dev/null 2>&1; then
    log "  Gateway restarted successfully with $SELECTED"
    # Send notification if termux-notification available
    if command -v termux-notification >/dev/null 2>&1; then
        termux-notification --title "PicoClaw Failover" \
            --content "Switched from $CURRENT to $SELECTED" \
            --priority default 2>/dev/null || true
    fi
else
    log "  WARNING: Gateway restart failed, check ~/.picoclaw/gateway.log"
fi

exit 0
