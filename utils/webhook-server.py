#!/data/data/com.termux/files/usr/bin/env python3
# =============================================================================
# webhook-server.py -- Hardened HTTP webhook receiver (v3)
# =============================================================================
# Flask server that exposes PicoClaw endpoints and user-defined routes. Sized
# for a mid-range Android phone (Snapdragon 732G / 6 GB RAM): tight caps on
# body size, handler execution time, and per-IP/per-route/global request rate.
#
# Security layers (in check order):
#   1. Honeypot / bot-trap --------- instant 444 + long ban for known-bad paths
#   2. IP ban list ---------------- 403 for IPs under cooldown (sliding window)
#   3. IP allowlist --------------- optional, env: WEBHOOK_IP_ALLOW
#   4. Global rate limit ---------- protects against amplified floods
#   5. Per-IP rate limit ---------- WEBHOOK_RATE_PER_IP (default 60/min)
#   6. Per-route rate limit ------- WEBHOOK_RATE_PER_ROUTE (default 30/min)
#   7. Content-Length cap --------- WEBHOOK_MAX_BODY (default 1 MiB)
#   8. Cloudflare-Access JWT ------ CF_ACCESS_AUD + CF_ACCESS_TEAM
#   9. Bearer / HMAC / provider --- per-endpoint token, HMAC-SHA256, CF JWT
#   10. Auto-ban on auth failures -- N failed 401/403 in M minutes → ban
#   11. Strict method enforcement -- meta.json methods list
#   12. Handler execution timeout -- bounded subprocess (default 30 s)
#   13. Path-name validation ------ strict [a-z0-9][a-z0-9_-]{0,62} regex
#   14. Hardening response headers  X-Content-Type-Options, Referrer-Policy, ...
#
# URL shape:
#   /                  public, minimal ({"status":"ok"}) — no fingerprinting
#   /health            public, minimal ({"status":"ok"})
#   /info              bearer-gated, fail-closed; full operational state
#   /metrics           bearer-gated, fail-closed; prometheus dump
#   /c/<name>          user-defined routes/forms (short prefix, /custom/ is deprecated alias)
#   /c (list)          bearer-gated, fail-closed; list of custom routes
#   /hook/<name>       agent-dispatched generic webhook (Bearer + HMAC)
#   /hook/github/<ev>  GitHub with X-Hub-Signature-256
#   /hook/gitlab/<ev>  GitLab with X-Gitlab-Token
#   /notify            free-form text → agent
#
# Auth modes:
#   check_bearer()   — soft: returns True when WEBHOOK_TOKEN is unset (dev mode).
#                      Used by ingest endpoints (/notify, /hook/*, /c/<name>).
#   require_bearer() — fail-closed: returns False when WEBHOOK_TOKEN is unset.
#                      Used by operator endpoints (/info, /metrics, /c list) so
#                      a token-less deployment cannot leak server internals.
#
# Environment tuning:
#   PORT=18791
#   WEBHOOK_TOKEN=<secret-for-bearer>
#   WEBHOOK_HMAC_SECRET=<secret-for-generic-hmac>
#   GITHUB_WEBHOOK_SECRET=<secret>
#   GITLAB_WEBHOOK_TOKEN=<token>
#   CF_ACCESS_AUD=<cf-access-aud>       CF_ACCESS_TEAM=<team>
#   WEBHOOK_IP_ALLOW=1.2.3.4,5.6.7.8    (comma-sep; empty = all)
#   WEBHOOK_RATE_PER_IP=60              requests/min per IP
#   WEBHOOK_RATE_PER_ROUTE=30           requests/min per (IP,route)
#   WEBHOOK_RATE_GLOBAL=300             requests/min total
#   WEBHOOK_BURST_PER_IP=15             max requests in any 10-second window per IP
#   WEBHOOK_MAX_BODY=1048576            bytes, hard cap
#   WEBHOOK_HANDLER_TIMEOUT=30          seconds, subprocess hard timeout
#   WEBHOOK_AUTH_FAIL_THRESHOLD=10      auth failures before auto-ban
#   WEBHOOK_BAN_MINUTES=60              ban duration
#   WEBHOOK_TRUST_PROXY=1               read X-Forwarded-For (set only if behind CF)
# =============================================================================

