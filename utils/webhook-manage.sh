#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# webhook-manage.sh -- Dynamic webhook route + form creation
# =============================================================================
# Lets the agent create custom HTTP endpoints at runtime without touching
# webhook-server.py. Each custom route is a script that runs when the route
# is hit. Forms are HTML pages served from the webhook server.
#
# URL shape: https://<tunnel>/c/<name>  (short prefix; legacy /custom/ is
# kept as a 301 redirect inside webhook-server.py for backwards compat).
#
# Route name rules: [a-z0-9][a-z0-9_-]{0,62} (strictly validated).
#
# The agent can do:
#   - "Create a webhook that logs to a file"     -> webhook-manage.sh create-route
#   - "Make a form to collect names and emails"  -> webhook-manage.sh create-form
#   - "Show me all my webhooks"                  -> webhook-manage.sh list
#
# Usage:
#   Creation:
#     ~/bin/webhook-manage.sh create-route <name> <handler-script-or-inline> [on|off]
#     ~/bin/webhook-manage.sh create-form <name> <html-file-or-inline>
#     ~/bin/webhook-manage.sh clone <existing> <new-name>
#
#   Inspection:
#     ~/bin/webhook-manage.sh list
#     ~/bin/webhook-manage.sh show <name>
#     ~/bin/webhook-manage.sh data <name>          # Show collected submissions
#     ~/bin/webhook-manage.sh url <name>           # Public URL
#     ~/bin/webhook-manage.sh stats <name>         # Submission count + last timestamp
#
#   Modification:
#     ~/bin/webhook-manage.sh update-html <name> <html-file-or-inline>
#     ~/bin/webhook-manage.sh update-handler <name> <script-or-inline>
#     ~/bin/webhook-manage.sh rename <old-name> <new-name>   # Changes URL!
#     ~/bin/webhook-manage.sh auth <name> on|off             # Toggle bearer auth
#     ~/bin/webhook-manage.sh methods <name> <GET,POST,...>  # Allowed methods
#
#   Deletion:
#     ~/bin/webhook-manage.sh remove <name>        # Backup + delete
#     ~/bin/webhook-manage.sh clear-data <name>    # Keep route, wipe submissions
#
# Storage:
#   ~/.picoclaw/webhooks/<name>/
#     handler.sh       # Custom handler (executed per request)
#     form.html        # Optional HTML form
#     data.jsonl       # Collected submissions (JSON-Lines)
#     meta.json        # Route config (auth, method, created_at)
# =============================================================================

set -eu
WEBHOOK_DIR="${HOME}/.picoclaw/webhooks"
mkdir -p "$WEBHOOK_DIR"

CMD="${1:-help}"

# Short prefix (matches webhook-server.py /c/<name> route).
# Legacy /custom/ still works via 301 redirect in the server.
PREFIX="/c"

# Strict route name: lowercase, digits, _-, 1..63 chars, cannot start with -
validate_name() {
    local n="$1"
    if ! printf '%s' "$n" | grep -Eq '^[a-z0-9][a-z0-9_-]{0,62}$'; then
        echo "error: invalid name '$n' (allowed: [a-z0-9][a-z0-9_-]{0,62})" >&2
        exit 2
    fi
}

get_public_url() {
    local base=""
    if [ -x "$HOME/bin/cloudflare-tool.sh" ]; then
        base=$("$HOME/bin/cloudflare-tool.sh" url 2>/dev/null || true)
    fi
    echo "$base"
}

case "$CMD" in
    create-route)
        NAME="${2:?Usage: webhook-manage.sh create-route <name> <handler-script>}"
        validate_name "$NAME"
        HANDLER="${3:?}"
        AUTH="${4:-on}"
        DIR="$WEBHOOK_DIR/$NAME"
        mkdir -p "$DIR"
        if [ -f "$HANDLER" ]; then
            cp "$HANDLER" "$DIR/handler.sh"
        else
            # Treat as inline script
            cat > "$DIR/handler.sh" << EOF
