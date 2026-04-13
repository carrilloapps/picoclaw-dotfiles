#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# context-inject.sh -- Retrieve RAG context for the agent before LLM call
# =============================================================================
# Called by the agent (via exec) to get relevant context from RAG memory
# before answering. Makes context consistent across LLM switches.
#
# Usage:
#   ~/bin/context-inject.sh <user-message>            # Returns top-3 context chunks
#   ~/bin/context-inject.sh --session <key> <msg>     # Include session context
#   ~/bin/context-inject.sh --count <n> <msg>         # Top-N chunks (default 3)
#   ~/bin/context-inject.sh --format [md|plain|json]  # Output format
#
# Output is meant to be prepended to the user's prompt:
#   [CONTEXT FROM MEMORY]
#   <retrieved chunks>
#   [END CONTEXT]
#
#   <user message>
# =============================================================================

set -eu
COUNT=3
FORMAT="md"
SESSION=""
MSG=""

while [ $# -gt 0 ]; do
    case "$1" in
        --count) COUNT="$2"; shift 2 ;;
        --session) SESSION="$2"; shift 2 ;;
        --format) FORMAT="$2"; shift 2 ;;
        *) MSG="$MSG $1"; shift ;;
    esac
done
MSG=$(echo "$MSG" | sed 's/^ *//;s/ *$//')

[ -n "$MSG" ] || { echo "Usage: context-inject.sh [--session k] [--count n] <message>" >&2; exit 1; }

# Get hybrid RAG context
CONTEXT=$(~/bin/rag-tool.sh search "$MSG" "$COUNT" 2>/dev/null | grep -v '^$' || true)

if [ -z "$CONTEXT" ]; then
    # No context — just echo the message back
    echo "$MSG"
    exit 0
fi

case "$FORMAT" in
    json)
        python3 -c "
import json
ctx = '''$CONTEXT'''
print(json.dumps({'context': ctx, 'message': '''$MSG'''}, indent=2))
"
        ;;
    plain)
        echo "[MEMORY]"
        echo "$CONTEXT"
        echo "[/MEMORY]"
        echo ""
        echo "$MSG"
        ;;
    md|*)
        cat <<EOF
<memory>
$CONTEXT
</memory>

$MSG
EOF
        ;;
esac