import base64
import hashlib
import hmac
import json
import os
import re
import subprocess
import sys
import threading
import time
from collections import defaultdict, deque
from datetime import datetime, timezone

try:
    from flask import Flask, request, jsonify, abort, Response, redirect
except ImportError:
    print("Flask not installed. Run: pip install flask")
    sys.exit(1)

# ----- Config -----------------------------------------------------------------
PORT = int(os.environ.get('PORT', 18791))
HOME = os.path.expanduser('~')
TOKEN = os.environ.get('WEBHOOK_TOKEN', '')
HMAC_SECRET = os.environ.get('WEBHOOK_HMAC_SECRET', '').encode()
GITHUB_SECRET = os.environ.get('GITHUB_WEBHOOK_SECRET', '').encode()
GITLAB_TOKEN = os.environ.get('GITLAB_WEBHOOK_TOKEN', '')
CF_ACCESS_AUD = os.environ.get('CF_ACCESS_AUD', '')
CF_ACCESS_TEAM = os.environ.get('CF_ACCESS_TEAM', '')
IP_ALLOWLIST = [i.strip() for i in os.environ.get('WEBHOOK_IP_ALLOW', '').split(',') if i.strip()]
RATE_PER_IP = int(os.environ.get('WEBHOOK_RATE_PER_IP', 60))
RATE_PER_ROUTE = int(os.environ.get('WEBHOOK_RATE_PER_ROUTE', 30))
RATE_GLOBAL = int(os.environ.get('WEBHOOK_RATE_GLOBAL', 300))
BURST_PER_IP = int(os.environ.get('WEBHOOK_BURST_PER_IP', 15))
MAX_BODY = int(os.environ.get('WEBHOOK_MAX_BODY', 1024 * 1024))  # 1 MiB
HANDLER_TIMEOUT = int(os.environ.get('WEBHOOK_HANDLER_TIMEOUT', 30))
AUTH_FAIL_THRESHOLD = int(os.environ.get('WEBHOOK_AUTH_FAIL_THRESHOLD', 10))
BAN_MINUTES = int(os.environ.get('WEBHOOK_BAN_MINUTES', 60))
TRUST_PROXY = os.environ.get('WEBHOOK_TRUST_PROXY', '').lower() in ('1', 'true', 'yes')

PICOCLAW = f'{HOME}/picoclaw.bin'
SSL_CERT = '/data/data/com.termux/files/usr/etc/tls/cert.pem'
LOG = f'{HOME}/webhook.log'
AUDIT_LOG = f'{HOME}/webhook-audit.log'

# Strict route name: lowercase, digits, _-, 1..63 chars, cannot start with -
ROUTE_NAME_RE = re.compile(r'^[a-z0-9][a-z0-9_-]{0,62}$')

# Well-known scanner/attack paths — any hit = instant 444 + long ban
HONEYPOT_PATHS = {
    '/.env', '/.env.local', '/.env.production', '/.git/config', '/.git/HEAD',
    '/wp-admin', '/wp-login.php', '/wp-config.php', '/wordpress',
    '/phpmyadmin', '/phpMyAdmin', '/pma', '/admin.php', '/administrator',
    '/xmlrpc.php', '/.aws/credentials', '/config.yml', '/config/database.yml',
    '/server-status', '/.DS_Store', '/.htaccess', '/.htpasswd',
    '/actuator', '/actuator/env', '/actuator/health', '/actuator/heapdump',
    '/jenkins', '/manager/html', '/solr', '/druid', '/eureka',
    '/api/v1/pods', '/console', '/swagger.json',
}
HONEYPOT_PREFIXES = ('/cgi-bin/', '/vendor/', '/.aws/', '/.ssh/', '/boaform/')

# ----- Flask app --------------------------------------------------------------
app = Flask(__name__)
app.config['MAX_CONTENT_LENGTH'] = MAX_BODY

# ----- State (thread-safe enough for Werkzeug dev server w/ GIL) -------------
_lock = threading.Lock()
request_times = defaultdict(deque)           # ip -> deque of ts
route_times = defaultdict(deque)              # (ip,route) -> deque of ts
global_times = deque()                        # deque of ts
burst_times = defaultdict(deque)              # ip -> deque of ts (10s window)
auth_failures = defaultdict(deque)            # ip -> deque of failure ts
banned = {}                                   # ip -> until_ts
metrics = defaultdict(int)


