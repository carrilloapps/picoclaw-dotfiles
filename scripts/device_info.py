#!/usr/bin/env python3
"""
device_info.py — Print a full diagnostic report of the PicoClaw device.

Collects hardware info, software versions, PicoClaw status, config summary,
and connectivity checks.

Usage:
    python scripts/device_info.py
"""
import json
import os
import sys

# Fix Windows encoding (cp1252 can't handle emoji/ANSI from PicoClaw)
if sys.platform == 'win32' and hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    sys.stderr.reconfigure(encoding='utf-8', errors='replace')

sys.path.insert(0, os.path.dirname(__file__))
from connect import connect, run


def section(title):
    print(f"\n{'=' * 60}")
    print(f"  {title}")
    print(f"{'=' * 60}\n")


def main():
    ssh = connect()

    # --- Hardware ---
    section("HARDWARE")
    commands = {
        'Brand': 'getprop ro.product.brand 2>/dev/null',
        'Model': 'getprop ro.product.model 2>/dev/null',
        'Device': 'getprop ro.product.device 2>/dev/null',
        'SoC': 'getprop ro.soc.model 2>/dev/null',
        'Platform': 'getprop ro.board.platform 2>/dev/null',
        'Architecture': 'getprop ro.product.cpu.abi 2>/dev/null',
        'Android': 'getprop ro.build.version.release 2>/dev/null',
        'API Level': 'getprop ro.build.version.sdk 2>/dev/null',
        'Kernel': 'uname -r',
        'CPU Cores': "cat /proc/cpuinfo 2>/dev/null | grep -c processor",
    }
    for label, cmd in commands.items():
        out, _ = run(ssh, cmd)
        print(f"  {label:15s}: {out.strip()}")

    # Memory
    out, _ = run(ssh, 'free -h 2>/dev/null')
    for line in out.strip().split('\n'):
        print(f"  {line}")

    # --- Software ---
    section("SOFTWARE")
    sw_commands = {
        'Termux': "termux-info 2>/dev/null | grep TERMUX_VERSION | head -1",
        'Termux Release': "termux-info 2>/dev/null | grep TERMUX_APK_RELEASE | head -1",
        'OpenSSH': "dpkg -l openssh 2>/dev/null | grep openssh | awk '{print $3}'",
        'CA Certificates': "dpkg -l ca-certificates 2>/dev/null | grep ca-cert | awk '{print $3}'",
    }
    for label, cmd in sw_commands.items():
        out, _ = run(ssh, cmd)
        val = out.strip().split('=')[-1] if '=' in out else out.strip()
        print(f"  {label:15s}: {val}")

    # --- PicoClaw ---
    section("PICOCLAW")
    out, _ = run(ssh, './picoclaw status 2>&1')
    for line in out.split('\n'):
        cleaned = line.replace('\x1b[0m', '').strip()
        if any(k in cleaned for k in ['Status', 'Version', 'Build', 'Config', 'Workspace', 'Model']):
            print(f"  {cleaned}")

    # Wrapper check
    out, _ = run(ssh, 'head -1 ~/picoclaw')
    is_wrapper = 'bash' in out
    print(f"  {'Wrapper':15s}: {'Deployed' if is_wrapper else 'NOT deployed (raw binary)'}")

    # Binary size
    out, _ = run(ssh, 'ls -lh ~/picoclaw.bin 2>/dev/null | awk \'{print $5}\'')
    if out.strip():
        print(f"  {'Binary size':15s}: {out.strip()}")

    # --- Config summary ---
    section("CONFIGURATION SUMMARY")
    out, _ = run(ssh, 'cat ~/.picoclaw/config.json')
    try:
        config = json.loads(out)
        print(f"  Provider       : {config['agents']['defaults']['provider']}")
        print(f"  Model          : {config['agents']['defaults']['model_name']}")
        print(f"  Base URL       : {config['providers']['openai']['base_url']}")
        print(f"  API Key        : {'***' + config['providers']['openai']['api_key'][-8:]}")

        enabled_tools = [k for k, v in config.get('tools', {}).items()
                         if isinstance(v, dict) and v.get('enabled')]
        enabled_channels = [k for k, v in config.get('channels', {}).items()
                            if isinstance(v, dict) and v.get('enabled')]
        print(f"  Enabled tools  : {', '.join(enabled_tools) if enabled_tools else '(none except write_file)'}")
        print(f"  Enabled channels: {', '.join(enabled_channels) if enabled_channels else '(none)'}")
    except json.JSONDecodeError:
        print("  ERROR: Could not parse config.json")

    # --- Skills ---
    section("INSTALLED SKILLS")
    out, _ = run(ssh, 'ls ~/.picoclaw/workspace/skills/')
    for skill in out.strip().split('\n'):
        if skill.strip():
            print(f"  - {skill.strip()}")

    # --- Connectivity ---
    section("CONNECTIVITY TEST")
    ssl = 'SSL_CERT_FILE=/data/data/com.termux/files/usr/etc/tls/cert.pem'
    api_key = config['providers']['openai']['api_key']
    curl_cmd = (
        f'{ssl} curl -s -o /dev/null -w "%{{http_code}}" '
        f'https://ollama.com/v1/models '
        f'-H "Authorization: Bearer {api_key}" 2>&1'
    )
    out, _ = run(ssh, curl_cmd, timeout=15)
    status = out.strip()
    print(f"  Ollama Cloud API: HTTP {status} {'OK' if status == '200' else 'FAILED'}")

    ssh.close()
    print()


if __name__ == '__main__':
    main()
