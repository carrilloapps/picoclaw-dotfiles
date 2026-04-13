#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# audit-log.sh -- Security audit trail for all agent activity
# =============================================================================
# Records every tool invocation, command execution, API call, and security
# event for compliance and forensics.
#
# Usage:
#   ~/bin/audit-log.sh tail [n]            # Show last N events (default 20)
#   ~/bin/audit-log.sh search <query>      # Search audit log
#   ~/bin/audit-log.sh stats               # Event counts by type
#   ~/bin/audit-log.sh export [days]       # Export last N days as JSON
#   ~/bin/audit-log.sh record <type> <json># Record a new event (for scripts)
# =============================================================================

set -eu
AUDIT="${HOME}/.picoclaw/audit.log"
CMD="${1:-tail}"
mkdir -p "$(dirname "$AUDIT")"

case "$CMD" in
    tail)
        N="${2:-20}"
        tail -n "$N" "$AUDIT" 2>/dev/null | while IFS= read -r line; do
            echo "$line" | python3 -c "
import sys, json
try:
    d = json.loads(sys.stdin.read())
    print(f\"[{d.get('ts','?')[:19]}] {d.get('type','?'):<15} {d.get('actor','?'):<15} {d.get('action','?')[:80]}\")
except: pass
"
        done
        ;;
    search)
        Q="${2:?Usage: audit-log.sh search <query>}"
        grep -i "$Q" "$AUDIT" 2>/dev/null | tail -20 | python3 -c "
import sys, json
for line in sys.stdin:
    try:
        d = json.loads(line)
        print(f\"[{d.get('ts','?')[:19]}] {d.get('type','?')} {d.get('action','?')[:100]}\")
    except: pass
"
        ;;
    stats)
        python3 <<PYEOF
import json
from collections import Counter
types = Counter()
actors = Counter()
try:
    with open('$AUDIT') as f:
        for line in f:
            try:
                d = json.loads(line)
                types[d.get('type', 'unknown')] += 1
                actors[d.get('actor', 'unknown')] += 1
            except: pass
    print('=== Event types ===')
    for t, n in types.most_common(20):
        print(f'  {t:<25s} {n:>6}')
    print()
    print('=== Actors ===')
    for a, n in actors.most_common(10):
        print(f'  {a:<25s} {n:>6}')
except FileNotFoundError:
    print('No audit log yet')
PYEOF
        ;;
    export)
        DAYS="${2:-7}"
        python3 -c "
import json, sys
from datetime import datetime, timedelta, timezone
cutoff = (datetime.now(timezone.utc) - timedelta(days=$DAYS)).isoformat()
with open('$AUDIT') as f:
    for line in f:
        try:
            d = json.loads(line)
            if d.get('ts', '') >= cutoff:
                print(json.dumps(d))
        except: pass
"
        ;;
    record)
        TYPE="${2:?}"; DATA="${3:-{}}"
        python3 -c "
import json, sys
from datetime import datetime, timezone
event = {'ts': datetime.now(timezone.utc).isoformat(), 'type': '$TYPE', **json.loads('''$DATA''')}
with open('$AUDIT', 'a') as f:
    f.write(json.dumps(event) + '\n')
print('Recorded')
"
        ;;
    help|*)
        head -12 "$0" | tail -10 | sed 's/^# //;s/^#//'
        ;;
esac
