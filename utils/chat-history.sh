#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# chat-history.sh -- Owner-authorized cross-session recall
# =============================================================================
# Thin wrapper around the RAG memory index and the session JSONL files so the
# agent can answer questions like:
#   - "qué te dije ayer en mi otra cuenta de Telegram?"
#   - "resume mis últimos mensajes de esta semana"
#   - "desde qué cuentas he hablado contigo?"
#
# The policy gate is the env var AGENT_CROSS_CHAT_ACCESS. When `false` the
# tool refuses with a structured message the agent can forward verbatim.
# When `true` the tool queries RAG (`mem:` doc_id space) and the session
# JSONL files under ~/.picoclaw/workspace/sessions/.
#
# Usage:
#   ~/bin/chat-history.sh recent [N]             Last N messages across sessions (default 20)
#   ~/bin/chat-history.sh session <name> [N]     Last N messages from one session
#   ~/bin/chat-history.sh search "<query>" [N]   RAG semantic+BM25 search over memory
#   ~/bin/chat-history.sh accounts               Distinct Telegram IDs with counts
#   ~/bin/chat-history.sh sessions               List every session file with sizes
#   ~/bin/chat-history.sh policy                 Print the current access policy
#
# Exit codes:
#   0  success / authorized
#   7  access denied by policy (AGENT_CROSS_CHAT_ACCESS != true)
#
# Security:
#   - Reads only files under $HOME/.picoclaw/workspace/sessions/ (fixed path).
#   - Session names are validated against [a-zA-Z0-9_.-]{1,128}.
#   - Never writes; never forwards data off-device.
# =============================================================================

set -eu
SESSIONS_DIR="$HOME/.picoclaw/workspace/sessions"
DB="$HOME/.picoclaw/workspace/knowledge/rag.db"
FLAG="${AGENT_CROSS_CHAT_ACCESS:-}"

# --- helpers ----------------------------------------------------------------
authorized() {
    case "${FLAG,,}" in
        1|true|yes|on) return 0 ;;
        *) return 1 ;;
    esac
}

refuse() {
    cat <<REFUSE
{
  "status": "denied",
  "reason": "AGENT_CROSS_CHAT_ACCESS is not enabled on this deployment",
  "hint": "set AGENT_CROSS_CHAT_ACCESS=true in ~/.picoclaw_keys, then restart the gateway (system-tool.sh restart gateway)"
}
REFUSE
    exit 7
}

validate_session() {
    local n="$1"
    if ! printf '%s' "$n" | grep -Eq '^[a-zA-Z0-9_.-]{1,128}$'; then
        echo "error: invalid session name '$n'" >&2
        exit 2
    fi
}

# --- commands ---------------------------------------------------------------
CMD="${1:-policy}"