def client_ip():
    if TRUST_PROXY:
        xff = request.headers.get('X-Forwarded-For', '')
        if xff:
            return xff.split(',')[0].strip()
        real = request.headers.get('CF-Connecting-IP', '')
        if real:
            return real
    return request.remote_addr or '0.0.0.0'


def audit(event, detail=None):
    line = json.dumps({
        'ts': datetime.now(timezone.utc).isoformat(),
        'event': event,
        'ip': (client_ip() if request else None),
        'path': (request.path if request else None),
        'detail': detail or {},
    }, ensure_ascii=False)
    try:
        with open(AUDIT_LOG, 'a') as f:
            f.write(line + '\n')
    except Exception:
        pass


def log(msg):
    try:
        with open(LOG, 'a') as f:
            f.write(f"[{datetime.now().isoformat()}] {msg}\n")
    except Exception:
        pass


# ----- Rate limiting / ban management ----------------------------------------
def _prune(q, window, now):
    while q and q[0] < now - window:
        q.popleft()


def check_rate():
    """Return (ok, reason, retry_after_seconds)."""
    ip = client_ip()
    now = time.time()
    with _lock:
        # Ban check
        until = banned.get(ip)
        if until:
            if until > now:
                return False, 'banned', int(until - now)
            del banned[ip]

        # Global
        _prune(global_times, 60, now)
        if len(global_times) >= RATE_GLOBAL:
            return False, 'global_rate', 30
        # Per-IP
        q_ip = request_times[ip]
        _prune(q_ip, 60, now)
        if len(q_ip) >= RATE_PER_IP:
            return False, 'ip_rate', 30
        # Burst (10s)
        q_burst = burst_times[ip]
        _prune(q_burst, 10, now)
        if len(q_burst) >= BURST_PER_IP:
            return False, 'burst', 10

        # Accept: record
        global_times.append(now)
        q_ip.append(now)
        q_burst.append(now)
    return True, None, 0


def check_route_rate(name):
    ip = client_ip()
    now = time.time()
    with _lock:
        key = (ip, name)
        q = route_times[key]
        _prune(q, 60, now)
        if len(q) >= RATE_PER_ROUTE:
            return False
        q.append(now)
    return True


def record_auth_failure():
    ip = client_ip()
    now = time.time()
    with _lock:
        q = auth_failures[ip]
        _prune(q, 300, now)  # 5-minute window
        q.append(now)
        if len(q) >= AUTH_FAIL_THRESHOLD:
            banned[ip] = now + BAN_MINUTES * 60
            metrics['auto_banned'] += 1
            audit('auto_banned', {'ip': ip, 'minutes': BAN_MINUTES})


def ban_ip(ip, minutes=None):
    minutes = minutes or BAN_MINUTES
    with _lock:
        banned[ip] = time.time() + minutes * 60


# ----- Security checks -------------------------------------------------------
def check_ip_allowlist():
    if not IP_ALLOWLIST:
        return True
    return client_ip() in IP_ALLOWLIST


def check_bearer():
    """Soft bearer: skipped if no token is configured (dev mode)."""
    if not TOKEN:
        return True
    auth = request.headers.get('Authorization', '')
    return hmac.compare_digest(auth, f'Bearer {TOKEN}')


def require_bearer():
    """Strict bearer: ALWAYS requires a match, even if TOKEN is unset.
    Used for operator-only endpoints that expose server internals
    (/info, /metrics, /c list). Fails closed: no token configured
    means the endpoint is disabled."""
    if not TOKEN:
        return False
    auth = request.headers.get('Authorization', '')
    return hmac.compare_digest(auth, f'Bearer {TOKEN}')


def check_hmac(secret, header_name='X-Signature-256'):
    sig = request.headers.get(header_name, '')
    if not sig or not secret:
        return False
    body = request.get_data(cache=True)  # cache so handler can also read
    if sig.startswith('sha256='):
        sig = sig[7:]
    expected = hmac.new(secret, body, hashlib.sha256).hexdigest()
    return hmac.compare_digest(expected, sig)


