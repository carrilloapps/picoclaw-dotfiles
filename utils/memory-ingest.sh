#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# memory-ingest.sh -- Stream conversations into RAG (central memory)
# =============================================================================
# Parses gateway.log and auto-indexes every user message and agent response
# into the RAG DB. This makes context persistent ACROSS LLM switches —
# Gemini, Azure, Ollama all share the same long-term memory.
#
# Runs via cron every minute. Uses incremental offset tracking to avoid
# reprocessing. Indexes with session/channel/role metadata.
#
# Usage:
#   ~/bin/memory-ingest.sh             # Process new log entries
#   ~/bin/memory-ingest.sh full        # Re-process everything from start
#   ~/bin/memory-ingest.sh stats       # Show ingestion stats
#   ~/bin/memory-ingest.sh search <q>  # Search conversation memory
# =============================================================================

set -eu
GATEWAY_LOG="${HOME}/.picoclaw/gateway.log"
DB="${HOME}/.picoclaw/workspace/knowledge/rag.db"
STATE_FILE="${HOME}/.picoclaw/workspace/knowledge/memory-ingest.offset"
CMD="${1:-ingest}"

mkdir -p "$(dirname "$STATE_FILE")"

case "$CMD" in
    full)
        echo "0" > "$STATE_FILE"
        exec "$0" ingest
        ;;
    stats)
        python3 -c "
