#!/usr/bin/env python3
"""
setup_voice.py — Configure voice transcription (Groq Whisper) on the device.

Reads GROQ_API_KEY from .env and updates the device config to enable
automatic voice message transcription via Groq's Whisper API.

Usage:
    python scripts/setup_voice.py              # Configure from .env
    python scripts/setup_voice.py <api_key>    # Configure with explicit key
    python scripts/setup_voice.py --status     # Check current voice config
"""
import json
import os
import sys

# Fix Windows encoding
if sys.platform == 'win32' and hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    sys.stderr.reconfigure(encoding='utf-8', errors='replace')

sys.path.insert(0, os.path.dirname(__file__))
from connect import connect, run

CONFIG_PATH = '/data/data/com.termux/files/home/.picoclaw/config.json'
SSL = 'SSL_CERT_FILE=/data/data/com.termux/files/usr/etc/tls/cert.pem'


def get_groq_key():
    """Get Groq API key from CLI arg or .env."""
    if len(sys.argv) >= 2 and not sys.argv[1].startswith('--'):
        return sys.argv[1]
    return os.environ.get('GROQ_API_KEY', '')


def show_status(ssh):
    sftp = ssh.open_sftp()
    with sftp.open(CONFIG_PATH, 'r') as f:
        config = json.loads(f.read())
    sftp.close()

    voice = config.get('voice', {})
    print("Voice configuration:")
    print(f"  echo_transcription: {voice.get('echo_transcription', False)}")
    print(f"  transcriber: {voice.get('transcriber', '(not set)')}")

    groq = voice.get('groq', {})
    if groq:
        key = groq.get('api_key', '')
        masked = f"***{key[-6:]}" if len(key) > 6 else '(empty)'
        print(f"  groq.api_key: {masked}")
        print(f"  groq.model: {groq.get('model', '(not set)')}")
    else:
        print("  groq: (not configured)")

    # Check if ffmpeg is available
    out, _ = run(ssh, 'command -v ffmpeg 2>/dev/null && echo OK || echo MISSING')
    print(f"  ffmpeg: {out.strip()}")

    # Check exec tool
    with ssh.open_sftp().open(CONFIG_PATH, 'r') as f:
        c2 = json.loads(f.read())
    exec_on = c2.get('tools', {}).get('exec', {}).get('enabled', False)
    print(f"  exec tool: {'enabled' if exec_on else 'DISABLED (required for ffmpeg)'}")


def setup(ssh, api_key):
    if not api_key:
        print("ERROR: No Groq API key provided.")
        print("  Option 1: Add GROQ_API_KEY to .env, then run this script")
        print("  Option 2: python scripts/setup_voice.py gsk_your_key_here")
        print("")
        print("Get a free key at: https://console.groq.com")
        sys.exit(1)

    if not api_key.startswith('gsk_'):
        print(f"WARNING: Key doesn't start with 'gsk_'. Groq keys typically do.")
        print(f"  Provided: {api_key[:10]}...")

    sftp = ssh.open_sftp()
    with sftp.open(CONFIG_PATH, 'r') as f:
        config = json.loads(f.read())

    # Set voice config
    config['voice'] = {
        'echo_transcription': True,
        'transcriber': 'groq',
        'groq': {
            'api_key': api_key,
            'model': os.environ.get('VOICE_MODEL', 'whisper-large-v3'),  # fallback default
        }
    }

    # Ensure exec tool is enabled (needed for ffmpeg)
    if not config.get('tools', {}).get('exec', {}).get('enabled'):
        config['tools']['exec']['enabled'] = True
        config['tools']['exec']['timeout_seconds'] = 30
        print("[*] Enabled exec tool (required for audio processing)")

    # Ensure ffmpeg is installed
    out, _ = run(ssh, 'command -v ffmpeg 2>/dev/null || echo missing')
    if 'missing' in out:
        print("[*] Installing ffmpeg...")
        out, _ = run(ssh, 'pkg install -y ffmpeg 2>&1 | tail -3', timeout=120)
        print(f"    {out.strip()}")

    with sftp.open(CONFIG_PATH, 'w') as f:
        f.write(json.dumps(config, indent=2, ensure_ascii=False))
    sftp.close()

    print("[OK] Voice transcription configured:")
    print(f"  Provider: Groq Whisper")
    print(f"  Model: {config['voice']['groq']['model']}")
    print(f"  API Key: ***{api_key[-6:]}")
    print(f"  Echo transcription: enabled")
    print("")
    print("Restart the gateway to apply:")
    print("  python scripts/gateway.py restart")


def main():
    if len(sys.argv) >= 2 and sys.argv[1] == '--status':
        ssh = connect()
        show_status(ssh)
        ssh.close()
        return

    ssh = connect()
    api_key = get_groq_key()
    setup(ssh, api_key)
    ssh.close()


if __name__ == '__main__':
    main()