def check_cf_access():
    if not CF_ACCESS_AUD or not CF_ACCESS_TEAM:
        return True
    jwt_token = request.headers.get('Cf-Access-Jwt-Assertion', '')
    if not jwt_token:
        return False
    try:
        parts = jwt_token.split('.')
        if len(parts) != 3:
            return False
        payload = json.loads(base64.urlsafe_b64decode(parts[1] + '==='))
        return CF_ACCESS_AUD in payload.get('aud', [])
    except Exception:
        return False


def valid_route_name(name):
    return bool(ROUTE_NAME_RE.match(name or ''))


def pre_checks():
    """Global pre-request checks. Aborts with proper code on failure."""
    ok, reason, retry = check_rate()
    if not ok:
        audit('rate_' + reason, {'retry': retry})
        metrics['rate_' + reason] += 1
        resp = jsonify({'error': 'rate_limited', 'reason': reason, 'retry_after': retry})
        resp.headers['Retry-After'] = str(retry)
        return resp, 429
    if not check_ip_allowlist():
        audit('denied_ip_allowlist')
        record_auth_failure()
        abort(403)
    if not check_cf_access():
        audit('denied_cf_access')
        record_auth_failure()
        abort(401)
    return None


# ----- Agent bridge ----------------------------------------------------------
def send_to_agent(prompt, session='webhook', timeout=120):
    env = os.environ.copy()
    env['SSL_CERT_FILE'] = SSL_CERT
    try:
        proc = subprocess.run(
            [PICOCLAW, 'agent', '-s', f'cli:{session}'],
            input=prompt, capture_output=True, text=True, timeout=timeout, env=env,
        )
        metrics['agent_calls'] += 1
        return proc.stdout
    except subprocess.TimeoutExpired:
        metrics['agent_timeouts'] += 1
        raise


# ----- Hooks: global before/after --------------------------------------------
@app.before_request
def _before():
    metrics['requests_total'] += 1
    path = request.path or '/'

    # 1. Honeypot bot trap (before anything else)
    if path in HONEYPOT_PATHS or any(path.startswith(p) for p in HONEYPOT_PREFIXES):
        ip = client_ip()
        audit('honeypot', {'ip': ip, 'ua': request.headers.get('User-Agent', '')[:120]})
        metrics['honeypot_hits'] += 1
        ban_ip(ip, minutes=BAN_MINUTES * 4)  # long ban
        # 444 = "connection closed without response" (nginx-style); Flask uses 444 body
        return Response(status=444)

    # 2. Content-Length cap (Flask enforces via MAX_CONTENT_LENGTH, but reply fast)
    cl = request.content_length
    if cl is not None and cl > MAX_BODY:
        audit('body_too_large', {'size': cl})
        metrics['body_too_large'] += 1
        return jsonify({'error': 'payload_too_large', 'max': MAX_BODY}), 413


@app.after_request
def _after(resp):
    # Hardening headers on every response
    resp.headers['X-Content-Type-Options'] = 'nosniff'
    resp.headers['X-Frame-Options'] = 'DENY'
    resp.headers['Referrer-Policy'] = 'no-referrer'
    resp.headers['Permissions-Policy'] = 'camera=(), microphone=(), geolocation=(), payment=()'
    resp.headers['Cross-Origin-Opener-Policy'] = 'same-origin'
    # No CORS by default — handlers can override via their own response headers
    resp.headers.setdefault('Content-Security-Policy',
                            "default-src 'self'; frame-ancestors 'none'; base-uri 'none'")
    resp.headers['Strict-Transport-Security'] = 'max-age=31536000; includeSubDomains'
    # Hide server banner
    resp.headers['Server'] = 'picoclaw'
    return resp


@app.errorhandler(401)
def _401(e):
    record_auth_failure()
    return jsonify({'error': 'unauthorized'}), 401


@app.errorhandler(403)
def _403(e):
    return jsonify({'error': 'forbidden'}), 403


@app.errorhandler(404)
def _404(e):
    return jsonify({'error': 'not_found'}), 404


@app.errorhandler(413)
def _413(e):
    return jsonify({'error': 'payload_too_large', 'max': MAX_BODY}), 413


@app.errorhandler(429)
def _429(e):
    return jsonify({'error': 'rate_limited'}), 429


