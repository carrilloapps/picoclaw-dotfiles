#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# form-handler.sh -- Universal form submission handler
# =============================================================================
# Used by webhook-manage.sh create-form. Handles GET (serve HTML) and POST
# (parse, store, notify via RAG + Android + Telegram).
#
# Invoked by webhook-server.py with:
#   stdin   = request body
#   env     = REQUEST_METHOD, REMOTE_ADDR, REQUEST_PATH, CONTENT_TYPE
#   argv[0] = path to this script (so we can find the form's directory via symlink chain)
#
# The handler is installed as a symlink in each form's directory:
#   ~/.picoclaw/webhooks/<name>/handler.sh -> ~/bin/form-handler.sh
# so there's ONE copy of the logic, updates apply to all forms at once.
# =============================================================================

set -eu
# Resolve the real form directory (symlink's dirname)
SELF_PATH="${BASH_SOURCE[0]:-$0}"
if [ -L "$SELF_PATH" ]; then
    # handler.sh is a symlink inside the form's dir
    DIR="$(dirname "$SELF_PATH")"
else
    # Fallback: use $REQUEST_PATH to find the dir
    NAME="$(basename "${REQUEST_PATH:-/c/unknown}")"
    DIR="$HOME/.picoclaw/webhooks/$NAME"
fi

# Get form name from meta.json (or derive from directory name)
NAME="$(basename "$DIR")"
METHOD="${REQUEST_METHOD:-GET}"

if [ "$METHOD" = "GET" ]; then
    if [ -f "$DIR/form.html" ]; then
        cat "$DIR/form.html"
    else
        echo "No form HTML present"
    fi
    exit 0
fi

# POST: capture body first (heredoc would steal stdin from Python)
BODY="$(cat)"

# Write Python script to a temp file so Python's stdin stays with the body
TMP_PY=$(mktemp --suffix=.py)
cat > "$TMP_PY" <<'PYEOF'
import sys, json, os, subprocess, urllib.parse, tempfile
from datetime import datetime

name, dir_ = sys.argv[1], sys.argv[2]
body = os.environ.get('HANDLER_BODY', '')

entry = {'ts': datetime.now().isoformat(), 'ip': os.environ.get('REMOTE_ADDR', '')}
try:
    parsed = json.loads(body)
    if isinstance(parsed, dict):
        entry.update(parsed)
    else:
        entry['payload'] = parsed
except Exception:
    for k, v in urllib.parse.parse_qsl(body):
        entry[k] = v

# 1. Store as JSONL
data_file = os.path.join(dir_, 'data.jsonl')
with open(data_file, 'a') as f:
    f.write(json.dumps(entry, ensure_ascii=False) + '\n')

# 2. Index into RAG for agent memory
user_fields = {k: v for k, v in entry.items() if k not in ('ts', 'ip')}
doc_id = f'form:{name}:' + datetime.now().strftime('%Y%m%d-%H%M%S')
lines = [f'Form submission to /c/{name}']
lines.append(f'Timestamp: {entry["ts"]}')
lines.append(f'From IP: {entry.get("ip", "?")}')
lines.append('')
for k, v in user_fields.items():
    lines.append(f'{k}: {v}')
content = '\n'.join(lines)

try:
    with tempfile.NamedTemporaryFile('w', delete=False, suffix='.txt') as tf:
        tf.write(content)
        tmp = tf.name
    subprocess.run([os.path.expanduser('~/bin/rag-tool.sh'), 'add', doc_id, tmp],
                   timeout=30, capture_output=True)
    os.unlink(tmp)
except Exception as e:
    pass

# 3. Android notification
summary_parts = [f'{k}: {v}' for k, v in user_fields.items()]
summary = ' | '.join(str(p)[:80] for p in summary_parts)[:300]
try:
    subprocess.run(['termux-notification',
                    '--title', f'\ud83d\udce9 Form: {name}',
                    '--content', summary or 'New submission',
                    '--priority', 'default',
                    '--id', f'form-{name}'],
                   timeout=5, capture_output=True)
except Exception:
    pass

# 4. Telegram notification
try:
    import urllib.request
    import yaml
    sec = yaml.safe_load(open(os.path.expanduser('~/.picoclaw/.security.yml'))) or {}
    token = sec.get('channels', {}).get('telegram', {}).get('token', '')
    if isinstance(token, str):
        token = token.strip('"').strip()
    cfg = json.load(open(os.path.expanduser('~/.picoclaw/config.json')))
    owners = cfg.get('channels', {}).get('telegram', {}).get('allow_from', [])
    if token and owners:
        owner = owners[0]
        msg_lines = [f'\ud83d\udce9 <b>Nueva submission a /c/{name}</b>', '']
        for k, v in user_fields.items():
            safe_v = str(v)[:200].replace('<', '&lt;').replace('>', '&gt;')
            msg_lines.append(f'<b>{k}:</b> {safe_v}')
        msg = '\n'.join(msg_lines)
        url = f'https://api.telegram.org/bot{token}/sendMessage'
        data = json.dumps({'chat_id': owner, 'text': msg, 'parse_mode': 'HTML'}).encode()
        req = urllib.request.Request(url, data=data, headers={'Content-Type': 'application/json'})
        urllib.request.urlopen(req, timeout=10)
except Exception as e:
    pass

print(json.dumps({'status': 'received', 'indexed_as': doc_id, 'ok': True}))
PYEOF

HANDLER_BODY="$BODY" python3 "$TMP_PY" "$NAME" "$DIR"
rm -f "$TMP_PY"