#!/data/data/com.termux/files/usr/bin/bash
# Auto-generated handler for webhook '$NAME'
# Input: request body on stdin, query string in \$1
# Output: response body on stdout, HTTP status via exit code (0=200, 1=500)
$HANDLER
EOF
        fi
        chmod 700 "$DIR/handler.sh"

        cat > "$DIR/meta.json" << META
{
  "name": "$NAME",
  "created_at": "$(date -Iseconds)",
  "auth_required": $([ "$AUTH" = "on" ] && echo true || echo false),
  "methods": ["POST", "GET"],
  "path": "$PREFIX/$NAME"
}
META
        PUBLIC=$(get_public_url)
        echo "Route created: $NAME"
        echo "Handler: $DIR/handler.sh"
        [ -n "$PUBLIC" ] && echo "Public URL: $PUBLIC$PREFIX/$NAME" || echo "Local URL:  http://localhost:18791$PREFIX/$NAME"
        echo "Auth: $AUTH"
        # Reload webhook server to pick up new route
        # No reload needed: webhook-server reads route files per-request.
        ;;

    create-form)
        NAME="${2:?Usage: webhook-manage.sh create-form <name> <html-or-file>}"
        validate_name "$NAME"
        HTML_SRC="${3:?}"
        DIR="$WEBHOOK_DIR/$NAME"
        mkdir -p "$DIR"
        if [ -f "$HTML_SRC" ]; then
            cp "$HTML_SRC" "$DIR/form.html"
        else
            echo "$HTML_SRC" > "$DIR/form.html"
        fi
        # Install the universal form-handler as a copy (not symlink — easier for chmod)
        if [ -f "$HOME/bin/form-handler.sh" ]; then
            cp "$HOME/bin/form-handler.sh" "$DIR/handler.sh"
            chmod 700 "$DIR/handler.sh"
        else
            # Fallback inline handler if form-handler.sh isn't installed
            cat > "$DIR/handler.sh" << HANDLER
#!/data/data/com.termux/files/usr/bin/bash
# Form submission handler (auto-generated by webhook-manage.sh)
set -eu
DIR="\$(dirname "\$(readlink -f "\$0")")"
NAME="$NAME"
METHOD="\${REQUEST_METHOD:-GET}"
BODY=\$(cat)

if [ "\$METHOD" = "GET" ]; then
    cat "\$DIR/form.html"
    exit 0
fi

# POST: parse + store + notify
python3 - <<PYEOF
import sys, json, os, subprocess, urllib.parse, tempfile
from datetime import datetime

body = '''\$BODY'''
name = '$NAME'
entry = {'ts': datetime.now().isoformat(), 'ip': os.environ.get('REMOTE_ADDR', '')}
try:
    entry.update(json.loads(body))
except Exception:
    for k, v in urllib.parse.parse_qsl(body):
        entry[k] = v

# 1. Store JSONL
data_file = os.path.join('\$DIR', 'data.jsonl')
with open(data_file, 'a') as f:
    f.write(json.dumps(entry, ensure_ascii=False) + '\n')

# 2. Index in RAG for agent memory
summary = ', '.join(f'{k}={v}'[:80] for k, v in entry.items() if k not in ('ts', 'ip'))
doc_id = f'form:{name}:' + datetime.now().strftime('%Y%m%d-%H%M%S')
content = f'Form submission on {entry[\"ts\"]} to /c/{name}:\n' + \
          '\n'.join(f'{k}: {v}' for k, v in entry.items())
try:
    with tempfile.NamedTemporaryFile('w', delete=False, suffix='.txt') as tf:
        tf.write(content)
        tmp_path = tf.name
    subprocess.run([os.path.expanduser('~/bin/rag-tool.sh'), 'add', doc_id, tmp_path],
                   timeout=30, capture_output=True)
    os.unlink(tmp_path)
except Exception: pass

# 3. Android notification
try:
    subprocess.run(['termux-notification',
                    '--title', f'Form: {name}',
                    '--content', summary[:200],
                    '--priority', 'default',
                    '--id', f'form-{name}'],
                   timeout=5, capture_output=True)
except Exception: pass

