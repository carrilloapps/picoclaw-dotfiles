#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# rag-tool.sh -- Hybrid RAG: BM25 + Semantic (Gemini embeddings)
# =============================================================================
# Combines SQLite FTS5 (BM25 keyword search) with optional Gemini embeddings
# for semantic search. Hybrid mode uses Reciprocal Rank Fusion (RRF) to merge
# both signals. Fully local DB, no vector-DB dependency. Embeddings are free
# via Gemini AI Studio (text-embedding-004, 768 dims).
#
# Usage:
#   ~/bin/rag-tool.sh init                             # Create knowledge DB
#   ~/bin/rag-tool.sh add <doc-id> <file>              # Index + embed
#   ~/bin/rag-tool.sh add-text <doc-id> "<text>"       # Index raw text
#   ~/bin/rag-tool.sh add-dir <dir>                    # Bulk index .md/.txt
#   ~/bin/rag-tool.sh add-url <doc-id> <url>           # Fetch + index URL content
#   ~/bin/rag-tool.sh add-pdf <doc-id> <pdf>           # PDF text extraction + index
#   ~/bin/rag-tool.sh search "<query>" [limit]         # Hybrid (BM25 + semantic)
#   ~/bin/rag-tool.sh search-bm25 "<query>" [limit]    # BM25 only
#   ~/bin/rag-tool.sh search-semantic "<query>" [limit] # Semantic only
#   ~/bin/rag-tool.sh list                             # List docs
#   ~/bin/rag-tool.sh remove <doc-id>                  # Remove
#   ~/bin/rag-tool.sh stats                            # DB stats
#   ~/bin/rag-tool.sh query "<question>" [model]       # Hybrid retrieve + LLM
#   ~/bin/rag-tool.sh reindex                          # Regenerate embeddings
#
# Embeddings: uses GOOGLE_AI_STUDIO_API_KEY from ~/.picoclaw_keys or .env
# Storage: ~/.picoclaw/workspace/knowledge/rag.db (SQLite)
# =============================================================================

set -eu
DB="${HOME}/.picoclaw/workspace/knowledge/rag.db"
CMD="${1:-help}"
mkdir -p "$(dirname "$DB")"

# Load API keys
[ -f "$HOME/.picoclaw_keys" ] && . "$HOME/.picoclaw_keys" 2>/dev/null || true