# ----- Endpoints -------------------------------------------------------------
# Public endpoints return the absolute minimum: just enough for a load balancer
# or uptime probe to confirm the service is alive. Detailed operational state
# (rate caps, security flags, version, port, metrics, route list) only comes
# back on authenticated `/info`, `/metrics` and `/c` endpoints.

@app.route('/health')
def health():
    # Public, no auth. Intentionally minimal — no metrics, no counts, no version,
    # so scanners and the Cloudflare edge can't fingerprint the server.
    return jsonify({'status': 'ok'})


@app.route('/metrics')
def metrics_endpoint():
    # Prometheus-format; bearer-gated (fails closed if no WEBHOOK_TOKEN set).
    if not require_bearer():
        audit('denied_metrics')
        abort(401)
    lines = ['# HELP webhook_requests_total Total HTTP requests',
             '# TYPE webhook_requests_total counter']
    for k, v in metrics.items():
        lines.append(f'webhook_{k} {v}')
    lines.append(f'webhook_banned_ips {len(banned)}')
    return '\n'.join(lines) + '\n', 200, {'Content-Type': 'text/plain; charset=utf-8'}


@app.route('/info')
def info_endpoint():
    """Full operational state — bearer-gated (fails closed if no
    WEBHOOK_TOKEN set). Everything that used to be on / lives here:
    port, limits, security flags, endpoint list, version."""
    if not require_bearer():
        audit('denied_info')
        abort(401)
    return jsonify({
        'service': 'picoclaw-webhook-server',
        'version': '3.0',
        'prefix': '/c/',
        'legacy_prefix': '/custom/ (308 redirect)',
        'endpoints': [
            '/health', '/metrics (auth)', '/info (auth)',
            '/hook/<name>', '/hook/github/<event>', '/hook/gitlab/<event>',
            '/notify',
            '/c (list, auth)', '/c/<name> (user-defined)',
        ],
        'port': PORT,
        'limits': {
            'max_body_bytes': MAX_BODY,
            'rate_per_ip_min': RATE_PER_IP,
            'rate_per_route_min': RATE_PER_ROUTE,
            'rate_global_min': RATE_GLOBAL,
            'burst_per_ip_10s': BURST_PER_IP,
            'handler_timeout_sec': HANDLER_TIMEOUT,
            'ban_minutes': BAN_MINUTES,
            'auth_fail_threshold': AUTH_FAIL_THRESHOLD,
        },
        'security': {
            'bearer_auth': bool(TOKEN),
            'hmac_verification': bool(HMAC_SECRET),
            'github_hmac': bool(GITHUB_SECRET),
            'gitlab_token': bool(GITLAB_TOKEN),
            'cloudflare_access': bool(CF_ACCESS_AUD),
            'ip_allowlist': bool(IP_ALLOWLIST),
            'trust_proxy': TRUST_PROXY,
            'honeypot': len(HONEYPOT_PATHS) + len(HONEYPOT_PREFIXES),
        },
        'metrics': dict(metrics),
        'banned_ips': len(banned),
    })


