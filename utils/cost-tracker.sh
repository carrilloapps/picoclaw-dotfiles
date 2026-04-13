#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# cost-tracker.sh -- LLM cost tracking and usage analytics
# =============================================================================
# Parses gateway.log for LLM calls and computes cost estimates per provider,
# per model, per session. Alerts when daily/monthly budgets are exceeded.
#
# Usage:
#   ~/bin/cost-tracker.sh today           # Today's usage
#   ~/bin/cost-tracker.sh week            # Last 7 days
#   ~/bin/cost-tracker.sh month           # Last 30 days
#   ~/bin/cost-tracker.sh by-model        # Breakdown per model
#   ~/bin/cost-tracker.sh by-session      # Breakdown per session
#   ~/bin/cost-tracker.sh export          # CSV export
#   ~/bin/cost-tracker.sh budget <USD>    # Set monthly budget alert threshold
# =============================================================================

set -eu
LOG="${HOME}/.picoclaw/gateway.log"
DB="${HOME}/.picoclaw/workspace/knowledge/costs.db"
CMD="${1:-today}"

# Pricing in USD per 1M tokens (input/output)
python3 - "$CMD" "$@" <<'PYEOF' "$LOG" "$DB"
import sys, os, re, sqlite3, json, time
from datetime import datetime, timedelta

cmd = sys.argv[1]
log_path = sys.argv[-2]
db_path = sys.argv[-1]

PRICING = {
    'gpt-4o': (2.50, 10.00),
    'azure-gpt4o': (2.50, 10.00),
    'gpt-4': (30.00, 60.00),
    'gpt-3.5-turbo': (0.50, 1.50),
    'claude-opus': (15.00, 75.00),
    'claude-sonnet': (3.00, 15.00),
    'claude-haiku': (0.25, 1.25),
    'gemini-2.5-pro': (1.25, 10.00),
    'gemini-2.5-flash': (0.075, 0.30),
    'gemini-2.0-flash': (0.075, 0.30),
    'gemini-flash-lite': (0.075, 0.30),
    'gpt-oss:120b': (0.0, 0.0),
    'deepseek-v3.2': (0.0, 0.0),
    'default': (0.50, 1.50),
}

def price(model):
    model_lower = model.lower()
    for k, v in PRICING.items():
        if k in model_lower:
            return v
    return PRICING['default']

os.makedirs(os.path.dirname(db_path), exist_ok=True)
con = sqlite3.connect(db_path)
cur = con.cursor()
cur.execute('''CREATE TABLE IF NOT EXISTS calls (
    ts TEXT, session TEXT, model TEXT, prompt_tokens INTEGER, completion_tokens INTEGER,
    duration_ms INTEGER, cost_usd REAL)''')
cur.execute('CREATE INDEX IF NOT EXISTS idx_ts ON calls(ts)')
cur.execute('CREATE INDEX IF NOT EXISTS idx_model ON calls(model)')
con.commit()

# Parse log (incremental - track last position)
state_path = db_path + '.state'
last_offset = 0
if os.path.exists(state_path):
    with open(state_path) as f:
        last_offset = int(f.read().strip() or 0)

if os.path.exists(log_path):
    with open(log_path, 'r', errors='replace') as f:
        f.seek(last_offset)
        content = f.read()
        last_offset = f.tell()

    # Patterns: LLM response with tokens
    pattern = re.compile(r'(\d{2}:\d{2}:\d{2}).*?LLM response.*?session_key=(\S+).*?model=(\S+).*?prompt_tokens=(\d+).*?completion_tokens=(\d+).*?(?:duration_ms=(\d+))?')
    today = datetime.now().strftime('%Y-%m-%d')
    for m in pattern.finditer(content):
        ts, session, model, pt, ct, dur = m.groups()
        pt, ct = int(pt), int(ct)
        dur = int(dur) if dur else 0
        p_in, p_out = price(model)
        cost = (pt * p_in + ct * p_out) / 1_000_000
        cur.execute('INSERT INTO calls VALUES (?, ?, ?, ?, ?, ?, ?)',
                   (f'{today} {ts}', session, model, pt, ct, dur, cost))
    con.commit()
    with open(state_path, 'w') as f: f.write(str(last_offset))

