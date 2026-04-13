#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# agent-self.sh -- Self-modification toolkit for the agent
# =============================================================================
# Allows the agent to inspect and modify its own personality, capabilities,
# tools, and configuration. All changes are versioned in RAG so the agent
# can roll back or recall what it changed.
#
# Personality lives in BOTH:
#   - ~/.picoclaw/workspace/AGENT.md (active prompt for the LLM)
#   - RAG database as 'self:personality:<timestamp>' chunks (versioned history)
#
# The agent can:
#   - Add/modify personality traits
#   - Install new tools (write a script + register it)
#   - Modify config.json (model, providers, channels)
#   - Restart itself with new behavior
#   - Read its own source/scripts
#   - Roll back changes
#
# Usage:
#   ~/bin/agent-self.sh personality-show              # Current AGENT.md
#   ~/bin/agent-self.sh personality-add "<trait>"     # Append trait
#   ~/bin/agent-self.sh personality-set <section> "<text>"
#   ~/bin/agent-self.sh personality-history           # Versioned snapshots
#   ~/bin/agent-self.sh capability-add <name> <script>  # Install a new tool
#   ~/bin/agent-self.sh capability-list               # All available tools
#   ~/bin/agent-self.sh capability-remove <name>
#   ~/bin/agent-self.sh config-get <key>              # jq path on config.json
#   ~/bin/agent-self.sh config-set <key> <value>
#   ~/bin/agent-self.sh restart                       # Restart gateway
#   ~/bin/agent-self.sh snapshot                      # Save full state to RAG
#   ~/bin/agent-self.sh rollback <snapshot-id>        # Restore a snapshot
# =============================================================================

set -eu
HOME_DIR="${HOME}"
AGENT_MD="${HOME_DIR}/.picoclaw/workspace/AGENT.md"
CONFIG="${HOME_DIR}/.picoclaw/config.json"
BIN="${HOME_DIR}/bin"
DB="${HOME_DIR}/.picoclaw/workspace/knowledge/rag.db"
SELF_LOG="${HOME_DIR}/.picoclaw/agent-self.log"
SNAPSHOTS_DIR="${HOME_DIR}/.picoclaw/snapshots"
mkdir -p "$SNAPSHOTS_DIR"

CMD="${1:-help}"

log_event() {
    local action="$1"; shift
    echo "{\"ts\":\"$(date -Iseconds)\",\"action\":\"$action\",\"args\":\"$*\"}" >> "$SELF_LOG"
}

snapshot_to_rag() {
    local snap_id="self:personality:$(date +%Y%m%d-%H%M%S)"
    if [ -x "$BIN/rag-tool.sh" ] && [ -f "$AGENT_MD" ]; then
        cat "$AGENT_MD" | "$BIN/rag-tool.sh" add-text "$snap_id" "$(cat "$AGENT_MD")" >/dev/null 2>&1 || true
        echo "$snap_id"
    fi
}

case "$CMD" in
    personality-show)
        cat "$AGENT_MD"
        ;;
    personality-add)
        TRAIT="${2:?Usage: agent-self.sh personality-add \"<trait>\"}"
        SECTION="${3:-Custom Traits}"
        log_event personality-add "$TRAIT"
        snapshot_to_rag >/dev/null
        # Append to a "Custom Traits" section, create if missing
        if ! grep -q "^## $SECTION" "$AGENT_MD" 2>/dev/null; then
            printf '\n\n## %s\n' "$SECTION" >> "$AGENT_MD"
        fi
        printf '\n- %s' "$TRAIT" >> "$AGENT_MD"
        echo "Added trait. Restart gateway for it to take effect:"
        echo "  ~/bin/agent-self.sh restart"
        ;;
    personality-set)
        SECTION="${2:?}"; TEXT="${3:?}"
        log_event personality-set "$SECTION"
        snapshot_to_rag >/dev/null
        # Replace section content (between this ## and next ##)
        python3 -c "
import re
with open('$AGENT_MD') as f: content = f.read()
new_section = '## $SECTION\n\n$TEXT\n'
pattern = r'## $SECTION.*?(?=^## |\Z)'
if re.search(pattern, content, flags=re.MULTILINE | re.DOTALL):
    content = re.sub(pattern, new_section, content, count=1, flags=re.MULTILINE | re.DOTALL)
else:
    content += '\n\n' + new_section