@app.route('/hook/<name>', methods=['POST'])
def hook(name):
    r = pre_checks()
    if r is not None: return r
    if not valid_route_name(name):
        abort(404)
    if not check_bearer():
        audit('denied_bearer', {'name': name})
        abort(401)
    if HMAC_SECRET and not check_hmac(HMAC_SECRET):
        audit('denied_hmac', {'name': name})
        abort(401)
    if not check_route_rate(name):
        audit('route_rate', {'name': name})
        return jsonify({'error': 'route_rate_limited'}), 429

    payload = request.get_json(silent=True) or {}
    prompt = f"[WEBHOOK:{name}] Received event. Payload:\n{json.dumps(payload, indent=2)[:2000]}\n\nAnalyze and act or summarize."
    audit('hook', {'name': name, 'size': len(str(payload))})
    try:
        result = send_to_agent(prompt, session=f'webhook-{name}')
        return jsonify({'status': 'processed', 'name': name, 'preview': result[-500:]})
    except subprocess.TimeoutExpired:
        return jsonify({'error': 'agent_timeout'}), 504
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/hook/github/<event>', methods=['POST'])
def github_hook(event):
    r = pre_checks()
    if r is not None: return r
    if not valid_route_name(event):
        abort(404)
    if GITHUB_SECRET and not check_hmac(GITHUB_SECRET, 'X-Hub-Signature-256'):
        audit('denied_github_hmac', {'event': event})
        abort(401)
    if not check_route_rate('github:' + event):
        return jsonify({'error': 'route_rate_limited'}), 429

    payload = request.get_json(silent=True) or {}
    repo = payload.get('repository', {}).get('full_name', '?')
    sender = payload.get('sender', {}).get('login', '?')
    prompt = f"[GITHUB:{event}] {sender} on {repo}:\n{json.dumps(payload, indent=2)[:2000]}\n\nSummarize and act if needed."
    audit('github_hook', {'event': event, 'repo': repo, 'sender': sender})
    try:
        result = send_to_agent(prompt, session=f'github-{event}')
        return jsonify({'status': 'processed', 'event': event, 'repo': repo})
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/hook/gitlab/<event>', methods=['POST'])
def gitlab_hook(event):
    r = pre_checks()
    if r is not None: return r
    if not valid_route_name(event):
        abort(404)
    if GITLAB_TOKEN and not hmac.compare_digest(
            request.headers.get('X-Gitlab-Token', ''), GITLAB_TOKEN):
        audit('denied_gitlab_token', {'event': event})
        abort(401)
    if not check_route_rate('gitlab:' + event):
        return jsonify({'error': 'route_rate_limited'}), 429
    payload = request.get_json(silent=True) or {}
    audit('gitlab_hook', {'event': event})
    try:
        result = send_to_agent(payload and json.dumps(payload)[:2000] or '', session=f'gitlab-{event}')
        return jsonify({'status': 'processed', 'event': event})
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/notify', methods=['POST'])
def notify():
    r = pre_checks()
    if r is not None: return r
    if not check_bearer():
        abort(401)
    text = request.get_json(silent=True, force=True)
    if isinstance(text, dict):
        text = text.get('text') or text.get('message') or json.dumps(text)
    text = text or request.get_data(as_text=True) or ''
    if not text:
        return jsonify({'error': 'empty'}), 400
    audit('notify', {'size': len(text)})
    try:
        result = send_to_agent(text, session='webhook-notify')
        return jsonify({'status': 'processed', 'preview': result[-500:]})
    except Exception as e:
        return jsonify({'error': str(e)}), 500


# ----- User-defined dynamic routes ------------------------------------------
def _dispatch_custom(name):
    """Shared implementation for /c/<name> and legacy /custom/<name>."""
    r = pre_checks()
    if r is not None: return r
    if not valid_route_name(name):
        abort(404)

    from pathlib import Path
    route_dir = Path(HOME) / '.picoclaw' / 'webhooks' / name
    # Double guard: resolve and make sure we stay inside webhooks/
    try:
        base = (Path(HOME) / '.picoclaw' / 'webhooks').resolve()
        real = route_dir.resolve()
        if not str(real).startswith(str(base)):
            abort(404)
    except Exception:
        abort(404)
    if not route_dir.is_dir():
        abort(404)

    meta_file = route_dir / 'meta.json'
    meta = {}
    if meta_file.is_file():
        try:
            meta = json.loads(meta_file.read_text())
        except Exception:
            pass

    # Method enforcement
    allowed = [m.upper() for m in meta.get('methods', ['GET', 'POST'])]
    if request.method not in allowed:
        audit('method_not_allowed', {'name': name, 'method': request.method})
        return jsonify({'error': 'method_not_allowed', 'allowed': allowed}), 405

    if meta.get('auth_required', True) and not check_bearer():
        audit('custom_denied_bearer', {'name': name})
        abort(401)

    if not check_route_rate(name):
        audit('route_rate', {'name': name})
        return jsonify({'error': 'route_rate_limited'}), 429

    handler = route_dir / 'handler.sh'
    if not handler.is_file():
        return jsonify({'error': 'handler missing'}), 500

    body = request.get_data(as_text=True, cache=True)
    env = os.environ.copy()
    env['REQUEST_METHOD'] = request.method
    env['REQUEST_PATH'] = f'/c/{name}'
    env['REMOTE_ADDR'] = client_ip()
    env['QUERY_STRING'] = request.query_string.decode('utf-8', errors='replace')
    env['CONTENT_TYPE'] = request.content_type or ''
    env['WEBHOOK_NAME'] = name
    audit('custom_hook', {'name': name, 'method': request.method, 'size': len(body)})

    try:
        proc = subprocess.run(
            ['/data/data/com.termux/files/usr/bin/bash', str(handler), env['QUERY_STRING']],
            input=body, capture_output=True, text=True,
            timeout=HANDLER_TIMEOUT, env=env,
        )
        metrics['custom_calls'] += 1
        stdout = proc.stdout
        # Content-type auto-detection
        if stdout.lstrip().startswith('<!DOCTYPE') or stdout.lstrip().startswith('<html'):
            return stdout, 200, {'Content-Type': 'text/html; charset=utf-8'}
        if stdout.lstrip().startswith('{') or stdout.lstrip().startswith('['):
            try:
                json.loads(stdout)
                return stdout, 200, {'Content-Type': 'application/json'}
            except Exception:
                pass
        return stdout or '', 200 if proc.returncode == 0 else 500
    except subprocess.TimeoutExpired:
        audit('handler_timeout', {'name': name})
        metrics['handler_timeouts'] += 1
        return jsonify({'error': 'handler_timeout', 'limit': HANDLER_TIMEOUT}), 504
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/c/<name>', methods=['GET', 'POST', 'PUT', 'DELETE', 'PATCH'])
def short_route(name):
    return _dispatch_custom(name)


