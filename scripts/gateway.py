#!/usr/bin/env python3
"""
gateway.py — Manage the PicoClaw gateway (Telegram, Discord, etc.)

Starts/stops/restarts the gateway in a persistent tmux session on the device.

Usage:
    python scripts/gateway.py start       # Start gateway in tmux
    python scripts/gateway.py stop        # Stop gateway
    python scripts/gateway.py restart     # Restart gateway
    python scripts/gateway.py status      # Check if gateway is running
    python scripts/gateway.py logs        # Show recent gateway logs
    python scripts/gateway.py logs -f     # Follow logs in real-time
"""
import os
import sys
import time

# Fix Windows encoding
if sys.platform == 'win32' and hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    sys.stderr.reconfigure(encoding='utf-8', errors='replace')

sys.path.insert(0, os.path.dirname(__file__))
from connect import connect, run

TMUX_SESSION = 'picoclaw'
HOME = '/data/data/com.termux/files/home'
BINARY = f'{HOME}/picoclaw.bin'
LOG = f'{HOME}/.picoclaw/gateway.log'
SSL = f'SSL_CERT_FILE=/data/data/com.termux/files/usr/etc/tls/cert.pem'


def start(ssh):
    # Check if already running
    out, _ = run(ssh, f'tmux has-session -t {TMUX_SESSION} 2>&1 && echo running || echo stopped')
    if 'running' in out:
        print(f"Gateway already running in tmux session '{TMUX_SESSION}'.")
        print("Use 'restart' to restart, or 'stop' first.")
        return

    # Start in tmux
    cmd = (
        f'tmux new-session -d -s {TMUX_SESSION} '
        f'"{SSL} {BINARY} gateway 2>&1 | tee {LOG}"'
    )
    run(ssh, cmd)
    time.sleep(3)

    # Verify
    out, _ = run(ssh, f'tmux has-session -t {TMUX_SESSION} 2>&1 && echo running || echo stopped')
    if 'running' in out:
        out2, _ = run(ssh, f'tail -5 {LOG}')
        for line in out2.strip().split('\n'):
            cleaned = line.replace('\x1b[0m', '').strip()
            if cleaned and not any(c in cleaned for c in ['╗','╝','╚','║','═']):
                print(f"  {cleaned}")
        print(f"\nGateway started in tmux session '{TMUX_SESSION}'.")
    else:
        print("ERROR: Gateway failed to start. Check logs:")
        out3, _ = run(ssh, f'cat {LOG} 2>/dev/null | tail -20')
        print(out3)


def stop(ssh):
    run(ssh, f'pkill -f "picoclaw.bin gateway" 2>/dev/null')
    run(ssh, f'tmux kill-session -t {TMUX_SESSION} 2>/dev/null')
    print("Gateway stopped.")


def restart(ssh):
    print("Stopping gateway...")
    stop(ssh)
    time.sleep(2)
    print("Starting gateway...")
    start(ssh)


def status(ssh):
    out, _ = run(ssh, f'tmux has-session -t {TMUX_SESSION} 2>&1 && echo running || echo stopped')
    if 'running' in out:
        # Get uptime from tmux
        out2, _ = run(ssh, f'tmux display-message -t {TMUX_SESSION} -p "#{{session_created}}" 2>/dev/null')
        print(f"Gateway: RUNNING (tmux session '{TMUX_SESSION}')")
        # Show last few log lines
        out3, _ = run(ssh, f'tail -5 {LOG} 2>/dev/null')
        for line in out3.strip().split('\n'):
            cleaned = line.replace('\x1b[0m', '').strip()
            if cleaned and not any(c in cleaned for c in ['╗','╝','╚','║','═']):
                print(f"  {cleaned}")
    else:
        print("Gateway: STOPPED")


def logs(ssh, follow=False):
    if follow:
        print(f"Following {LOG} (Ctrl+C to stop)...")
        print("---")
        # Use a channel to stream
        transport = ssh.get_transport()
        channel = transport.open_session()
        channel.exec_command(f'tail -f {LOG}')
        try:
            while True:
                if channel.recv_ready():
                    data = channel.recv(4096).decode('utf-8', errors='replace')
                    sys.stdout.write(data)
                    sys.stdout.flush()
                if channel.exit_status_ready():
                    break
                time.sleep(0.1)
        except KeyboardInterrupt:
            print("\n--- Stopped following logs ---")
        finally:
            channel.close()
    else:
        out, _ = run(ssh, f'tail -30 {LOG} 2>/dev/null')
        print(out)


def main():
    if len(sys.argv) < 2:
        print("Usage: python scripts/gateway.py <start|stop|restart|status|logs>")
        print("       python scripts/gateway.py logs -f    (follow logs)")
        sys.exit(1)

    action = sys.argv[1]
    ssh = connect()

    if action == 'start':
        start(ssh)
    elif action == 'stop':
        stop(ssh)
    elif action == 'restart':
        restart(ssh)
    elif action == 'status':
        status(ssh)
    elif action == 'logs':
        follow = '-f' in sys.argv
        logs(ssh, follow=follow)
    else:
        print(f"Unknown action: {action}")
        print("Use: start, stop, restart, status, logs")

    ssh.close()


if __name__ == '__main__':
    main()
