# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in this project, please report it responsibly.

**Do NOT open a public issue.** Instead:

1. Email: **m@carrillo.app**
2. Or use [GitHub's private vulnerability reporting](https://github.com/carrilloapps/picoclaw-dotfiles/security/advisories/new)

Include:
- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

I will acknowledge receipt within 48 hours and provide a timeline for a fix.

## Scope

This project manages deployment configuration for PicoClaw on Android/Termux. Security-relevant areas include:

| Area | Risk | Mitigation |
|------|------|------------|
| API keys in `.env` / `security.yml` | Credential exposure | `.gitignore`, `chmod 600`, never in config.json |
| SSH access (port 8022) | Unauthorized access | Password auth, MaxAuthTries=3, WiFi-only |
| ADB self-bridge (port 5555) | Device control | Localhost-only binding, authorized keys |
| Gateway (port 18790) | API exposure | Bound to `127.0.0.1` only |
| Telegram bot token | Bot hijacking | Stored in `security.yml` (600), `allow_from` whitelist |

## Secrets Handling

- **Never** commit `.env`, `security.yml`, `.picoclaw_keys`, or `.device_pin`
- All secret files use `chmod 600` (owner read/write only)
- API keys live only in `security.yml`, not in `config.json`
- Template files use `<PLACEHOLDER>` values
- See [SECRETS.md](../SECRETS.md) for the full credential management guide

## Supported Versions

| Version | Supported |
|---------|-----------|
| Latest (main branch) | Yes |
| Older commits | Best effort |

## Dependencies

- **PicoClaw binary**: from [sipeed/picoclaw](https://github.com/sipeed/picoclaw) (MIT licensed)
- **MCP servers**: from npm (`@modelcontextprotocol/*`)
- **Python packages**: `paramiko`, `python-dotenv`, `httpx`, `beautifulsoup4`