import sqlite3, os
con = sqlite3.connect('$DB')
try:
    n = con.execute(\"SELECT COUNT(*) FROM docs WHERE doc_id LIKE 'mem:%'\").fetchone()[0]
    sess = con.execute(\"SELECT COUNT(DISTINCT doc_id) FROM docs WHERE doc_id LIKE 'mem:%'\").fetchone()[0]
    print(f'Memory chunks: {n}')
    print(f'Sessions:      {sess}')
except Exception as e: print(f'Error: {e}')
"
        [ -f "$STATE_FILE" ] && echo "Offset: $(cat $STATE_FILE)" || echo "Offset: 0"
        ;;
    search)
        Q="${2:?Usage: memory-ingest.sh search <query>}"
        LIMIT="${3:-5}"
        python3 -c "
import sqlite3
con = sqlite3.connect('$DB')
try:
    for r in con.execute(\"SELECT doc_id, chunk_idx, substr(content, 1, 250) FROM docs WHERE docs MATCH ? AND doc_id LIKE 'mem:%' ORDER BY rank LIMIT ?\", ('$Q', $LIMIT)):
        print(f'[{r[0]}]')
        print(f'  {r[2]}...\n')
except Exception as e: print(f'Error: {e}')
"
        ;;
    ingest|*)
        [ -f "$GATEWAY_LOG" ] || { echo "No gateway.log yet"; exit 0; }

        OFFSET=0
        [ -f "$STATE_FILE" ] && OFFSET=$(cat "$STATE_FILE" 2>/dev/null || echo 0)

        python3 - "$GATEWAY_LOG" "$DB" "$OFFSET" "$STATE_FILE" <<'PYEOF'
import sys, re, sqlite3, os, json, struct, urllib.request
from datetime import datetime

log_path, db_path, offset_str, state_path = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
offset = int(offset_str or 0)

# Load Google API key for embeddings
api_key = os.environ.get('GOOGLE_AI_STUDIO_API_KEY', '')
if not api_key:
    try:
        keys = open(os.path.expanduser('~/.picoclaw_keys')).read()
        for line in keys.splitlines():
            if 'GOOGLE' in line and '=' in line:
                api_key = line.split('=', 1)[1].strip().strip('"')
                break
    except Exception:
        pass
if not api_key:
    try:
        import yaml
        d = yaml.safe_load(open(os.path.expanduser('~/.picoclaw/.security.yml')))
        ml = d.get('model_list', {}) or {}
        for k, v in ml.items():
            if 'gemini' in k.lower():
                keys = v.get('api_keys', []) if v else []
                if keys: api_key = keys[0]; break
    except Exception: pass

EMBED_URL = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-embedding-001:embedContent'

def embed(text):
    if not api_key or not text: return None
    body = json.dumps({'model': 'models/gemini-embedding-001', 'content': {'parts': [{'text': text[:8000]}]}}).encode()
    req = urllib.request.Request(EMBED_URL + '?key=' + api_key, data=body, headers={'Content-Type': 'application/json'})
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            vec = json.loads(r.read()).get('embedding', {}).get('values') or []
            if vec: return struct.pack(f'{len(vec)}f', *vec)
    except Exception: pass
    return None

# Read new log content
file_size = os.path.getsize(log_path)
if offset > file_size:
    offset = 0  # Log was rotated

with open(log_path, 'r', errors='replace') as f:
    f.seek(offset)
    content = f.read()
    new_offset = f.tell()

# Strip ANSI codes
content = re.sub(r'\x1b\[[0-9;]*m', '', content)

# Setup DB
con = sqlite3.connect(db_path)
cur = con.cursor()
cur.execute("CREATE VIRTUAL TABLE IF NOT EXISTS docs USING fts5(doc_id UNINDEXED, chunk_idx UNINDEXED, content, tokenize='porter unicode61')")
cur.execute("CREATE TABLE IF NOT EXISTS meta (doc_id TEXT PRIMARY KEY, path TEXT, added_at TEXT, chunks INTEGER, content_hash TEXT)")
cur.execute("CREATE TABLE IF NOT EXISTS embeddings (doc_id TEXT, chunk_idx INTEGER, vector BLOB, PRIMARY KEY(doc_id, chunk_idx))")

# Extract user messages (from channels) and agent responses
# Pattern: user messages appear as "inbound" events, responses as "Response:"
ingested = 0
# Session-keyed memory: one doc per session, append chunks
sessions = {}  # session_key -> list of (role, text)

# User inbound messages
for m in re.finditer(r'Inbound.*?session_key=(\S+).*?text[^=]*=["\']?([^"\']{3,300})["\']?', content):
    sk, text = m.group(1), m.group(2).strip()
    if text and len(text) > 3:
        sessions.setdefault(sk, []).append(('user', text))

# Agent responses with final text
for m in re.finditer(r'Response:\s+(.+?)\s+agent_id=\S+.*?session_key=(\S+)', content):
    text, sk = m.group(1).strip(), m.group(2)
    if text and len(text) > 3 and not text.startswith('[') and 'error' not in text.lower()[:20]:
        sessions.setdefault(sk, []).append(('assistant', text[:500]))

# Index into RAG as mem:<session>:<timestamp> documents
now = datetime.now().strftime('%Y%m%d-%H%M%S')
for sk, turns in sessions.items():
    if not turns: continue
    doc_id = f'mem:{sk}:{now}:{ingested}'
    combined = '\n\n'.join(f'[{role}] {text}' for role, text in turns)
    cur.execute('DELETE FROM docs WHERE doc_id=?', (doc_id,))
    cur.execute('INSERT INTO docs(doc_id, chunk_idx, content) VALUES (?, 0, ?)', (doc_id, combined))
    v = embed(combined)
    if v:
        cur.execute('DELETE FROM embeddings WHERE doc_id=?', (doc_id,))
        cur.execute('INSERT INTO embeddings VALUES (?, 0, ?)', (doc_id, v))
    cur.execute('INSERT OR REPLACE INTO meta VALUES (?, ?, datetime("now"), 1, ?)',
                (doc_id, f'memory:{sk}', str(hash(combined) % (10**16))))
    ingested += 1

con.commit()

# Save offset
with open(state_path, 'w') as f:
    f.write(str(new_offset))

print(f'Ingested {ingested} memory chunks from {len(content)} bytes (offset: {offset} -> {new_offset})')
PYEOF
        ;;
esac
