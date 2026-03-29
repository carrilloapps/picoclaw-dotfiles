#!/usr/bin/env python3
"""
deploy_wrapper.py — Deploy (or re-deploy) the TLS wrapper script on the device.

This script:
  1. Renames ~/picoclaw to ~/picoclaw.bin (if it's the real binary)
  2. Writes the wrapper script at ~/picoclaw
  3. Copies the wrapper to ~/bin/picoclaw
  4. Creates ~/.bash_profile and updates ~/.bashrc
  5. Creates /usr/etc/profile.d/ssl-certs.sh
  6. Verifies everything works

Safe to run multiple times (idempotent).

Usage:
    python scripts/deploy_wrapper.py
"""
import os
import sys

# Fix Windows encoding (cp1252 can't handle emoji/ANSI from PicoClaw)
if sys.platform == 'win32' and hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    sys.stderr.reconfigure(encoding='utf-8', errors='replace')

sys.path.insert(0, os.path.dirname(__file__))
from connect import connect, run

HOME = '/data/data/com.termux/files/home'
PREFIX = '/data/data/com.termux/files/usr'
CERT_PATH = f'{PREFIX}/etc/tls/cert.pem'
BINARY = f'{HOME}/picoclaw.bin'
WRAPPER = f'{HOME}/picoclaw'
WRAPPER_BIN = f'{HOME}/bin/picoclaw'


def main():
    ssh = connect()
    sftp = ssh.open_sftp()

    # --- Step 1: Rename binary if needed ---
    out, _ = run(ssh, f'file {WRAPPER} 2>/dev/null || echo "no-file-cmd"')
    # If current ~/picoclaw is the ELF binary (not a script), rename it
    out2, _ = run(ssh, f'head -c 4 {WRAPPER} 2>/dev/null | od -A n -t x1 | head -1')
    if '7f 45 4c 46' in out2:  # ELF magic bytes
        print("[1/6] Renaming binary: ~/picoclaw -> ~/picoclaw.bin")
        run(ssh, f'mv {WRAPPER} {BINARY}')
    else:
        print("[1/6] Binary already renamed (~/picoclaw is wrapper)")

    # --- Step 2: Write wrapper at ~/picoclaw ---
    print("[2/6] Writing wrapper: ~/picoclaw")
    wrapper_content = (
        b'#!/data/data/com.termux/files/usr/bin/bash\n'
        b'export SSL_CERT_FILE=' + CERT_PATH.encode() + b'\n'
        b'exec ' + BINARY.encode() + b' "\x24@"\n'
    )
    with sftp.open(WRAPPER, 'wb') as f:
        f.write(wrapper_content)
    run(ssh, f'chmod +x {WRAPPER}')

    # --- Step 3: Copy to ~/bin ---
    print("[3/6] Writing wrapper: ~/bin/picoclaw")
    run(ssh, f'mkdir -p {HOME}/bin')
    with sftp.open(WRAPPER_BIN, 'wb') as f:
        f.write(wrapper_content)
    run(ssh, f'chmod +x {WRAPPER_BIN}')

    # --- Step 4: Shell profiles ---
    print("[4/6] Writing ~/.bash_profile")
    bash_profile = b'# Load .bashrc for login shells\nif [ -f ~/.bashrc ]; then\n    . ~/.bashrc\nfi\n'
    with sftp.open(f'{HOME}/.bash_profile', 'wb') as f:
        f.write(bash_profile)

    print("[5/6] Updating ~/.bashrc")
    bashrc = (
        b'pgrep -x sshd >/dev/null || sshd\n'
        b'export SSL_CERT_FILE=' + CERT_PATH.encode() + b'\n'
        b'export PATH="\x24HOME/bin:\x24PATH"\n'
    )
    with sftp.open(f'{HOME}/.bashrc', 'wb') as f:
        f.write(bashrc)

    # --- Step 5: System-wide profile.d ---
    print("[6/6] Writing profile.d/ssl-certs.sh")
    ssl_profile = b'export SSL_CERT_FILE=' + CERT_PATH.encode() + b'\n'
    with sftp.open(f'{PREFIX}/etc/profile.d/ssl-certs.sh', 'wb') as f:
        f.write(ssl_profile)
    run(ssh, f'chmod 644 {PREFIX}/etc/profile.d/ssl-certs.sh')

    sftp.close()

    # --- Verify ---
    print("\nVerifying...")
    out, _ = run(ssh, f'{WRAPPER} status 2>&1')
    for line in out.split('\n'):
        if any(k in line for k in ['Status', 'Version', 'Config', 'Workspace', 'Model']):
            cleaned = line.replace('\x1b[0m', '').strip()
            if cleaned:
                print(f"  {cleaned}")

    print("\nDone. Wrapper deployed successfully.")
    ssh.close()


if __name__ == '__main__':
    main()