with open('$AGENT_MD', 'w') as f: f.write(content)
print(f'Section [$SECTION] updated')
"
        ;;
    personality-history)
        if [ -x "$BIN/rag-tool.sh" ]; then
            "$BIN/rag-tool.sh" list 2>/dev/null | grep '^self:personality:' || echo "No personality snapshots in RAG yet"
        fi
        ;;
    capability-add)
        NAME="${2:?Usage: agent-self.sh capability-add <name> <script-content-file>}"
        SCRIPT="${3:?}"
        DEST="$BIN/${NAME}.sh"
        if [ -f "$SCRIPT" ]; then
            cp "$SCRIPT" "$DEST"
        else
            # Treat $SCRIPT as inline content
            printf '#!/data/data/com.termux/files/usr/bin/bash\n%s\n' "$SCRIPT" > "$DEST"
        fi
        chmod 700 "$DEST"
        log_event capability-add "$NAME"
        # Auto-document in AGENT.md
        printf '\n- `~/bin/%s.sh` — %s (added %s)' "$NAME" "$(head -3 "$DEST" | grep -oP '(?<=# ).+' | head -1 || echo "custom capability")" "$(date +%Y-%m-%d)" >> "$AGENT_MD"
        echo "Capability installed: $DEST"
        ;;
    capability-list)
        for f in "$BIN"/*.sh "$BIN"/*.py; do
            [ -e "$f" ] || continue
            DESC=$(grep -m1 '^# .* -- ' "$f" 2>/dev/null | sed 's/^# //' || basename "$f")
            printf '%-25s %s\n' "$(basename "$f")" "${DESC:0:80}"
        done
        ;;
    capability-remove)
        NAME="${2:?}"
        DEST="$BIN/${NAME}.sh"
        [ -f "$DEST" ] && rm "$DEST" && log_event capability-remove "$NAME" && echo "Removed: $DEST" || echo "Not found: $DEST"
        ;;
    config-get)
        KEY="${2:?}"
        jq -r ".$KEY" "$CONFIG"
        ;;
    config-set)
        KEY="${2:?}"; VAL="${3:?}"
        log_event config-set "$KEY=$VAL"
        # Snapshot config first
        cp "$CONFIG" "$SNAPSHOTS_DIR/config-$(date +%Y%m%d-%H%M%S).json"
        # Try to set as string, then number, then boolean
        TMP=$(mktemp)
        if jq --arg v "$VAL" ".$KEY = \$v" "$CONFIG" > "$TMP" 2>/dev/null; then
            mv "$TMP" "$CONFIG"
            chmod 600 "$CONFIG"
            echo "Set $KEY = \"$VAL\""
        else
            rm -f "$TMP"
            echo "Failed to set $KEY"
        fi
        ;;
    restart)
        log_event restart
        echo "Restarting gateway..."
        tmux kill-session -t picoclaw 2>/dev/null || true
        pkill -f "picoclaw.bin gateway" 2>/dev/null || true
        sleep 2
        tmux new-session -d -s picoclaw \
            "SSL_CERT_FILE=/data/data/com.termux/files/usr/etc/tls/cert.pem $HOME/picoclaw.bin gateway > $HOME/.picoclaw/gateway.log 2>&1"
        sleep 5
        if curl -sf http://127.0.0.1:18790/health >/dev/null 2>&1; then
            echo "Gateway: HEALTHY"
        else
            echo "Gateway: FAILED — check ~/.picoclaw/gateway.log"
        fi
        ;;
    snapshot)
        SNAP_ID="snap-$(date +%Y%m%d-%H%M%S)"
        SNAP_DIR="$SNAPSHOTS_DIR/$SNAP_ID"
        mkdir -p "$SNAP_DIR"
        cp "$AGENT_MD" "$SNAP_DIR/AGENT.md" 2>/dev/null || true
        cp "$CONFIG" "$SNAP_DIR/config.json" 2>/dev/null || true
        cp "$HOME/.picoclaw/.security.yml" "$SNAP_DIR/security.yml.enc" 2>/dev/null || true
        # Index snapshot ID in RAG
        if [ -x "$BIN/rag-tool.sh" ]; then
            "$BIN/rag-tool.sh" add-text "self:snapshot:$SNAP_ID" \
                "Snapshot $SNAP_ID created at $(date). AGENT.md size: $(wc -l < $AGENT_MD) lines. Config keys: $(jq 'keys|length' $CONFIG)" >/dev/null 2>&1 || true
        fi
        log_event snapshot "$SNAP_ID"
        echo "Snapshot saved: $SNAP_DIR"
        echo "Restore with: ~/bin/agent-self.sh rollback $SNAP_ID"
        ;;
    rollback)
        SNAP_ID="${2:?Usage: agent-self.sh rollback <snapshot-id>}"
        SNAP_DIR="$SNAPSHOTS_DIR/$SNAP_ID"
        [ -d "$SNAP_DIR" ] || { echo "Snapshot not found: $SNAP_ID"; exit 1; }
        log_event rollback "$SNAP_ID"
        # Backup current first
        "$0" snapshot
        [ -f "$SNAP_DIR/AGENT.md" ] && cp "$SNAP_DIR/AGENT.md" "$AGENT_MD"
        [ -f "$SNAP_DIR/config.json" ] && cp "$SNAP_DIR/config.json" "$CONFIG"
        chmod 600 "$AGENT_MD" "$CONFIG"
        echo "Rolled back to $SNAP_ID. Restart gateway to apply:"
        echo "  ~/bin/agent-self.sh restart"
        ;;
    snapshots)
        ls -lt "$SNAPSHOTS_DIR" 2>/dev/null | head -20
        ;;
    history)
        N="${2:-30}"
        tail -n "$N" "$SELF_LOG" 2>/dev/null | python3 -c "
import sys, json
for line in sys.stdin:
    try:
        d = json.loads(line)
        print(f\"[{d['ts'][:19]}] {d['action']:20s} {d.get('args','')[:60]}\")
    except: pass
"
        ;;
    help|*)
        head -32 "$0" | tail -30 | sed 's/^# //;s/^#//'
        ;;
esac