# 4. Telegram notification to owner (if bot configured)
try:
    import urllib.request
    # Source .security.yml to get telegram token
    import yaml
    sec = yaml.safe_load(open(os.path.expanduser('~/.picoclaw/.security.yml'))) or {}
    token = sec.get('channels', {}).get('telegram', {}).get('token', '').strip('"')
    # Get owner from config.json
    cfg = json.load(open(os.path.expanduser('~/.picoclaw/config.json')))
    owners = cfg.get('channels', {}).get('telegram', {}).get('allow_from', [])
    if token and owners:
        owner = owners[0]
        msg = f'\ud83d\udce9 New submission to /{name}\n\n' + \
              '\n'.join(f'<b>{k}:</b> {v}' for k, v in entry.items() if k not in ('ts', 'ip'))
        url = f'https://api.telegram.org/bot{token}/sendMessage'
        data = json.dumps({'chat_id': owner, 'text': msg, 'parse_mode': 'HTML'}).encode()
        req = urllib.request.Request(url, data=data, headers={'Content-Type': 'application/json'})
        urllib.request.urlopen(req, timeout=10)
except Exception as e:
    pass

print(json.dumps({'status': 'received', 'count': 1, 'indexed_as': doc_id}))
PYEOF
HANDLER
            chmod 700 "$DIR/handler.sh"
        fi

        cat > "$DIR/meta.json" << META
{
  "name": "$NAME",
  "created_at": "$(date -Iseconds)",
  "auth_required": false,
  "methods": ["GET", "POST"],
  "path": "$PREFIX/$NAME",
  "type": "form"
}
META
        PUBLIC=$(get_public_url)
        echo "Form created: $NAME"
        echo "HTML: $DIR/form.html"
        [ -n "$PUBLIC" ] && echo "Public URL: $PUBLIC$PREFIX/$NAME" || echo "Local URL:  http://localhost:18791$PREFIX/$NAME"
        echo "Submissions stored in: $DIR/data.jsonl"
        # No reload needed: webhook-server reads route files per-request.
        ;;

    list)
        if [ -d "$WEBHOOK_DIR" ] && [ "$(ls -A "$WEBHOOK_DIR" 2>/dev/null)" ]; then
            for d in "$WEBHOOK_DIR"/*/; do
                [ -d "$d" ] || continue
                name=$(basename "$d")
                meta="$d/meta.json"
                if [ -f "$meta" ]; then
                    auth=$(jq -r '.auth_required' "$meta" 2>/dev/null)
                    created=$(jq -r '.created_at' "$meta" 2>/dev/null)
                    type=$(jq -r '.type // "route"' "$meta" 2>/dev/null)
                    count=0
                    [ -f "$d/data.jsonl" ] && count=$(wc -l < "$d/data.jsonl" 2>/dev/null | tr -d ' ')
                    printf "%-20s type=%-6s auth=%-5s submissions=%-4s created=%s\n" "$name" "$type" "$auth" "$count" "$created"
                fi
            done
        else
            echo "No custom webhooks. Create with: webhook-manage.sh create-route <name> <handler>"
        fi
        ;;

    show)
        NAME="${2:?}"
        DIR="$WEBHOOK_DIR/$NAME"
        [ -d "$DIR" ] || { echo "Not found: $NAME"; exit 1; }
        echo "=== Meta ==="
        cat "$DIR/meta.json" 2>/dev/null | jq .
        echo ""
        if [ -f "$DIR/form.html" ]; then
            echo "=== Form HTML ($(wc -l < "$DIR/form.html") lines) ==="
            head -30 "$DIR/form.html"
        fi
        echo ""
        echo "=== Handler ==="
        cat "$DIR/handler.sh"
        ;;

    data)
        NAME="${2:?}"
        DIR="$WEBHOOK_DIR/$NAME"
        FILE="$DIR/data.jsonl"
        [ -f "$FILE" ] || { echo "No submissions for $NAME"; exit 0; }
        python3 -c "
import json
with open('$FILE') as f:
    rows = [json.loads(l) for l in f if l.strip()]
print(f'Total: {len(rows)}')
for r in rows[-10:]:
    print(json.dumps(r, indent=2, ensure_ascii=False))
"
        ;;

    remove|delete)
        NAME="${2:?}"
        DIR="$WEBHOOK_DIR/$NAME"
        [ -d "$DIR" ] || { echo "Not found: $NAME"; exit 1; }
        # Backup before deleting
        BACKUP="$HOME/.picoclaw/backups/webhook-$NAME-$(date +%Y%m%d-%H%M%S).tar.gz"
        mkdir -p "$(dirname "$BACKUP")"
        tar czf "$BACKUP" -C "$WEBHOOK_DIR" "$NAME"
        rm -rf "$DIR"
        echo "Removed $NAME (backup at $BACKUP)"
        # No reload needed: webhook-server reads route files per-request.
        ;;

    url)
        NAME="${2:?}"
        PUBLIC=$(get_public_url)
        if [ -n "$PUBLIC" ]; then
            echo "$PUBLIC$PREFIX/$NAME"
        else
            echo "http://localhost:18791$PREFIX/$NAME"
        fi
        ;;

    auth)
        NAME="${2:?}"; MODE="${3:?on|off}"
        DIR="$WEBHOOK_DIR/$NAME"
        [ -d "$DIR" ] || { echo "Not found: $NAME"; exit 1; }
        BOOL=$([ "$MODE" = "on" ] && echo true || echo false)
        jq ".auth_required = $BOOL" "$DIR/meta.json" > "$DIR/meta.json.tmp" && mv "$DIR/meta.json.tmp" "$DIR/meta.json"
        echo "$NAME auth: $MODE"
        # No reload needed: webhook-server reads route files per-request.
        ;;

    update-html)
        NAME="${2:?}"; HTML_SRC="${3:?Usage: update-html <name> <html-file-or-inline>}"
        DIR="$WEBHOOK_DIR/$NAME"
        [ -d "$DIR" ] || { echo "Not found: $NAME"; exit 1; }
        # Snapshot previous form
        [ -f "$DIR/form.html" ] && cp "$DIR/form.html" "$DIR/form.html.bak-$(date +%s)"
        if [ -f "$HTML_SRC" ]; then
            cp "$HTML_SRC" "$DIR/form.html"
        else
            echo "$HTML_SRC" > "$DIR/form.html"
        fi
        echo "HTML updated for $NAME"
        # No reload needed: webhook-server reads route files per-request.
        ;;

    update-handler)
        NAME="${2:?}"; HANDLER="${3:?Usage: update-handler <name> <script-or-inline>}"
        DIR="$WEBHOOK_DIR/$NAME"
        [ -d "$DIR" ] || { echo "Not found: $NAME"; exit 1; }
        cp "$DIR/handler.sh" "$DIR/handler.sh.bak-$(date +%s)"
        if [ -f "$HANDLER" ]; then
            cp "$HANDLER" "$DIR/handler.sh"
        else
            cat > "$DIR/handler.sh" << EOF
#!/data/data/com.termux/files/usr/bin/bash
# Updated handler for webhook '$NAME' ($(date -Iseconds))
$HANDLER
EOF
        fi
        chmod 700 "$DIR/handler.sh"
        echo "Handler updated for $NAME"
        # No reload needed: webhook-server reads route files per-request.
        ;;

    rename)
        OLD="${2:?}"; NEW="${3:?Usage: rename <old> <new>}"
        validate_name "$NEW"
        OLD_DIR="$WEBHOOK_DIR/$OLD"; NEW_DIR="$WEBHOOK_DIR/$NEW"
        [ -d "$OLD_DIR" ] || { echo "Source not found: $OLD"; exit 1; }
        [ -d "$NEW_DIR" ] && { echo "Target already exists: $NEW"; exit 1; }
        mv "$OLD_DIR" "$NEW_DIR"
        # Update meta.json
        jq ".name = \"$NEW\" | .path = \"$PREFIX/$NEW\"" "$NEW_DIR/meta.json" > "$NEW_DIR/meta.json.tmp" && \
            mv "$NEW_DIR/meta.json.tmp" "$NEW_DIR/meta.json"
        PUBLIC=$(get_public_url)
        echo "Renamed $OLD -> $NEW"
        [ -n "$PUBLIC" ] && echo "New public URL: $PUBLIC$PREFIX/$NEW"
        # No reload needed: webhook-server reads route files per-request.
        ;;

    clone)
        OLD="${2:?}"; NEW="${3:?Usage: clone <existing> <new-name>}"
        validate_name "$NEW"
        OLD_DIR="$WEBHOOK_DIR/$OLD"; NEW_DIR="$WEBHOOK_DIR/$NEW"
        [ -d "$OLD_DIR" ] || { echo "Source not found: $OLD"; exit 1; }
        [ -d "$NEW_DIR" ] && { echo "Target already exists: $NEW"; exit 1; }
        cp -r "$OLD_DIR" "$NEW_DIR"
        rm -f "$NEW_DIR/data.jsonl"   # Fresh submission log
        # Update meta.json with new name + timestamp
        jq ".name = \"$NEW\" | .path = \"$PREFIX/$NEW\" | .created_at = \"$(date -Iseconds)\" | .cloned_from = \"$OLD\"" \
            "$NEW_DIR/meta.json" > "$NEW_DIR/meta.json.tmp" && mv "$NEW_DIR/meta.json.tmp" "$NEW_DIR/meta.json"
        PUBLIC=$(get_public_url)
        echo "Cloned $OLD -> $NEW"
        [ -n "$PUBLIC" ] && echo "Public URL: $PUBLIC$PREFIX/$NEW"
        # No reload needed: webhook-server reads route files per-request.
        ;;

    methods)
        NAME="${2:?}"; METHODS="${3:?Usage: methods <name> <GET,POST,...>}"
        DIR="$WEBHOOK_DIR/$NAME"
        [ -d "$DIR" ] || { echo "Not found: $NAME"; exit 1; }
        python3 -c "
import json
with open('$DIR/meta.json') as f: m = json.load(f)
m['methods'] = '$METHODS'.split(',')
with open('$DIR/meta.json', 'w') as f: json.dump(m, f, indent=2)
print(f'Methods for $NAME: {m[\"methods\"]}')
"
        # No reload needed: webhook-server reads route files per-request.
        ;;

    stats)
        NAME="${2:?}"
        DIR="$WEBHOOK_DIR/$NAME"
        [ -d "$DIR" ] || { echo "Not found: $NAME"; exit 1; }
        COUNT=0
        LAST=""
        if [ -f "$DIR/data.jsonl" ]; then
            COUNT=$(wc -l < "$DIR/data.jsonl" 2>/dev/null | tr -d ' ')
            LAST=$(tail -1 "$DIR/data.jsonl" 2>/dev/null | jq -r .ts 2>/dev/null || echo "?")
        fi
        SIZE=$(du -sh "$DIR" 2>/dev/null | cut -f1)
        AUTH=$(jq -r '.auth_required' "$DIR/meta.json" 2>/dev/null)
        CREATED=$(jq -r '.created_at' "$DIR/meta.json" 2>/dev/null)
        cat << STATS
Name:        $NAME
Submissions: $COUNT
Last:        $LAST
Size:        $SIZE
Auth:        $AUTH
Created:     $CREATED
URL:         $(get_public_url)$PREFIX/$NAME
STATS
        ;;

    clear-data)
        NAME="${2:?}"
        DIR="$WEBHOOK_DIR/$NAME"
        [ -d "$DIR" ] || { echo "Not found: $NAME"; exit 1; }
        if [ -f "$DIR/data.jsonl" ]; then
            # Backup + clear
            mv "$DIR/data.jsonl" "$DIR/data.jsonl.archived-$(date +%s)"
            : > "$DIR/data.jsonl"
            echo "Submissions cleared (previous archived)"
        else
            echo "No submissions to clear"
        fi
        ;;

    help|*)
        head -36 "$0" | tail -34 | sed 's/^# //;s/^#//'
        ;;
esac
