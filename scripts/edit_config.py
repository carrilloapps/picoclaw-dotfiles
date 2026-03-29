#!/usr/bin/env python3
"""
edit_config.py — Read or modify PicoClaw config.json on the remote device.

Usage:
    # Dump current config (pretty-printed, API key masked)
    python scripts/edit_config.py

    # Get a specific field (dot notation)
    python scripts/edit_config.py get agents.defaults.model_name

    # Set a specific field
    python scripts/edit_config.py set agents.defaults.model_name "deepseek-v3.2"

    # Enable a tool
    python scripts/edit_config.py enable-tool exec
    python scripts/edit_config.py enable-tool web
    python scripts/edit_config.py enable-tool read_file

    # Enable a channel
    python scripts/edit_config.py enable-channel telegram
"""
import copy
import json
import os
import sys

# Fix Windows encoding (cp1252 can't handle emoji/ANSI from PicoClaw)
if sys.platform == 'win32' and hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    sys.stderr.reconfigure(encoding='utf-8', errors='replace')

sys.path.insert(0, os.path.dirname(__file__))
from connect import connect

CONFIG_PATH = '/data/data/com.termux/files/home/.picoclaw/config.json'


def read_config(ssh):
    sftp = ssh.open_sftp()
    with sftp.open(CONFIG_PATH, 'r') as f:
        config = json.loads(f.read())
    sftp.close()
    return config


def write_config(ssh, config):
    sftp = ssh.open_sftp()
    with sftp.open(CONFIG_PATH, 'w') as f:
        f.write(json.dumps(config, indent=2, ensure_ascii=False))
    sftp.close()


def mask_secrets(config):
    """Return a deep copy with API keys masked."""
    masked = copy.deepcopy(config)
    # Mask in providers
    for prov in masked.get('providers', {}).values():
        if isinstance(prov, dict) and 'api_key' in prov:
            key = prov['api_key']
            prov['api_key'] = f"***{key[-8:]}" if len(key) > 8 else '***'
    # Mask in model_list
    for model in masked.get('model_list', []):
        if 'api_key' in model:
            key = model['api_key']
            model['api_key'] = f"***{key[-8:]}" if len(key) > 8 else '***'
    return masked


def get_nested(obj, path):
    """Get a value from a nested dict using dot notation."""
    keys = path.split('.')
    for key in keys:
        if isinstance(obj, dict):
            obj = obj.get(key)
        elif isinstance(obj, list) and key.isdigit():
            obj = obj[int(key)]
        else:
            return None
    return obj


def set_nested(obj, path, value):
    """Set a value in a nested dict using dot notation."""
    keys = path.split('.')
    for key in keys[:-1]:
        if isinstance(obj, dict):
            obj = obj.setdefault(key, {})
        elif isinstance(obj, list) and key.isdigit():
            obj = obj[int(key)]
    # Try to parse value as JSON (for booleans, numbers, etc.)
    try:
        parsed = json.loads(value)
    except (json.JSONDecodeError, TypeError):
        parsed = value
    obj[keys[-1]] = parsed


def main():
    if len(sys.argv) < 2:
        # Dump config with masked secrets
        ssh = connect()
        config = read_config(ssh)
        masked = mask_secrets(config)
        # Only show non-empty, relevant sections
        summary = {
            'agents.defaults': masked['agents']['defaults'],
            'providers': masked['providers'],
            'model_list': masked['model_list'],
            'tools (enabled)': {k: v for k, v in masked.get('tools', {}).items()
                                if isinstance(v, dict) and v.get('enabled')},
            'channels (enabled)': {k: v for k, v in masked.get('channels', {}).items()
                                   if isinstance(v, dict) and v.get('enabled')},
        }
        print(json.dumps(summary, indent=2, ensure_ascii=False))
        ssh.close()
        return

    action = sys.argv[1]
    ssh = connect()
    config = read_config(ssh)

    if action == 'get' and len(sys.argv) >= 3:
        val = get_nested(config, sys.argv[2])
        if isinstance(val, (dict, list)):
            print(json.dumps(val, indent=2, ensure_ascii=False))
        else:
            print(val)

    elif action == 'set' and len(sys.argv) >= 4:
        path, value = sys.argv[2], sys.argv[3]
        old = get_nested(config, path)
        set_nested(config, path, value)
        write_config(ssh, config)
        print(f"{path}: {old} -> {get_nested(config, path)}")

    elif action == 'enable-tool' and len(sys.argv) >= 3:
        tool = sys.argv[2]
        if tool in config.get('tools', {}):
            if isinstance(config['tools'][tool], dict):
                config['tools'][tool]['enabled'] = True
            else:
                config['tools'][tool] = {'enabled': True}
            write_config(ssh, config)
            print(f"Tool '{tool}' enabled.")
        else:
            print(f"Tool '{tool}' not found. Available:")
            for k in sorted(config.get('tools', {}).keys()):
                if isinstance(config['tools'][k], dict):
                    status = 'ON' if config['tools'][k].get('enabled') else 'off'
                    print(f"  [{status:3s}] {k}")

    elif action == 'enable-channel' and len(sys.argv) >= 3:
        ch = sys.argv[2]
        if ch in config.get('channels', {}):
            config['channels'][ch]['enabled'] = True
            write_config(ssh, config)
            print(f"Channel '{ch}' enabled. You may need to fill in additional fields.")
        else:
            print(f"Channel '{ch}' not found. Available:")
            for k in sorted(config.get('channels', {}).keys()):
                if isinstance(config['channels'][k], dict):
                    status = 'ON' if config['channels'][k].get('enabled') else 'off'
                    print(f"  [{status:3s}] {k}")

    else:
        print("Usage:")
        print("  python scripts/edit_config.py                              # Dump summary")
        print("  python scripts/edit_config.py get <path>                   # Get value")
        print("  python scripts/edit_config.py set <path> <value>           # Set value")
        print("  python scripts/edit_config.py enable-tool <name>           # Enable tool")
        print("  python scripts/edit_config.py enable-channel <name>        # Enable channel")

    ssh.close()


if __name__ == '__main__':
    main()
