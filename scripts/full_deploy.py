#!/usr/bin/env python3
"""
full_deploy.py — Complete deployment and verification of PicoClaw.

Runs all 10 steps:
 1. Install all required Termux packages
 2. Check storage access
 3. Deploy all utils/ files to device
 4. Generate AGENT.md with device context
 5. Verify config.json
 6. Verify security.yml
 7. Test transcribe.sh
 8. Test PicoClaw binary
 9. Clear sessions + restart gateway
10. End-to-end agent test

Usage:
    python scripts/full_deploy.py
"""
import json
import os
import sys
import time

if sys.platform == 'win32' and hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    sys.stderr.reconfigure(encoding='utf-8', errors='replace')

sys.path.insert(0, os.path.dirname(__file__))
from connect import connect, run

HOME = '/data/data/com.termux/files/home'
PREFIX = '/data/data/com.termux/files/usr'
SSL = f'SSL_CERT_FILE={PREFIX}/etc/tls/cert.pem'
PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def log(msg):
    print(msg)


def load_env():
    env = {}
    env_path = os.path.join(PROJECT, '.env')
    if not os.path.isfile(env_path):
        log("ERROR: .env not found. Run 'make setup' first.")
        sys.exit(1)
    with open(env_path, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith('#') and '=' in line:
                k, _, v = line.partition('=')
                env[k.strip()] = v.strip()
    return env


def main():
    env = load_env()
    ssh = connect()

    # ==== STEP 1: Install packages ====
    log('\n=== [1/10] Installing packages ===')
    out, _ = run(ssh, 'pkg install -y termux-api nmap dnsutils cronie jq net-tools iproute2 ffmpeg python tmux openssh ca-certificates curl wget 2>&1 | tail -3', timeout=120)
    log(f'  {out.strip().split(chr(10))[-1]}')

    # ==== STEP 2: Storage ====
    log('\n=== [2/10] Storage access ===')
    out, _ = run(ssh, 'ls ~/storage/ 2>/dev/null && echo OK || echo NOT_LINKED')
    if 'NOT_LINKED' in out:
        log('  Storage not linked. Run termux-setup-storage on the device screen.')
    else:
        log('  Storage: linked')

    # ==== STEP 3: Deploy utils/ ====
    log('\n=== [3/10] Deploying utils/ to device ===')
    sftp = ssh.open_sftp()

    # Check if ~/picoclaw is the binary or wrapper
    out, _ = run(ssh, f'head -c 4 {HOME}/picoclaw 2>/dev/null | od -A n -t x1 | head -1')
    if '7f 45 4c 46' in out:
        run(ssh, f'mv {HOME}/picoclaw {HOME}/picoclaw.bin')
        log('  Renamed binary to picoclaw.bin')

    # Deploy wrapper
    wrapper = open(os.path.join(PROJECT, 'utils/picoclaw-wrapper.sh'), 'rb').read()
    with sftp.open(f'{HOME}/picoclaw', 'wb') as f:
        f.write(wrapper)
    run(ssh, f'chmod +x {HOME}/picoclaw')
    log('  ~/picoclaw: wrapper deployed')

    # ~/bin/
    run(ssh, f'mkdir -p {HOME}/bin')

    # transcribe.sh with real Groq key
    groq_key = env.get('GROQ_API_KEY', '')
    ts = open(os.path.join(PROJECT, 'utils/transcribe.sh'), 'rb').read()
    ts = ts.replace(b'<YOUR_GROQ_API_KEY>', groq_key.encode())
    with sftp.open(f'{HOME}/bin/transcribe.sh', 'wb') as f:
        f.write(ts)
    run(ssh, f'chmod +x {HOME}/bin/transcribe.sh')
    log(f'  ~/bin/transcribe.sh: deployed (key: ***{groq_key[-6:]})')

    # device-context.sh
    sftp.put(os.path.join(PROJECT, 'utils/device-context.sh'), f'{HOME}/bin/device-context.sh')
    run(ssh, f'chmod +x {HOME}/bin/device-context.sh')
    log('  ~/bin/device-context.sh: deployed')

    # ~/bin/picoclaw wrapper
    with sftp.open(f'{HOME}/bin/picoclaw', 'wb') as f:
        f.write(wrapper)
    run(ssh, f'chmod +x {HOME}/bin/picoclaw')
    log('  ~/bin/picoclaw: wrapper deployed')

    # Shell profiles
    sftp.put(os.path.join(PROJECT, 'utils/bashrc'), f'{HOME}/.bashrc')
    sftp.put(os.path.join(PROJECT, 'utils/bash_profile'), f'{HOME}/.bash_profile')
    log('  .bashrc + .bash_profile: deployed')

    # ssl-certs.sh
    sftp.put(os.path.join(PROJECT, 'utils/ssl-certs.sh'), f'{PREFIX}/etc/profile.d/ssl-certs.sh')
    run(ssh, f'chmod 644 {PREFIX}/etc/profile.d/ssl-certs.sh')
    log('  ssl-certs.sh: deployed to profile.d')

    sftp.close()

    # ==== STEP 4: Generate AGENT.md ====
    log('\n=== [4/10] Generating AGENT.md ===')
    out, _ = run(ssh, f'{HOME}/bin/device-context.sh 2>&1', timeout=30)
    log(f'  {out.strip()}')

    # Patch IP if empty
    out2, _ = run(ssh, f'grep "Local IP" {HOME}/.picoclaw/workspace/AGENT.md')
    if '|  |' in out2 or '| |' in out2:
        ip = env.get('DEVICE_SSH_HOST', '?.?.?.?')
        run(ssh, f"sed -i 's/| Local IP        |.*|/| Local IP        | {ip} (WiFi)           |/' {HOME}/.picoclaw/workspace/AGENT.md")
        run(ssh, f"sed -i 's|| Gateway/Router  |.*|/| Gateway/Router  | {ip[:-3]}1                    |/' {HOME}/.picoclaw/workspace/AGENT.md")
        log(f'  Patched IP: {ip}')

    # ==== STEP 5: Verify config.json ====
    log('\n=== [5/10] Verifying config.json ===')
    sftp = ssh.open_sftp()
    with sftp.open(f'{HOME}/.picoclaw/config.json', 'r') as f:
        config = json.loads(f.read())
    sftp.close()

    checks = {
        'model': bool(config['agents']['defaults'].get('model_name')),
        'provider.openai': 'openai' in config.get('providers', {}),
        'provider.groq': 'groq' in config.get('providers', {}),
        'telegram.enabled': config['channels']['telegram'].get('enabled', False),
        'telegram.allow_from': bool(config['channels']['telegram'].get('allow_from')),
        'exec.enabled': config['tools']['exec'].get('enabled', False),
        'exec.allow_remote': config['tools']['exec'].get('allow_remote', False),
        'read_file': config['tools']['read_file'].get('enabled', False),
        'write_file': config['tools']['write_file'].get('enabled', False),
        'web_fetch': config['tools']['web_fetch'].get('enabled', False),
        'voice.echo': config.get('voice', {}).get('echo_transcription', False),
    }
    for name, ok in checks.items():
        status = 'OK' if ok else 'FAIL'
        log(f'  [{status}] {name}')

    # ==== STEP 6: Verify security.yml ====
    log('\n=== [6/10] Verifying security.yml ===')
    out, _ = run(ssh, f'cat {HOME}/.picoclaw/.security.yml')
    sec_checks = {
        'ollama_key': 'api_keys' in out and 'ollama' in out,
        'telegram_token': 'telegram' in out and 'token' in out,
        'groq_key': 'groq_api_key' in out,
    }
    for name, ok in sec_checks.items():
        log(f'  [{"OK" if ok else "FAIL"}] {name}')

    # ==== STEP 7: Test transcribe.sh ====
    log('\n=== [7/10] Testing transcribe.sh ===')
    out, _ = run(ssh, f'ls -t {PREFIX}/tmp/picoclaw_media/*.ogg 2>/dev/null | head -1')
    audio = out.strip()
    if audio:
        out, _ = run(ssh, f'{SSL} {HOME}/bin/transcribe.sh {audio} 2>&1', timeout=15)
        text = out.strip()[:100]
        log(f'  Transcription: "{text}"')
    else:
        log('  No audio files yet (will work when voice messages arrive)')

    # ==== STEP 8: Test PicoClaw binary ====
    log('\n=== [8/10] PicoClaw status ===')
    out, _ = run(ssh, f'{HOME}/picoclaw status 2>&1')
    for line in out.split('\n'):
        for keyword in ['Status', 'Version', 'Config', 'Workspace', 'Model']:
            if keyword in line:
                cleaned = line.replace('\x1b[0m', '').strip()
                if cleaned:
                    log(f'  {cleaned}')

    # ==== STEP 9: Restart gateway ====
    log('\n=== [9/10] Restarting gateway ===')
    run(ssh, 'rm -f ~/.picoclaw/workspace/sessions/*.jsonl ~/.picoclaw/workspace/sessions/*.json 2>/dev/null')
    run(ssh, 'pkill -9 -f picoclaw.bin 2>/dev/null')
    time.sleep(2)
    run(ssh, 'tmux kill-server 2>/dev/null')
    time.sleep(1)
    run(ssh, f'tmux new-session -d -s picoclaw "{SSL} {HOME}/picoclaw.bin gateway > {HOME}/.picoclaw/gateway.log 2>&1"')
    time.sleep(5)
    out, _ = run(ssh, f'tail -10 {HOME}/.picoclaw/gateway.log')
    for line in out.split('\n'):
        if any(c in line for c in ['╗', '╝', '╚', '║']):
            continue
        s = line.strip()
        if s and ('✓' in s or 'Channel' in s or 'Tool' in s or 'Gateway' in s):
            log(f'  {s}')

    # ==== STEP 10: E2E test ====
    log('\n=== [10/10] End-to-end test ===')
    out, _ = run(ssh, f'{SSL} {HOME}/picoclaw.bin agent -s "cli:e2e-final" -m "List your available tools in one line" 2>&1', timeout=60)
    for line in out.split('\n'):
        if any(c in line for c in ['╗', '╝', '╚', '║']):
            continue
        s = line.strip()
        if s and not s.startswith('\x1b['):
            log(f'  {s}')
            break

    log('\n========================================')
    log('  DEPLOYMENT COMPLETE')
    log('========================================')
    log('')
    log('Telegram bot is live. Send a message or voice note to test.')

    ssh.close()


if __name__ == '__main__':
    main()