@app.route('/custom/<name>', methods=['GET', 'POST', 'PUT', 'DELETE', 'PATCH'])
def legacy_custom_route(name):
    """Deprecated: /custom/<name> is a 301 redirect to /c/<name>.
    Kept only so public links minted before the rename keep working."""
    if not valid_route_name(name):
        abort(404)
    metrics['legacy_custom_hits'] += 1
    # Preserve query string
    qs = request.query_string.decode('utf-8', errors='replace')
    target = f'/c/{name}' + (f'?{qs}' if qs else '')
    return redirect(target, code=308)  # 308 preserves method + body


@app.route('/c')
@app.route('/custom')
def list_routes():
    r = pre_checks()
    if r is not None: return r
    if not require_bearer():
        audit('denied_list_routes')
        abort(401)
    from pathlib import Path
    base = Path(HOME) / '.picoclaw' / 'webhooks'
    routes = []
    if base.is_dir():
        for d in sorted(base.iterdir()):
            if not d.is_dir():
                continue
            if not valid_route_name(d.name):
                continue
            meta_file = d / 'meta.json'
            try:
                meta = json.loads(meta_file.read_text()) if meta_file.is_file() else {}
            except Exception:
                meta = {}
            routes.append({'name': d.name, **meta})
    return jsonify(routes)


@app.route('/')
def index():
    # Public root: no fingerprintable information (no version, no port, no
    # security flags, no limits, no endpoint list). An attacker who hits `/`
    # learns only that there is an HTTP service — which they already knew.
    return jsonify({'status': 'ok'})


if __name__ == '__main__':
    print(f"PicoClaw webhook server v3 on 127.0.0.1:{PORT}")
    print(f"Audit log: {AUDIT_LOG}")
    enabled = []
    if TOKEN: enabled.append('Bearer')
    if HMAC_SECRET: enabled.append('HMAC')
    if GITHUB_SECRET: enabled.append('GitHub-HMAC')
    if CF_ACCESS_AUD: enabled.append('CF-Access')
    if IP_ALLOWLIST: enabled.append(f'IP-allowlist({len(IP_ALLOWLIST)})')
    print(f"Security: {', '.join(enabled) if enabled else 'NONE (dev mode)'}")
    print(f"Rate: IP={RATE_PER_IP}/min  route={RATE_PER_ROUTE}/min  global={RATE_GLOBAL}/min"
          f"  burst={BURST_PER_IP}/10s")
    print(f"Caps: body={MAX_BODY}B  handler={HANDLER_TIMEOUT}s"
          f"  ban={BAN_MINUTES}min after {AUTH_FAIL_THRESHOLD} auth fails")
    # threaded=True so a single slow handler doesn't block others
    app.run(host='127.0.0.1', port=PORT, debug=False, threaded=True)