# Fallback: parse from security.yml
if [ -z "${GOOGLE_AI_STUDIO_API_KEY:-}" ] && [ -f "$HOME/.picoclaw/.security.yml" ]; then
    GOOGLE_AI_STUDIO_API_KEY=$(python3 -c "
import yaml
try:
    d = yaml.safe_load(open('$HOME/.picoclaw/.security.yml'))
    ml = d.get('model_list', {}) or {}
    for k, v in ml.items():
        if 'gemini' in k:
            keys = v.get('api_keys', []) if v else []
            if keys: print(keys[0]); break
except Exception: pass
" 2>/dev/null || echo "")
fi
export GOOGLE_AI_STUDIO_API_KEY="${GOOGLE_AI_STUDIO_API_KEY:-}"

py_helper() {
    local action="$1"; shift
    python3 -c "
import sys, sqlite3, re, os, json, struct, hashlib
import urllib.request

DB = '$DB'
API_KEY = os.environ.get('GOOGLE_AI_STUDIO_API_KEY', '')
EMBED_URL = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-embedding-001:embedContent'
action = '$action'

def ensure():
    con = sqlite3.connect(DB); cur = con.cursor()
    cur.execute(\"CREATE VIRTUAL TABLE IF NOT EXISTS docs USING fts5(doc_id UNINDEXED, chunk_idx UNINDEXED, content, tokenize='porter unicode61')\")
    cur.execute('''CREATE TABLE IF NOT EXISTS meta (
        doc_id TEXT PRIMARY KEY, path TEXT, added_at TEXT, chunks INTEGER, content_hash TEXT)''')
    cur.execute('''CREATE TABLE IF NOT EXISTS embeddings (
        doc_id TEXT, chunk_idx INTEGER, vector BLOB, PRIMARY KEY(doc_id, chunk_idx))''')
    cur.execute('CREATE INDEX IF NOT EXISTS idx_emb_doc ON embeddings(doc_id)')
    con.commit(); return con

def chunk(text, size=500):
    paras = [p.strip() for p in re.split(r'\n\s*\n', text.strip()) if p.strip()]
    out, buf = [], ''
    for p in paras:
        if len(buf) + len(p) < size:
            buf = (buf + '\n\n' + p) if buf else p
        else:
            if buf: out.append(buf)
            buf = p
    if buf: out.append(buf)
    if not out and text.strip(): out = [text.strip()[:5000]]
    return out

def embed(text):
    '''Get 768-dim embedding from Gemini. Returns bytes (float32 packed).'''
    if not API_KEY or not text: return None
    body = json.dumps({
        'model': 'models/gemini-embedding-001',
        'content': {'parts': [{'text': text[:8000]}]}
    }).encode()
    req = urllib.request.Request(
        EMBED_URL + '?key=' + API_KEY,
        data=body, headers={'Content-Type': 'application/json'}
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            data = json.loads(r.read())
            vec = data.get('embedding', {}).get('values') or []
            if vec: return struct.pack(f'{len(vec)}f', *vec)
    except Exception as e:
        print(f'[embed error: {e}]', file=sys.stderr)
    return None

def unembed(blob):
    n = len(blob) // 4
    return list(struct.unpack(f'{n}f', blob))

def cosine(a, b):
    na = sum(x*x for x in a) ** 0.5
    nb = sum(x*x for x in b) ** 0.5
    if na == 0 or nb == 0: return 0.0
    return sum(x*y for x,y in zip(a,b)) / (na * nb)

if action == 'init':
    ensure(); print(f'DB initialized: {DB}')

elif action == 'add':
    doc_id, path = sys.argv[1], sys.argv[2]
    text = sys.stdin.read()
    con = ensure(); cur = con.cursor()
    h = hashlib.sha256(text.encode()).hexdigest()[:16]
    # Check if already indexed
    row = cur.execute('SELECT content_hash FROM meta WHERE doc_id=?', (doc_id,)).fetchone()
    if row and row[0] == h:
        print(f'{doc_id}: unchanged (hash match)'); sys.exit(0)
    cur.execute('DELETE FROM docs WHERE doc_id=?', (doc_id,))
    cur.execute('DELETE FROM meta WHERE doc_id=?', (doc_id,))
    cur.execute('DELETE FROM embeddings WHERE doc_id=?', (doc_id,))
    chunks = chunk(text)
    for i, c in enumerate(chunks):
        cur.execute('INSERT INTO docs(doc_id, chunk_idx, content) VALUES (?, ?, ?)', (doc_id, i, c))
        v = embed(c)
        if v: cur.execute('INSERT INTO embeddings VALUES (?, ?, ?)', (doc_id, i, v))
    cur.execute('INSERT INTO meta VALUES (?, ?, datetime(\"now\"), ?, ?)', (doc_id, path, len(chunks), h))
    con.commit()
    embedded = cur.execute('SELECT COUNT(*) FROM embeddings WHERE doc_id=?', (doc_id,)).fetchone()[0]
    print(f'Indexed {doc_id} ({len(chunks)} chunks, {embedded} with embeddings)')

elif action == 'search-bm25':
    q, limit = sys.argv[1], int(sys.argv[2])
    con = ensure(); cur = con.cursor()
    try:
        cur.execute('SELECT doc_id, chunk_idx, substr(content, 1, 200), rank FROM docs WHERE docs MATCH ? ORDER BY rank LIMIT ?', (q, limit))
        rows = cur.fetchall()
        if not rows: print('No results.')
        for r in rows:
            print(f'[{r[0]} #{r[1]}] score={-r[3]:.3f}')
            print(f'  {r[2]}...')
    except sqlite3.OperationalError as e: print(f'Error: {e}')

elif action == 'search-semantic':
    q, limit = sys.argv[1], int(sys.argv[2])
    con = ensure(); cur = con.cursor()
    qv = embed(q)
    if not qv:
        print('Semantic search unavailable (no API key or empty query)')
        sys.exit(1)
    qvec = unembed(qv)
    results = []
    for row in cur.execute('SELECT e.doc_id, e.chunk_idx, e.vector, substr(d.content, 1, 200) FROM embeddings e JOIN docs d ON d.doc_id=e.doc_id AND d.chunk_idx=e.chunk_idx'):
        score = cosine(qvec, unembed(row[2]))
        results.append((score, row[0], row[1], row[3]))
    results.sort(reverse=True)
    if not results: print('No results (DB empty or no embeddings).')
    for score, doc, idx, preview in results[:limit]:
        print(f'[{doc} #{idx}] cos={score:.3f}')
        print(f'  {preview}...')

elif action == 'search-hybrid':
    q, limit = sys.argv[1], int(sys.argv[2])
    con = ensure(); cur = con.cursor()
    # BM25 results
    bm25 = {}
    try:
        for r_idx, row in enumerate(cur.execute('SELECT doc_id, chunk_idx, substr(content, 1, 200) FROM docs WHERE docs MATCH ? ORDER BY rank LIMIT 20', (q,))):
            bm25[(row[0], row[1])] = (r_idx, row[2])
    except sqlite3.OperationalError: pass
    # Semantic results
    sem = {}
    qv = embed(q)
    if qv:
        qvec = unembed(qv)
        scored = []
        for row in cur.execute('SELECT e.doc_id, e.chunk_idx, e.vector, substr(d.content, 1, 200) FROM embeddings e JOIN docs d ON d.doc_id=e.doc_id AND d.chunk_idx=e.chunk_idx'):
            scored.append((cosine(qvec, unembed(row[2])), row[0], row[1], row[3]))
        scored.sort(reverse=True)
        for r_idx, (_, doc, idx, preview) in enumerate(scored[:20]):
            sem[(doc, idx)] = (r_idx, preview)
    # RRF fusion
    k = 60
    keys = set(bm25.keys()) | set(sem.keys())
    fused = []
    for key in keys:
        score = 0
        if key in bm25: score += 1.0 / (k + bm25[key][0])
        if key in sem: score += 1.0 / (k + sem[key][0])
        preview = (bm25.get(key) or sem.get(key))[1]
        fused.append((score, key[0], key[1], preview))
    fused.sort(reverse=True)
    if not fused: print('No results.')
    for score, doc, idx, preview in fused[:limit]:
        tag = ''
        if (doc, idx) in bm25: tag += 'BM25 '
        if (doc, idx) in sem: tag += 'SEM'
        print(f'[{doc} #{idx}] rrf={score:.4f} [{tag.strip()}]')
        print(f'  {preview}...')

elif action == 'list':
    con = ensure(); cur = con.cursor()
    cur.execute('SELECT doc_id, path, chunks, added_at FROM meta ORDER BY added_at DESC')
    rows = cur.fetchall()
    if not rows: print('No documents.')
    for r in rows:
        embc = cur.execute('SELECT COUNT(*) FROM embeddings WHERE doc_id=?', (r[0],)).fetchone()[0]
        print(f'{r[0]:30s} chunks={r[2]:3d} emb={embc:3d} added={r[3]}')

elif action == 'remove':
    doc_id = sys.argv[1]
    con = ensure(); cur = con.cursor()
    cur.execute('DELETE FROM docs WHERE doc_id=?', (doc_id,))
    cur.execute('DELETE FROM meta WHERE doc_id=?', (doc_id,))
    cur.execute('DELETE FROM embeddings WHERE doc_id=?', (doc_id,))
    con.commit(); print(f'Removed {doc_id}')

elif action == 'stats':
    con = ensure(); cur = con.cursor()
    docs = cur.execute('SELECT COUNT(*) FROM meta').fetchone()[0]
    chunks = cur.execute('SELECT COUNT(*) FROM docs').fetchone()[0]
    emb = cur.execute('SELECT COUNT(*) FROM embeddings').fetchone()[0]
    size = os.path.getsize(DB) / 1024
    print(f'Documents: {docs} | Chunks: {chunks} | Embeddings: {emb} | DB size: {size:.1f} KB')
    print(f'Hybrid search: {\"enabled\" if API_KEY else \"BM25 only (no GOOGLE_AI_STUDIO_API_KEY)\"}')

elif action == 'retrieve':
    q = sys.argv[1]
    con = ensure(); cur = con.cursor()
    # Use hybrid
    bm25 = {}
    try:
        for r_idx, row in enumerate(cur.execute('SELECT doc_id, chunk_idx, content FROM docs WHERE docs MATCH ? ORDER BY rank LIMIT 10', (q,))):
            bm25[(row[0], row[1])] = (r_idx, row[2])
    except sqlite3.OperationalError: pass
    sem = {}
    qv = embed(q)
    if qv:
        qvec = unembed(qv)
        scored = []
        for row in cur.execute('SELECT e.doc_id, e.chunk_idx, e.vector, d.content FROM embeddings e JOIN docs d ON d.doc_id=e.doc_id AND d.chunk_idx=e.chunk_idx'):
            scored.append((cosine(qvec, unembed(row[2])), row[0], row[1], row[3]))
        scored.sort(reverse=True)
        for r_idx, (_, doc, idx, content) in enumerate(scored[:10]):
            sem[(doc, idx)] = (r_idx, content)
    k = 60
    keys = set(bm25.keys()) | set(sem.keys())
    fused = []
    for key in keys:
        score = 0
        if key in bm25: score += 1.0 / (k + bm25[key][0])
        if key in sem: score += 1.0 / (k + sem[key][0])
        content = (bm25.get(key) or sem.get(key))[1]
        fused.append((score, content))
    fused.sort(reverse=True, key=lambda x: x[0])
    print('\n\n---\n\n'.join(f[1] for f in fused[:3]))

elif action == 'reindex':
    con = ensure(); cur = con.cursor()
    count = 0
    for row in cur.execute('SELECT doc_id, chunk_idx, content FROM docs'):
        v = embed(row[2])
        if v:
            cur.execute('INSERT OR REPLACE INTO embeddings VALUES (?, ?, ?)', (row[0], row[1], v))
            count += 1
    con.commit()
    print(f'Reindexed {count} chunks with embeddings')
" "$@"
}

case "$CMD" in
    init)
        py_helper init
        ;;
    add)
        DOC="${2:?}"; FILE="${3:?}"
        cat "$FILE" | py_helper add "$DOC" "$FILE"
        ;;
    add-text)
        DOC="${2:?}"; TEXT="${3:?}"
        printf '%s' "$TEXT" | py_helper add "$DOC" "inline"
        ;;
    add-dir)
        DIR="${2:?}"
        count=0
        while IFS= read -r f; do
            "$0" add "$(basename "$f")" "$f" && count=$((count + 1)) || true
        done < <(find "$DIR" -type f \( -name '*.md' -o -name '*.txt' -o -name '*.rst' \))
        echo "Indexed $count files"
        ;;
    add-url)
        DOC="${2:?}"; URL="${3:?}"
        TEXT=$(curl -sL -A "Mozilla/5.0" "$URL" | python3 -c "
import sys, re
from html.parser import HTMLParser
class T(HTMLParser):
    def __init__(self):
        super().__init__(); self.buf=[]; self.skip=False
    def handle_starttag(self,t,a):
        if t in ('script','style','noscript'): self.skip=True
    def handle_endtag(self,t):
        if t in ('script','style','noscript'): self.skip=False
    def handle_data(self,d):
        if not self.skip and d.strip(): self.buf.append(d.strip())
p=T(); p.feed(sys.stdin.read())
print('\n'.join(p.buf))
")
        printf '%s' "$TEXT" | py_helper add "$DOC" "$URL"
        ;;
    add-pdf)
        DOC="${2:?}"; PDF="${3:?}"
        pdftotext -layout "$PDF" - | py_helper add "$DOC" "$PDF"
        ;;
    search)
        py_helper search-hybrid "${2:?}" "${3:-5}"
        ;;
    search-bm25)
        py_helper search-bm25 "${2:?}" "${3:-5}"
        ;;
    search-semantic)
        py_helper search-semantic "${2:?}" "${3:-5}"
        ;;
    list)       py_helper list ;;
    remove)     py_helper remove "${2:?}" ;;
    stats)      py_helper stats ;;
    reindex)    py_helper reindex ;;
    query)
        Q="${2:?}"; MODEL="${3:-}"
        CONTEXT=$(py_helper retrieve "$Q" 2>/dev/null)
        if [ -z "$CONTEXT" ]; then
            echo "No context found. Asking without RAG..."
            echo "$Q" | SSL_CERT_FILE=/data/data/com.termux/files/usr/etc/tls/cert.pem "$HOME/picoclaw.bin" agent 2>&1 | tail -10
        else
            PROMPT="Answer using only this context. If insufficient, say so.

CONTEXT:
$CONTEXT

QUESTION: $Q"
            ARGS=""; [ -n "$MODEL" ] && ARGS="--model $MODEL"
            echo "$PROMPT" | SSL_CERT_FILE=/data/data/com.termux/files/usr/etc/tls/cert.pem "$HOME/picoclaw.bin" agent $ARGS 2>&1 | tail -15
        fi
        ;;
    help|*)
        head -26 "$0" | tail -24 | sed 's/^# //;s/^#//'
        ;;
esac