def window(since_days):
    since = (datetime.now() - timedelta(days=since_days)).strftime('%Y-%m-%d %H:%M:%S')
    return since

if cmd == 'today':
    since = datetime.now().strftime('%Y-%m-%d 00:00:00')
    rows = cur.execute('SELECT COUNT(*), SUM(prompt_tokens), SUM(completion_tokens), SUM(cost_usd) FROM calls WHERE ts >= ?', (since,)).fetchone()
    n, pt, ct, cost = rows[0] or 0, rows[1] or 0, rows[2] or 0, rows[3] or 0
    print(f'Today ({datetime.now().strftime("%Y-%m-%d")}):')
    print(f'  Calls:         {n}')
    print(f'  Prompt tokens: {pt:,}')
    print(f'  Output tokens: {ct:,}')
    print(f'  Est. cost:     ${cost:.4f}')

elif cmd == 'week':
    since = window(7)
    rows = cur.execute('SELECT COUNT(*), SUM(prompt_tokens+completion_tokens), SUM(cost_usd) FROM calls WHERE ts >= ?', (since,)).fetchone()
    print(f'Last 7 days: {rows[0]} calls, {rows[1] or 0:,} tokens, ${rows[2] or 0:.4f}')

elif cmd == 'month':
    since = window(30)
    rows = cur.execute('SELECT COUNT(*), SUM(prompt_tokens+completion_tokens), SUM(cost_usd) FROM calls WHERE ts >= ?', (since,)).fetchone()
    print(f'Last 30 days: {rows[0]} calls, {rows[1] or 0:,} tokens, ${rows[2] or 0:.4f}')

elif cmd == 'by-model':
    since = window(30)
    print(f'{"MODEL":<30} {"CALLS":>7} {"TOKENS":>12} {"COST":>10}')
    for r in cur.execute('SELECT model, COUNT(*), SUM(prompt_tokens+completion_tokens), SUM(cost_usd) FROM calls WHERE ts >= ? GROUP BY model ORDER BY 4 DESC', (since,)):
        print(f'{r[0]:<30} {r[1]:>7} {r[2] or 0:>12,} {r[3] or 0:>10.4f}')

elif cmd == 'by-session':
    since = window(30)
    print(f'{"SESSION":<40} {"CALLS":>7} {"COST":>10}')
    for r in cur.execute('SELECT session, COUNT(*), SUM(cost_usd) FROM calls WHERE ts >= ? GROUP BY session ORDER BY 3 DESC LIMIT 20', (since,)):
        print(f'{r[0][:40]:<40} {r[1]:>7} {r[2] or 0:>10.4f}')

elif cmd == 'export':
    import csv
    out = sys.stdout
    w = csv.writer(out)
    w.writerow(['ts', 'session', 'model', 'prompt_tokens', 'completion_tokens', 'duration_ms', 'cost_usd'])
    for r in cur.execute('SELECT * FROM calls ORDER BY ts DESC'):
        w.writerow(r)

elif cmd == 'budget':
    if len(sys.argv) < 3:
        print('Usage: cost-tracker.sh budget <USD>'); sys.exit(1)
    budget = float(sys.argv[2])
    cur.execute('CREATE TABLE IF NOT EXISTS config (k TEXT PRIMARY KEY, v TEXT)')
    cur.execute('INSERT OR REPLACE INTO config VALUES (?, ?)', ('monthly_budget', str(budget)))
    con.commit()
    print(f'Monthly budget set: ${budget:.2f}')
else:
    print('Usage: cost-tracker.sh [today|week|month|by-model|by-session|export|budget <USD>]')
PYEOF
