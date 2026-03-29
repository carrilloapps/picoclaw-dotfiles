#!/usr/bin/env python3
"""
change_model.py — Switch the PicoClaw model on the remote device.

Updates all 3 required locations in config.json:
  1. agents.defaults.model_name
  2. model_list[0].model_name
  3. model_list[0].model (with openai/ prefix)

Usage:
    python scripts/change_model.py deepseek-v3.2
    python scripts/change_model.py <model_name>
    python scripts/change_model.py --list          # List available models
"""
import json
import os
import sys

# Fix Windows encoding (cp1252 can't handle emoji/ANSI from PicoClaw)
if sys.platform == 'win32' and hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    sys.stderr.reconfigure(encoding='utf-8', errors='replace')

# Allow importing connect.py from same directory
sys.path.insert(0, os.path.dirname(__file__))
from connect import connect, run


CONFIG_PATH = '/data/data/com.termux/files/home/.picoclaw/config.json'
SSL_PREFIX = 'SSL_CERT_FILE=/data/data/com.termux/files/usr/etc/tls/cert.pem'


def list_models(ssh):
    """Query Ollama Cloud for available models."""
    # Read API key from device config
    out, _ = run(ssh, f'cat {CONFIG_PATH}')
    config = json.loads(out)
    api_key = config['providers']['openai']['api_key']

    cmd = f'{SSL_PREFIX} curl -s -H "Authorization: Bearer {api_key}" https://ollama.com/v1/models 2>&1'
    out, _ = run(ssh, cmd, timeout=20)
    data = json.loads(out)

    print("Available Ollama Cloud models:\n")
    for m in sorted(data.get('data', []), key=lambda x: x['id']):
        print(f"  {m['id']}")
    print(f"\nTotal: {len(data.get('data', []))} models")


def change_model(ssh, new_model):
    """Update config.json with the new model name."""
    # Read current config via SFTP
    sftp = ssh.open_sftp()
    with sftp.open(CONFIG_PATH, 'r') as f:
        config = json.loads(f.read())

    old_model = config['agents']['defaults']['model_name']

    # Update the 3 required fields
    config['agents']['defaults']['model_name'] = new_model
    if config.get('model_list') and len(config['model_list']) > 0:
        config['model_list'][0]['model_name'] = new_model
        config['model_list'][0]['model'] = f'openai/{new_model}'
    else:
        api_key = config['providers']['openai']['api_key']
        base_url = config['providers']['openai']['base_url']
        config['model_list'] = [{
            'model_name': new_model,
            'model': f'openai/{new_model}',
            'api_key': api_key,
            'api_base': base_url,
        }]

    # Write back
    with sftp.open(CONFIG_PATH, 'w') as f:
        f.write(json.dumps(config, indent=2, ensure_ascii=False))
    sftp.close()

    # Verify
    out, _ = run(ssh, './picoclaw status 2>&1')
    # Extract model line
    for line in out.split('\n'):
        if 'Model:' in line:
            print(line.strip())
            break

    print(f"\nModel changed: {old_model} -> {new_model}")


def main():
    if len(sys.argv) < 2:
        print("Usage:")
        print("  python scripts/change_model.py <model_name>")
        print("  python scripts/change_model.py --list")
        sys.exit(1)

    ssh = connect()

    if sys.argv[1] == '--list':
        list_models(ssh)
    else:
        new_model = sys.argv[1]
        change_model(ssh, new_model)

        # Quick test
        print("\nTesting new model...")
        cmd = f'{SSL_PREFIX} ./picoclaw agent -s "cli:model-test" -m "Respond with only: OK" 2>&1'
        out, _ = run(ssh, cmd, timeout=60)
        # Print last non-empty line (the response)
        lines = [l for l in out.strip().split('\n') if l.strip() and not l.startswith('\x1b')]
        if lines:
            print(f"Response: {lines[-1].strip()}")

    ssh.close()


if __name__ == '__main__':
    main()
