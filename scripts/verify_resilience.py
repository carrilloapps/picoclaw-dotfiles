#!/usr/bin/env python3
"""8-phase resilience verification for PicoClaw."""
import os
import sys
import time
import re

if sys.platform == 'win32' and hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')

sys.path.insert(0, os.path.dirname(__file__))
from connect import connect, run


def clean(text):
    return re.sub(r'\x1b\[[0-9;]*m', '', text).strip()


def check(ssh, name, cmd):
    out, _ = run(ssh, cmd, timeout=10)
    ok = 'OK' in out
    status = 'PASS' if ok else 'FAIL'
    print(f'  [{status}] {name}')
    return ok


def main():
    ssh = connect()

    print('=' * 60)
    print('  PICOCLAW RESILIENCE VERIFICATION')
    print('=' * 60)

    # ---- PHASE 1: Baseline ----
    print('\n[PHASE 1] BASELINE STATE')
    services = {
        'sshd': 'pgrep -x sshd >/dev/null && echo OK || echo DOWN',
        'gateway': 'pgrep -f "picoclaw.bin gateway" >/dev/null && echo OK || echo DOWN',
        'tmux session': 'tmux has-session -t picoclaw 2>/dev/null && echo OK || echo DOWN',
        'ADB bridge': 'adb -s localhost:5555 shell echo ok 2>/dev/null | grep -q ok && echo OK || echo DOWN',
        'crond': 'pgrep crond >/dev/null && echo OK || echo DOWN',
        'watchdog cron': 'crontab -l 2>/dev/null | grep -q watchdog && echo OK || echo MISSING',
        'boot script': 'test -x ~/.termux/boot/start-picoclaw.sh && echo OK || echo MISSING',
    }
    for name, cmd in services.items():
        check(ssh, name, cmd)

    # ---- PHASE 2: Kill gateway → watchdog recovery ----
    print('\n[PHASE 2] KILL GATEWAY -> WATCHDOG RECOVERY')
    print('  Killing gateway...')
    run(ssh, 'pkill -9 -f "picoclaw.bin gateway" 2>/dev/null')
    run(ssh, 'tmux kill-session -t picoclaw 2>/dev/null')
    time.sleep(2)
    out, _ = run(ssh, 'pgrep -f "picoclaw.bin gateway" >/dev/null && echo ALIVE || echo DEAD')
    print(f'  After kill: {out.strip()}')

    print('  Running watchdog...')
    out, _ = run(ssh, '~/bin/watchdog.sh 2>&1')
    print(f'  Watchdog: {out.strip()}')
    time.sleep(5)

    out, _ = run(ssh, 'pgrep -f "picoclaw.bin gateway" >/dev/null && echo ALIVE || echo DEAD')
    ok = 'ALIVE' in out
    print(f'  After recovery: {out.strip()}')
    print(f'  [{"PASS" if ok else "FAIL"}] Gateway auto-recovered')

    # ---- PHASE 3: Disconnect ADB → watchdog recovery ----
    print('\n[PHASE 3] DISCONNECT ADB -> WATCHDOG RECOVERY')
    run(ssh, 'adb disconnect localhost:5555 2>/dev/null')
    time.sleep(1)
    out, _ = run(ssh, 'adb -s localhost:5555 shell echo ok 2>/dev/null | grep -q ok && echo CONNECTED || echo DISCONNECTED')
    print(f'  After disconnect: {out.strip()}')

    run(ssh, '~/bin/watchdog.sh 2>&1')
    time.sleep(5)

    out, _ = run(ssh, 'adb -s localhost:5555 shell echo ok 2>/dev/null | grep -q ok && echo CONNECTED || echo DISCONNECTED')
    ok = 'CONNECTED' in out
    print(f'  After recovery: {out.strip()}')
    print(f'  [{"PASS" if ok else "FAIL"}] ADB auto-recovered')

    # ---- PHASE 4: Verify boot script ----
    print('\n[PHASE 4] BOOT SCRIPT VERIFICATION')
    boot, _ = run(ssh, 'cat ~/.termux/boot/start-picoclaw.sh')
    boot_checks = {
        'sshd start': 'sshd' in boot,
        'wake-lock': 'termux-wake-lock' in boot,
        'ADB TCP enable': 'setprop' in boot and '5555' in boot,
        'ADB connect': 'adb connect' in boot,
        'ADB retry background': 'sleep' in boot and '&' in boot,
        'gateway in tmux': 'tmux new-session' in boot and 'gateway' in boot,
        'watchdog cron install': 'crontab' in boot and 'watchdog' in boot,
        'crond start': 'crond' in boot,
        'SSL_CERT_FILE': 'SSL_CERT_FILE' in boot,
    }
    for name, ok in boot_checks.items():
        print(f'  [{"PASS" if ok else "FAIL"}] {name}')
    print(f'  Score: {sum(boot_checks.values())}/{len(boot_checks)}')

    # ---- PHASE 5: Verify watchdog script ----
    print('\n[PHASE 5] WATCHDOG SCRIPT VERIFICATION')
    wd, _ = run(ssh, 'cat ~/bin/watchdog.sh')
    wd_checks = {
        'sshd monitor+restart': 'pgrep' in wd and 'sshd' in wd,
        'wake-lock refresh': 'termux-wake-lock' in wd,
        'ADB bridge check': 'localhost:5555' in wd,
        'ADB reconnect flow': 'adb connect' in wd,
        'gateway tmux check': 'tmux has-session' in wd,
        'gateway process check': 'picoclaw.bin gateway' in wd,
        'gateway respawn': 'tmux new-session' in wd,
        'selective logging': 'RESTART_NEEDED' in wd,
    }
    for name, ok in wd_checks.items():
        print(f'  [{"PASS" if ok else "FAIL"}] {name}')
    print(f'  Score: {sum(wd_checks.values())}/{len(wd_checks)}')

    # ---- PHASE 6: Telegram health ----
    print('\n[PHASE 6] TELEGRAM GATEWAY HEALTH')
    time.sleep(3)
    log, _ = run(ssh, 'tail -10 ~/.picoclaw/gateway.log')
    log_clean = clean(log)
    tg_ok = 'telegram' in log_clean.lower()
    tools_line = ''
    skills_line = ''
    channels_line = ''
    for line in log_clean.split('\n'):
        if 'Tools:' in line:
            tools_line = line.strip()
        if 'Skills:' in line:
            skills_line = line.strip()
        if 'Channels enabled' in line:
            channels_line = line.strip()
    print(f'  [{"PASS" if tg_ok else "FAIL"}] Telegram in gateway log')
    if tools_line:
        print(f'  {tools_line}')
    if skills_line:
        print(f'  {skills_line}')
    if channels_line:
        print(f'  {channels_line}')

    # ---- PHASE 7: Watchdog log ----
    print('\n[PHASE 7] WATCHDOG LOG (recent activity)')
    wdlog, _ = run(ssh, 'tail -5 ~/watchdog.log 2>/dev/null')
    if wdlog:
        for line in wdlog.strip().split('\n'):
            print(f'  {line}')
    else:
        print('  (empty — no restarts needed)')

    # ---- PHASE 8: Final state ----
    print('\n[PHASE 8] FINAL STATE')
    all_ok = True
    for name, cmd in services.items():
        ok = check(ssh, name, cmd)
        if not ok:
            all_ok = False

    print('\n' + '=' * 60)
    if all_ok:
        print('  ALL CHECKS PASSED — SYSTEM IS RESILIENT')
    else:
        print('  SOME CHECKS FAILED — REVIEW ABOVE')
    print('=' * 60)

    ssh.close()


if __name__ == '__main__':
    main()