case "$CMD" in
    policy)
        if authorized; then
            echo "policy: AGENT_CROSS_CHAT_ACCESS=ON (owner-authorized cross-session recall via RAG)"
        else
            echo "policy: AGENT_CROSS_CHAT_ACCESS=OFF (current-session only)"
        fi
        ;;

    sessions)
        authorized || refuse
        [ -d "$SESSIONS_DIR" ] || { echo "no sessions yet"; exit 0; }
        printf "%-60s %10s %6s\n" "SESSION" "BYTES" "LINES"
        printf "%s\n" "$(printf '%*s' 80 '' | tr ' ' '-')"
        for f in "$SESSIONS_DIR"/*.jsonl; do
            [ -f "$f" ] || continue
            bn=$(basename "$f" .jsonl)
            sz=$(stat -c%s "$f" 2>/dev/null || echo 0)
            lc=$(wc -l < "$f" 2>/dev/null | tr -d ' ')
            printf "%-60s %10s %6s\n" "$bn" "$sz" "$lc"
        done
        ;;

    accounts)
        authorized || refuse
        # Extract distinct Telegram user IDs from filenames like:
        #   agent_main_telegram_direct_1945416503.jsonl
        # And summarize counts + last seen.
        python3 - "$SESSIONS_DIR" <<'PYEOF'
import json, os, sys, re
from datetime import datetime
root = sys.argv[1]
buckets = {}
pat = re.compile(r'telegram[_-]direct[_-](\d+)', re.I)
if os.path.isdir(root):
    for name in sorted(os.listdir(root)):
        if not name.endswith('.jsonl'):
            continue
        m = pat.search(name)
        key = m.group(1) if m else name.replace('.jsonl','')
        path = os.path.join(root, name)
        try:
            size = os.path.getsize(path)
            with open(path, 'rb') as f:
                # cheap line count
                lines = sum(1 for _ in f)
            mtime = datetime.fromtimestamp(os.path.getmtime(path)).isoformat(timespec='seconds')
        except Exception:
            lines, size, mtime = 0, 0, '?'
        b = buckets.setdefault(key, {'channels': [], 'messages': 0, 'bytes': 0, 'last': ''})
        b['channels'].append(name)
        b['messages'] += lines
        b['bytes'] += size
        if mtime > b['last']: b['last'] = mtime
print(json.dumps(buckets, indent=2, ensure_ascii=False))
PYEOF
        ;;

    session)
        authorized || refuse
        NAME="${2:?Usage: chat-history.sh session <name> [N]}"
        N="${3:-30}"
        validate_session "$NAME"
        # Allow full names or partial matches (so the agent can pass a
        # Telegram user ID and we find the matching session).
        MATCHES=$(ls "$SESSIONS_DIR"/*.jsonl 2>/dev/null | grep -F "$NAME" || true)
        if [ -z "$MATCHES" ]; then
            echo "no session matches '$NAME'"; exit 1
        fi
        python3 - "$N" $MATCHES <<'PYEOF'
import json, sys
n = int(sys.argv[1])
files = sys.argv[2:]
rows = []
for f in files:
    try:
        for line in open(f):
            line = line.strip()
            if not line: continue
            try: rows.append(json.loads(line))
            except Exception: pass
    except Exception: pass
for r in rows[-n:]:
    ts = r.get('ts') or r.get('timestamp') or ''
    role = r.get('role') or r.get('speaker') or '?'
    content = (r.get('content') or r.get('text') or r.get('message') or '')
    if isinstance(content, list):
        content = ' '.join(str(c) for c in content)
    content = str(content).replace('\n', ' ')[:400]
    print(f'[{ts}] ({role}) {content}')
PYEOF
        ;;

    recent)
        authorized || refuse
        N="${2:-20}"
        [ -d "$SESSIONS_DIR" ] || { echo "no sessions yet"; exit 0; }
        python3 - "$N" "$SESSIONS_DIR" <<'PYEOF'
import json, os, sys
n = int(sys.argv[1])
root = sys.argv[2]
rows = []
for name in os.listdir(root):
    if not name.endswith('.jsonl'): continue
    path = os.path.join(root, name)
    try:
        for line in open(path):
            line = line.strip()
            if not line: continue
            try:
                r = json.loads(line)
                r['__src'] = name.replace('.jsonl','')
                rows.append(r)
            except Exception: pass
    except Exception: pass
# sort by ts when present
def ts_of(r):
    return r.get('ts') or r.get('timestamp') or ''
rows.sort(key=ts_of)
for r in rows[-n:]:
    ts = ts_of(r)
    role = r.get('role') or r.get('speaker') or '?'
    src = r.get('__src', '?')
    content = (r.get('content') or r.get('text') or r.get('message') or '')
    if isinstance(content, list):
        content = ' '.join(str(c) for c in content)
    content = str(content).replace('\n', ' ')[:300]
    print(f'[{ts}] <{src}> ({role}) {content}')
PYEOF
        ;;

    search)
        authorized || refuse
        Q="${2:?Usage: chat-history.sh search \"<query>\" [N]}"
        N="${3:-10}"
        # Delegate to memory-ingest.sh which already queries the `mem:` slice
        # of RAG. Keeps one source of truth for memory search.
        if [ -x "$HOME/bin/memory-ingest.sh" ]; then
            "$HOME/bin/memory-ingest.sh" search "$Q" "$N"
        elif [ -x "$HOME/bin/rag-tool.sh" ]; then
            "$HOME/bin/rag-tool.sh" search "$Q" "$N"
        else
            echo "error: no memory search tool found" >&2; exit 1
        fi
        ;;

    help|-h|--help)
        sed -n '2,/^# =====/p' "$0" | sed 's/^# \{0,1\}//' | head -40
        ;;

    *)
        echo "unknown command: $CMD" >&2
        echo "try: policy | sessions | accounts | session <name> [N] | recent [N] | search \"<q>\" [N]" >&2
        exit 2
        ;;
esac
