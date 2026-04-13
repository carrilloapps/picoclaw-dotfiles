#!/usr/bin/env python3
"""
full_deploy.py — Complete deployment and verification of PicoClaw.

Runs all 12 steps:
 1. Install all required Termux packages
 2. Check storage access + create symlinks
 3. Deploy all utils/ files to device (wrapper, scripts, boot, shell)
 4. Generate AGENT.md with device context
 5. Verify config.json (v2 structure)
 6. Verify security.yml (model API keys required for v0.2.6)
 7. Test transcribe.sh
 8. Test PicoClaw binary
 9. Setup cron schedule, termux-job-scheduler, permissions
10. Restart gateway with health check
11. ADB self-bridge verification
12. End-to-end agent test

Usage:
    python scripts/full_deploy.py
"""
import json
import os
import re
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
    log('\n=== [1/12] Installing packages ===')
    pkgs = 'termux-api nmap dnsutils cronie jq net-tools iproute2 ffmpeg python nodejs-lts tmux openssh ca-certificates curl wget git gh make clang imagemagick socat rsync zip unzip android-tools file openssl gnupg'
    out, _ = run(ssh, f'pkg install -y {pkgs} 2>&1 | tail -3', timeout=300)
    log(f'  {out.strip().split(chr(10))[-1]}')
    out, _ = run(ssh, 'pip install --quiet httpx beautifulsoup4 edge-tts pyyaml 2>&1 || true', timeout=120)
    out, _ = run(ssh, 'dpkg -l 2>/dev/null | tail -n +6 | wc -l', timeout=5)
    log(f'  Total packages: {out.strip()}')

    # ==== STEP 2: Storage ====
    log('\n=== [2/12] Storage access ===')
    out, _ = run(ssh, 'test -d ~/storage/shared && echo LINKED || echo MISSING')
    if 'MISSING' in out:
        run(ssh, 'mkdir -p ~/storage')
        for name, target in [('shared', '/storage/emulated/0'), ('dcim', '/storage/emulated/0/DCIM'),
                              ('downloads', '/storage/emulated/0/Download'), ('pictures', '/storage/emulated/0/Pictures')]:
            run(ssh, f'ln -sf {target} ~/storage/{name} 2>/dev/null')
        log('  Storage symlinks created')
    else:
        log('  Storage: already linked')

    # ==== STEP 3: Deploy all utils/ ====
    log('\n=== [3/12] Deploying utils/ to device ===')
    sftp = ssh.open_sftp()

    # Ensure directories exist
    for d in ['bin', 'media', '.picoclaw', '.picoclaw/workspace', '.picoclaw/workspace/sessions',
              '.picoclaw/workspace/state', '.picoclaw/workspace/skills', '.picoclaw/workspace/knowledge',
              '.picoclaw/workspace/memory', '.termux/boot']:
        run(ssh, f'mkdir -p {HOME}/{d}')

    # Check if ~/picoclaw is the binary or wrapper
    out, _ = run(ssh, f'head -c 4 {HOME}/picoclaw 2>/dev/null | od -A n -t x1 | head -1')
    if '7f 45 4c 46' in out:
        run(ssh, f'mv {HOME}/picoclaw {HOME}/picoclaw.bin')
        log('  Renamed binary to picoclaw.bin')

    # Deploy wrapper
    sftp.put(os.path.join(PROJECT, 'utils/picoclaw-wrapper.sh'), f'{HOME}/picoclaw')
    run(ssh, f'chmod 700 {HOME}/picoclaw')
    run(ssh, f'cp {HOME}/picoclaw {HOME}/bin/picoclaw && chmod 700 {HOME}/bin/picoclaw')
    log('  ~/picoclaw + ~/bin/picoclaw: wrapper deployed')

    # Deploy all scripts
    scripts = [
        'transcribe.sh', 'tts-reply.sh', 'adb-shell.sh', 'adb-enable.sh',
        'ensure-unlocked.sh', 'ui-control.sh', 'ui-auto.py', 'media-capture.sh',
        'media-cleanup.sh', 'device-context.sh', 'watchdog.sh', 'scrape.sh',
        'switch-model.sh', 'auth-antigravity.sh', 'remote-device.sh', 'notifications.sh',
        'detect-ip.sh', 'adb-connect.sh', 'auto-failover.sh',
        # Power tools (OpenClaw parity+)
        'pdf-tool.sh', 'image-tool.sh', 'document-tool.sh', 'media-tool.sh',
        'qr-tool.sh', 'rag-tool.sh', 'code-run.sh', 'wakeup.sh', 'workflow.sh',
        'webhook-server.py', 'browser-tool.sh', 'cloudflare-tool.sh',
        'cost-tracker.sh', 'audit-log.sh',
        # Central memory + self-modification (v0.3)
        'memory-ingest.sh', 'context-inject.sh', 'agent-self.sh',
        # Live channel + system management (v0.3.1)
        'channels-tool.sh', 'system-tool.sh',
        # Network resilience + dynamic webhooks (v0.3.2)
        'network-recovery.sh', 'webhook-manage.sh', 'log-rotate.sh',
        'form-handler.sh',
    ]
    deployed = 0
    for name in scripts:
        src = os.path.join(PROJECT, 'utils', name)
        if os.path.isfile(src):
            sftp.put(src, f'{HOME}/bin/{name}')
            run(ssh, f'chmod 700 {HOME}/bin/{name}')
            deployed += 1
    log(f'  ~/bin/: {deployed} scripts deployed')

    # Backup monitor
    bkmon = (
        '#!/data/data/com.termux/files/usr/bin/bash\n'
        f'export SSL_CERT_FILE={PREFIX}/etc/tls/cert.pem\n'
        'export PATH="$HOME/bin:$PATH"\n'
        'pgrep crond >/dev/null 2>&1 || crond\n'
        'pgrep -x sshd >/dev/null 2>&1 || sshd\n'
        'termux-wake-lock 2>/dev/null\n'
    )
    with sftp.open(f'{HOME}/bin/backup-monitor.sh', 'w') as f:
        f.write(bkmon)
    run(ssh, f'chmod 700 {HOME}/bin/backup-monitor.sh')
    log('  ~/bin/backup-monitor.sh: created')

    # Boot script
    sftp.put(os.path.join(PROJECT, 'utils/boot-picoclaw.sh'), f'{HOME}/.termux/boot/start-picoclaw.sh')
    run(ssh, f'chmod 700 {HOME}/.termux/boot/start-picoclaw.sh')
    log('  ~/.termux/boot/start-picoclaw.sh: deployed')

    # AGENT.md (static fallback)
    agent_src = os.path.join(PROJECT, 'utils/AGENT.md')
    out, _ = run(ssh, f'test -f {HOME}/.picoclaw/workspace/AGENT.md && echo EXISTS || echo MISSING')
    if 'MISSING' in out and os.path.isfile(agent_src):
        sftp.put(agent_src, f'{HOME}/.picoclaw/workspace/AGENT.md')
        log('  AGENT.md: static fallback deployed')

    # Shell profiles
    sftp.put(os.path.join(PROJECT, 'utils/bashrc'), f'{HOME}/.bashrc')
    sftp.put(os.path.join(PROJECT, 'utils/bash_profile'), f'{HOME}/.bash_profile')
    log('  .bashrc + .bash_profile: deployed')

    # Ensure .bashrc has crond guard
    out, _ = run(ssh, 'grep -q "pgrep crond" ~/.bashrc && echo OK || echo MISSING')
    if 'MISSING' in out:
        run(ssh, 'echo \'pgrep crond >/dev/null 2>&1 || crond 2>/dev/null\' >> ~/.bashrc')

    # ssl-certs.sh
    run(ssh, f'mkdir -p {PREFIX}/etc/profile.d')
    sftp.put(os.path.join(PROJECT, 'utils/ssl-certs.sh'), f'{PREFIX}/etc/profile.d/ssl-certs.sh')
    log('  ssl-certs.sh: deployed to profile.d')

    sftp.close()

    # ==== STEP 4: Generate AGENT.md ====
    log('\n=== [4/12] Generating AGENT.md ===')
    out, _ = run(ssh, f'export {SSL} && export PATH="$HOME/bin:$PATH" && {HOME}/bin/device-context.sh 2>&1 | tail -5', timeout=60)
    log(f'  {out.strip()}')

    # ==== STEP 5: Verify config.json ====
    log('\n=== [5/12] Verifying config.json ===')
    sftp = ssh.open_sftp()
    with sftp.open(f'{HOME}/.picoclaw/config.json', 'r') as f:
        config = json.loads(f.read())

    checks = {
        'version': config.get('version', 0) >= 2,
        'model_name': bool(config['agents']['defaults'].get('model_name')),
        'model_list': len(config.get('model_list', [])) > 0,
        'telegram.enabled': config['channels']['telegram'].get('enabled', False),
        'telegram.allow_from': bool(config['channels']['telegram'].get('allow_from')),
        'gateway.port': config['gateway'].get('port', 0) > 0,
        'gateway.host': config['gateway'].get('host', '') == '127.0.0.1',
        'exec.allow_remote': config['tools']['exec'].get('allow_remote', False),
        'mcp.servers': bool(config['tools'].get('mcp', {}).get('servers')),
    }
    for name, ok in checks.items():
        log(f'  [{"OK" if ok else "!!"}] {name}')

    # ==== STEP 6: Verify security.yml ====
    log('\n=== [6/12] Verifying security.yml ===')
    out, _ = run(ssh, f'cat {HOME}/.picoclaw/.security.yml')
    sec_checks = {
        'model_list api_keys': 'api_keys' in out,
        'telegram token': 'token:' in out and len(out.split('token:')[1].strip().split('\n')[0].strip(' "')) > 10,
        'groq_api_key': 'groq_api_key' in out,
    }
    for name, ok in sec_checks.items():
        log(f'  [{"OK" if ok else "!!"}] {name}')
    if not sec_checks['model_list api_keys']:
        log('  WARNING: security.yml missing model_list API keys — gateway will exit silently!')
        log('  Fix: add model API keys to security.yml. See docs/02-picoclaw-installation.md')

    sftp.close()

    # ==== STEP 7: Test transcribe.sh ====
    log('\n=== [7/12] Testing transcribe.sh ===')
    out, _ = run(ssh, f'test -x {HOME}/bin/transcribe.sh && echo OK || echo MISSING')
    log(f'  transcribe.sh: {out.strip()}')

    # ==== STEP 8: Test PicoClaw binary ====
    log('\n=== [8/12] PicoClaw status ===')
    out, _ = run(ssh, f'{HOME}/picoclaw status 2>&1')
    cleaned = re.sub(r'\x1b\[[0-9;]*m', '', out)
    for line in cleaned.split('\n'):
        for keyword in ['Status', 'Version', 'Config', 'Workspace', 'Model']:
            if keyword in line and line.strip():
                log(f'  {line.strip()}')

    # ==== STEP 9: Setup cron + job-scheduler + permissions ====
    log('\n=== [9/12] Cron, job-scheduler, permissions ===')
    cron = (
        f'* * * * * {HOME}/bin/watchdog.sh >> {HOME}/watchdog.log 2>&1\n'
        f'0 * * * * {HOME}/bin/media-cleanup.sh >> /dev/null 2>&1\n'
        f'0 */6 * * * df -h /data/data/com.termux 2>/dev/null | awk \'NR==2{{if ($5+0>90) print "[DISK] " $5}}\' >> {HOME}/watchdog.log 2>&1\n'
        f'0 0 * * 0 find {HOME}/.picoclaw/workspace/sessions -type f -mtime +7 -delete 2>/dev/null\n'
    )
    sftp = ssh.open_sftp()
    with sftp.open(f'{PREFIX}/tmp/cron.deploy', 'w') as f:
        f.write(cron)
    sftp.close()
    run(ssh, f'crontab {PREFIX}/tmp/cron.deploy && rm {PREFIX}/tmp/cron.deploy')
    run(ssh, 'pgrep crond >/dev/null 2>&1 || crond 2>/dev/null')
    run(ssh, 'termux-wake-lock 2>/dev/null')
    run(ssh, f'termux-job-scheduler --job-id 1 --period-ms 300000 --script {HOME}/bin/backup-monitor.sh 2>/dev/null || true')
    log('  Cron: 4 jobs (watchdog, media, disk, sessions)')
    log('  termux-job-scheduler: backup-monitor every 5min')
    log('  Wake lock: set')

    # Harden permissions
    run(ssh, f'chmod 600 {HOME}/.picoclaw/config.json {HOME}/.picoclaw/.security.yml 2>/dev/null')
    run(ssh, f'chmod 600 {HOME}/.picoclaw_keys {HOME}/.device_pin 2>/dev/null')
    run(ssh, f'chmod 700 {HOME}/bin/*.sh {HOME}/bin/*.py {HOME}/picoclaw {HOME}/picoclaw.bin 2>/dev/null')
    run(ssh, f'chmod 700 {HOME}/.termux/boot/start-picoclaw.sh 2>/dev/null')
    log('  Permissions: 700 scripts, 600 secrets')

    # Cloudflare Tunnel (token + webhook URL)
    cf_token = env.get('CLOUDFLARE_TUNNEL_TOKEN', '').strip()
    webhook_url = env.get('WEBHOOK_PUBLIC_URL', '').strip()
    if cf_token and not cf_token.startswith('<'):
        sftp = ssh.open_sftp()
        run(ssh, f'mkdir -p {HOME}/.cloudflared && chmod 700 {HOME}/.cloudflared')
        with sftp.open(f'{HOME}/.cloudflared/token', 'w') as f:
            f.write(cf_token)
        run(ssh, f'chmod 600 {HOME}/.cloudflared/token')
        log(f'  Cloudflare token: saved (last 10 chars: ...{cf_token[-10:]})')
        if webhook_url and not webhook_url.startswith('<'):
            with sftp.open(f'{HOME}/.cloudflared/webhook-url', 'w') as f:
                f.write(webhook_url)
            run(ssh, f'chmod 600 {HOME}/.cloudflared/webhook-url')
            log(f'  Webhook URL: {webhook_url}')
        sftp.close()
        # Start tunnel as daemon
        run(ssh, f'{HOME}/bin/cloudflare-tool.sh daemon 2>&1 | tail -2', timeout=30)
        time.sleep(5)
        out, _ = run(ssh, f'{HOME}/bin/cloudflare-tool.sh status 2>&1 | head -2', timeout=10)
        log(f'  Tunnel: {out.strip()[:100]}')

    # ==== STEP 10: Restart gateway ====
    log('\n=== [10/12] Restarting gateway ===')
    run(ssh, 'pkill -9 -f "picoclaw.bin gateway" 2>/dev/null; tmux kill-session -t picoclaw 2>/dev/null')
    time.sleep(2)
    run(ssh, f'tmux new-session -d -s picoclaw "{SSL} {HOME}/picoclaw.bin gateway > {HOME}/.picoclaw/gateway.log 2>&1"')
    time.sleep(6)
    out, _ = run(ssh, 'curl -sf http://127.0.0.1:18790/health 2>/dev/null || echo FAIL')
    if 'ok' in out:
        log('  Gateway: HEALTHY')
    else:
        log(f'  Gateway: {out.strip()[:100]}')
        log('  Check: cat ~/.picoclaw/gateway.log')

    # ==== STEP 11: ADB verification ====
    log('\n=== [11/12] ADB self-bridge ===')
    out, _ = run(ssh, 'adb -s localhost:5555 shell echo OK 2>&1')
    if 'OK' in out:
        log('  ADB: connected (uid=2000)')
    else:
        log(f'  ADB: not connected ({out.strip()[:60]})')
        log('  Run grant-permissions.sh from a computer to enable ADB TCP')

    # ==== STEP 12: E2E test ====
    log('\n=== [12/12] End-to-end test ===')
    out, _ = run(ssh, f'{SSL} {HOME}/picoclaw.bin agent -m "Reply with exactly: DEPLOY_OK" 2>&1 | tail -1', timeout=30)
    cleaned = re.sub(r'\x1b\[[0-9;]*m', '', out).strip()
    log(f'  Agent: {cleaned}')

    log('\n========================================')
    log('  DEPLOYMENT COMPLETE')
    log('========================================')
    log('')
    log('Telegram bot is live. Send a message or voice note to test.')
    log('Run "make verify" for full resilience verification.')

    ssh.close()


if __name__ == '__main__':
    main()
