#!/usr/bin/env python3
"""
connect.py — SSH connection helper for PicoClaw device.

Provides a reusable `connect()` function and a CLI for quick commands.

Usage:
    # Interactive: run a single command
    python scripts/connect.py "uname -a"

    # Interactive: check PicoClaw status
    python scripts/connect.py status

    # As a library (from other scripts):
    from connect import connect
    ssh = connect()
    stdin, stdout, stderr = ssh.exec_command('./picoclaw status 2>&1')
"""
import os
import sys
import paramiko

# Fix Windows encoding (cp1252 can't handle emoji/ANSI from PicoClaw)
if sys.platform == 'win32' and hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    sys.stderr.reconfigure(encoding='utf-8', errors='replace')

# ---------------------------------------------------------------------------
# .env loader (no external dependency)
# ---------------------------------------------------------------------------
def _load_env(path=None):
    """Load .env file into os.environ. Minimal implementation, no deps."""
    if path is None:
        path = os.path.join(os.path.dirname(__file__), '..', '.env')
    path = os.path.abspath(path)
    if not os.path.isfile(path):
        print(f"ERROR: .env not found at {path}", file=sys.stderr)
        print("Copy .env.example to .env and fill in your values.", file=sys.stderr)
        sys.exit(1)
    with open(path, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#') or '=' not in line:
                continue
            key, _, value = line.partition('=')
            os.environ.setdefault(key.strip(), value.strip())


def connect():
    """Return a connected paramiko.SSHClient using credentials from .env."""
    _load_env()
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(
        hostname=os.environ['DEVICE_SSH_HOST'],
        port=int(os.environ['DEVICE_SSH_PORT']),
        username=os.environ['DEVICE_SSH_USER'],
        password=os.environ['DEVICE_SSH_PASSWORD'],
        timeout=15,
    )
    return ssh


def run(ssh, cmd, timeout=30):
    """Execute a command and return (stdout, stderr) as strings."""
    stdin, stdout, stderr = ssh.exec_command(cmd, timeout=timeout)
    out = stdout.read().decode('utf-8', errors='replace')
    err = stderr.read().decode('utf-8', errors='replace')
    return out, err


def main():
    if len(sys.argv) < 2:
        print("Usage: python scripts/connect.py <command|status|agent \"msg\">")
        sys.exit(1)

    arg = ' '.join(sys.argv[1:])

    # Shortcuts
    if arg == 'status':
        arg = './picoclaw status 2>&1'
    elif arg.startswith('agent '):
        msg = arg[6:]
        arg = f'SSL_CERT_FILE=/data/data/com.termux/files/usr/etc/tls/cert.pem ./picoclaw agent -s "cli:script" -m {msg} 2>&1'

    ssh = connect()
    out, err = run(ssh, arg)
    if out:
        sys.stdout.write(out)
    if err:
        sys.stderr.write(err)
    ssh.close()


if __name__ == '__main__':
    main()
