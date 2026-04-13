#!/usr/bin/env python3
"""
find_device.py — Auto-discover PicoClaw device on the local network.

Scans the local subnet for SSH on port 8022 (Termux default),
verifies it's a PicoClaw device, and optionally updates .env.

Usage:
    python scripts/find_device.py              # Scan and report
    python scripts/find_device.py --update     # Scan and update .env
    python scripts/find_device.py --subnet 192.168.1  # Custom subnet
"""
import os
import socket
import sys
import time
import threading
from concurrent.futures import ThreadPoolExecutor, as_completed

if sys.platform == 'win32' and hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')

PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load_env():
    env = {}
    env_path = os.path.join(PROJECT, '.env')
    if os.path.isfile(env_path):
        with open(env_path, 'r', encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    k, _, v = line.partition('=')
                    env[k.strip()] = v.strip()
    return env


def get_local_subnet():
    """Guess the local subnet from the machine's IP address."""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(('8.8.8.8', 80))
        ip = s.getsockname()[0]
        s.close()
        return '.'.join(ip.split('.')[:3])
    except Exception:
        return '192.168.1'


def check_ssh(ip, port=8022, timeout=1.0):
    """Check if SSH port is open on given IP."""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(timeout)
        result = s.connect_ex((ip, port))
        if result == 0:
            # Try to read SSH banner
            try:
                banner = s.recv(256).decode('utf-8', errors='replace')
                s.close()
                return banner
            except Exception:
                s.close()
                return 'open'
        s.close()
    except Exception:
        pass
    return None


def verify_picoclaw(ip, port, password, username):
    """Verify this is a PicoClaw device by checking for the binary."""
    try:
        import paramiko
        ssh = paramiko.SSHClient()
        ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        ssh.connect(ip, port=port, username=username, password=password, timeout=5)
        stdin, stdout, stderr = ssh.exec_command('test -f ~/picoclaw.bin && echo PICOCLAW_OK || echo NOT_PICOCLAW', timeout=10)
        result = stdout.read().decode('utf-8', errors='replace').strip()
        ssh.close()
        return result == 'PICOCLAW_OK'
    except Exception:
        return False


def update_env(ip):
    """Update DEVICE_SSH_HOST in .env file."""
    env_path = os.path.join(PROJECT, '.env')
    if not os.path.isfile(env_path):
        print(f'  .env not found at {env_path}')
        return False
    with open(env_path, 'r', encoding='utf-8') as f:
        content = f.read()
    old_line = None
    for line in content.split('\n'):
        if line.startswith('DEVICE_SSH_HOST='):
            old_line = line
            break
    if old_line:
        new_line = f'DEVICE_SSH_HOST={ip}'
        if old_line == new_line:
            print(f'  .env already up to date ({ip})')
            return True
        content = content.replace(old_line, new_line)
        with open(env_path, 'w', encoding='utf-8') as f:
            f.write(content)
        print(f'  .env updated: {old_line.split("=")[1]} -> {ip}')
        return True
    return False


def main():
    args = sys.argv[1:]
    do_update = '--update' in args

    # Determine subnet
    subnet = None
    for i, a in enumerate(args):
        if a == '--subnet' and i + 1 < len(args):
            subnet = args[i + 1]
    if not subnet:
        subnet = get_local_subnet()

    env = load_env()
    known_ip = env.get('DEVICE_SSH_HOST', '')
    port = int(env.get('DEVICE_SSH_PORT', '8022'))
    username = env.get('DEVICE_SSH_USER', '')
    password = env.get('DEVICE_SSH_PASSWORD', '')

    print(f'Scanning {subnet}.1-254 for SSH on port {port}...')

    # First try the known IP (fast path)
    if known_ip:
        banner = check_ssh(known_ip, port, timeout=2.0)
        if banner:
            print(f'  Found at known IP: {known_ip} ({banner[:40].strip()})')
            if username and password and verify_picoclaw(known_ip, port, password, username):
                print(f'  Verified: PicoClaw device')
            else:
                print(f'  SSH open but could not verify PicoClaw')
            return

    # Scan the subnet
    found = []
    with ThreadPoolExecutor(max_workers=50) as pool:
        futures = {}
        for i in range(1, 255):
            ip = f'{subnet}.{i}'
            if ip == known_ip:
                continue
            futures[pool.submit(check_ssh, ip, port)] = ip

        for future in as_completed(futures):
            ip = futures[future]
            result = future.result()
            if result:
                found.append((ip, result))
                print(f'  Found: {ip} ({str(result)[:40].strip()})')

    if not found:
        print('  No devices found on this subnet.')
        print(f'  Make sure the phone is on WiFi and sshd is running (port {port}).')
        return

    # If exactly one found, offer to update
    if len(found) == 1:
        ip = found[0][0]
        if do_update:
            update_env(ip)
        else:
            print(f'\n  To update .env: python scripts/find_device.py --update')
    else:
        print(f'\n  Multiple devices found. Verify which is yours:')
        for ip, banner in found:
            print(f'    ssh {username or "user"}@{ip} -p {port}')


if __name__ == '__main__':
    main()
