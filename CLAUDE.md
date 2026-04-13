# PicoClaw Dotfiles -- Claude Code Session Context

> Operational context for Claude Code sessions. For full documentation, see [`docs/`](docs/).

---

## Project Overview

PicoClaw is an ultra-lightweight AI assistant (Go binary, ~27 MB) running on a **Xiaomi Redmi Note 10 Pro** (Snapdragon 732G) via Termux. Cloud LLM providers handle inference.

- **Repo**: `D:\Desarrollo\AI\PicoClaw` (64 files)
- **Device**: Xiaomi Redmi Note 10 Pro (M2101K6R, codename `sweet`, PixelOS Android 16)
- **PicoClaw version**: v0.2.6
- **PicoClaw upstream**: [github.com/sipeed/picoclaw](https://github.com/sipeed/picoclaw)
- **Author**: [José Carrillo](https://carrillo.app) ([@carrilloapps](https://github.com/carrilloapps)), Senior Fullstack Developer & Tech Lead

---

## Primary Setup Method

The recommended way to set up a new device is the one-click installer:

```bash
# Run from Termux on the phone
curl -sL https://raw.githubusercontent.com/carrilloapps/picoclaw-dotfiles/main/utils/install.sh | bash

# Or clone and run
git clone https://github.com/carrilloapps/picoclaw-dotfiles.git
cd picoclaw-dotfiles && bash utils/install.sh
```

For remote deployment from a workstation, use `python scripts/full_deploy.py`.

---

## Connecting to the Device

Credentials in `.env` (git-ignored). Windows has no `sshpass`, so use paramiko.

```python
import paramiko, os
from dotenv import load_dotenv
load_dotenv()

ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect(
    os.getenv('DEVICE_SSH_HOST'),
    port=int(os.getenv('DEVICE_SSH_PORT')),
    username=os.getenv('DEVICE_SSH_USER'),
    password=os.getenv('DEVICE_SSH_PASSWORD'),
    timeout=15
)
stdin, stdout, stderr = ssh.exec_command('command here', timeout=30)
print(stdout.read().decode('utf-8', errors='replace'))
ssh.close()
```

**Encoding**: Always `PYTHONIOENCODING=utf-8` on Windows (PicoClaw outputs emoji/ANSI).

**SFTP for files with `$`**: Use `sftp.open()` instead of heredocs. Shell expansion eats `$@`.

---

## Quick Reference

### Scripts (workstation, via SSH)

```bash
python scripts/connect.py status          # Device status
python scripts/device_info.py             # Full diagnostic
python scripts/gateway.py start|stop|restart|status|logs
python scripts/change_model.py --list     # List models
python scripts/change_model.py <MODEL>    # Switch model
python scripts/edit_config.py             # Config summary
python scripts/full_deploy.py             # 10-step deploy
python scripts/verify_resilience.py       # 8-phase test
python scripts/install_scraping.py        # Install scraping stack
python scripts/setup_knowledge.py         # Create knowledge base
python scripts/setup_voice.py             # Configure STT
```

### Makefile

```bash
make status / make info / make health     # Diagnostics
make gateway-start / -stop / -restart     # Gateway
make agent MSG="Hello"                    # Send message
make model M=deepseek-v3.2               # Switch model
make deploy / make verify                 # Deploy / test
```

### Running Commands on Device

```python
cmd = 'SSL_CERT_FILE=/data/data/com.termux/files/usr/etc/tls/cert.pem ./picoclaw agent -s "cli:test" -m "Hello" 2>&1'
ssh.exec_command(cmd, timeout=60)
```

---

## Key Architecture Facts

- **`~/picoclaw`** is a WRAPPER script (3 lines), not the binary. Binary is `~/picoclaw.bin`.
- **TLS fix**: Wrapper sets `SSL_CERT_FILE` because Termux stores CA certs at `/data/data/com.termux/files/usr/etc/tls/cert.pem`.
- **v0.2.6 config structure**: Auto-migration v1→v2 removes `providers` key from config.json. API keys live ONLY in `security.yml` under `model_list.<name>:0.api_keys`. The `model_list` in config.json keeps `api_base` but drops `api_key`.
- **Google AI Studio**: Uses OpenAI-compatible endpoint at `https://generativelanguage.googleapis.com/v1beta/openai`. Provider type is `openai` (not `google` — PicoClaw rejects `google` provider). Models use `openai/gemini-*` format. Distinct from `antigravity/` which uses OAuth.
- **security.yml is critical**: Without API keys in security.yml's `model_list`, gateway exits silently (writes PID, removes it, exit code 1, no error message).
- **Gateway port**: v0.2.6 requires explicit `gateway.port` (e.g., 18790). Port 0 is rejected.
- **ADB self-bridge**: Requires one-time setup from workstation (USB cable or wireless debugging). The `setprop`/`stop adbd`/`start adbd` commands require root — use `adb connect localhost:5555` from Termux only.
- **Gateway**: Runs in `tmux` session `picoclaw`, long-polls Telegram. Health: `http://127.0.0.1:18790`.
- **ADB self-bridge**: `localhost:5555`, provides uid=2000 shell access without root.
- **Notifications**: `~/bin/notifications.sh` reads via ADB dumpsys (no Android listener permission needed).
- **Watchdog**: `~/bin/watchdog.sh` every minute via cron -- restarts sshd, gateway, ADB, webhook-server, cloudflared.
- **Boot**: `~/.termux/boot/start-picoclaw.sh` brings up everything on reboot.
- **Backup monitor**: `~/bin/backup-monitor.sh` via termux-job-scheduler every 5 min -- restarts crond/sshd if dead.
- **LLM failover**: `~/bin/auto-failover.sh` probes providers in priority order (Azure → Ollama → Antigravity → Google). Runs at boot + on 429/500/503 errors detected by watchdog.
- **Webhook server v3**: Flask on `127.0.0.1:18791` in tmux session `webhook`. Defense-in-depth: honeypot (instant 444 + 4h ban), global/per-IP/per-route rate limits, 15/10s burst cap, 1 MiB body cap, CF Access JWT, Bearer + HMAC-SHA256, auto-ban after 10 auth fails in 5 min, handler subprocess timeout (30s), strict route-name regex, path-traversal guard, response hardening headers (HSTS, CSP, X-Frame, X-CTO, Permissions-Policy). Dynamic routes are read from disk per-request — no reload needed when webhook-manage.sh adds/removes them.
- **Webhook URL prefix**: `/c/<name>` (short). Legacy `/custom/<name>` returns `308 Permanent Redirect` to `/c/<name>` — preserves method + body. Route names validated as `[a-z0-9][a-z0-9_-]{0,62}`.
- **Cloudflared tunnel**: `pico.carrillo.app`, runs via `proot -b resolv.conf:/etc/resolv.conf` (Termux DNS SRV workaround). Managed by `~/bin/cloudflare-tool.sh`.
- **Dynamic webhooks**: `~/bin/webhook-manage.sh` gives the agent full CRUD: create-route, create-form, update-html, update-handler, rename, clone, methods, auth, stats, clear-data, remove. The contact form at `/c/contact` is a DEMO — the user can delete/rename/modify it from chat at any time.
- **Universal form handler**: `~/bin/form-handler.sh` (copied into every form dir) writes to JSONL, indexes in RAG (`doc_id=form:<name>:<ts>`), fires `termux-notification`, and sends a Telegram message to the first allowed owner.
- **Log rotation**: `~/bin/log-rotate.sh` hourly (`15 * * * *`). Glob-discovers every `.log/.out/.err/.jsonl` under `$HOME`, `$PREFIX/tmp`, `~/.npm/_logs`, `~/.cache`. Caps: 2MB/5000 lines for logs, 5MB/10000 for JSONL. Purges npm/pip/apt caches + old media/backups/snapshots daily at 03:15.

### Providers (fallback chain)

Azure GPT-4o --> Ollama Cloud (gpt-oss:120b) --> Antigravity (OAuth) --> Google AI Studio (Gemini)

Failover is automated via `~/bin/auto-failover.sh`:
- Runs at boot (in start-picoclaw.sh) to pick healthy provider before gateway starts
- Watchdog monitors gateway.log for 429/500/503 errors, triggers failover after 2+ errors with 5min cooldown
- Probes each provider with real chat completion request (HTTP 200 = healthy)
- Updates config.json default model_name and restarts gateway in tmux
- Sends Android push notification on provider switch

### Voice Pipeline

- **STT**: `~/bin/transcribe.sh` (Azure Whisper --> Groq Whisper cascade)
- **TTS**: `~/bin/tts-reply.sh` (Azure TTS --> Edge TTS, 6 voices)
- Built-in transcription is broken in v0.2.4/v0.2.6. Scripts work around it via `exec` tool.

### Enabled Tools (19)

`exec` (allow_remote), `read_file`, `edit_file`, `append_file`, `list_dir`, `write_file`, `web_fetch`, `web`, `cron`, `skills`, `find_skills`, `install_skill`, `message`, `send_file`, `spawn`, `spawn_status`, `subagent`, `media_cleanup`, `mcp`

### MCP Servers (4 active, 146 tools)

`filesystem`, `memory`, `sequential-thinking`, `github`

---

## Device File Layout

```
~/
|-- picoclaw              # Wrapper script (sets SSL_CERT_FILE, execs binary)
|-- picoclaw.bin          # Go binary (25.7 MB, aarch64)
|-- bin/                  # 20 device scripts (transcribe, tts, adb, ui, media, watchdog, notifications, failover, scrape, model switch)
|-- media/                # Captured photos, audio, screenshots (temp, cleaned hourly)
|-- .picoclaw/
|   |-- config.json       # Main config (providers, models, tools, channels)
|   |-- .security.yml     # Tokens (Telegram, API keys)
|   +-- workspace/
|       |-- AGENT.md      # Agent persona + voice + device context
|       |-- knowledge/    # Persistent knowledge base (.md files)
|       +-- skills/       # Installed skills
|-- .picoclaw_keys        # API keys for voice scripts (Azure, Groq)
|-- .device_pin           # Screen unlock PIN
+-- .termux/boot/start-picoclaw.sh  # Auto-start on boot
```

---

## Repo Structure (57 files)

```
D:\Desarrollo\AI\PicoClaw\
|-- assets/               # 4 device photos and screenshots
|-- config/               # 3 config templates (sanitized)
|-- docs/                 # 9 step-by-step guides (00-09)
|-- scripts/              # 11 Python scripts + README (12 files)
|-- utils/                # 21 device-side scripts + AGENT.md + README (23 files)
|-- .env                  # Secrets (git-ignored)
|-- .env.example          # Template
|-- .gitignore            # Excludes secrets, binaries, runtime data
|-- CLAUDE.md             # THIS FILE
|-- LICENSE               # MIT
|-- Makefile              # 30+ targets
|-- README.md             # Public documentation with gallery
+-- SECRETS.md            # Credential management
```

---

## Known Gotchas

| Issue | Fix |
| ----- | --- |
| `x509: certificate signed by unknown authority` | Wrapper script or prepend `SSL_CERT_FILE=...` |
| `api_key or api_base is required` | Add to BOTH `providers` AND `model_list` |
| Gateway exits silently (writes PID then removes it) | Add API keys to `security.yml` `model_list` section (v0.2.6) |
| `invalid gateway port: 0` | Set `gateway.port` to 18790 (v0.2.6 rejects port 0) |
| Config auto-migration wipes security.yml | v0.2.6 migrates v1→v2 and empties `model_list` API keys in security.yml |
| `exec is restricted to internal channels` | Set `tools.exec.allow_remote: true` |
| `aria2c` package not found | Package name is `aria2` in Termux (not `aria2c`) |
| Voice not transcribing | Deploy `transcribe.sh`, keys in `~/.picoclaw_keys`, instructions in AGENT.md |
| Stale session context | `make clean-sessions` or use `-s "cli:fresh"` |
| Windows encoding errors | `PYTHONIOENCODING=utf-8` + `sys.stdout.buffer.write()` |
| `$@` eaten in heredocs | Use SFTP with `\x24@` hex escape |
| Webhook `HTTP 444` / silent close | Request path hit honeypot (.env/.git/wp-*/actuator/…) → IP banned 4h |
| Webhook `HTTP 413` | Body > 1 MiB → raise `WEBHOOK_MAX_BODY` |
| Webhook `HTTP 403` on known-good IP | Auto-ban after 10 auth failures in 5 min → wait `WEBHOOK_BAN_MINUTES` or restart webhook |
| Webhook `HTTP 405` | Method not in `meta.methods` → `webhook-manage.sh methods <name> GET,POST` |
| Client still hits `/custom/<name>` | `308 Permanent Redirect` to `/c/<name>` — update client or let redirect chain resolve |
| Operator endpoints (`/info`, `/metrics`, `/c`) return `401` even on LAN | `WEBHOOK_TOKEN` not loaded into server process. Must launch via `~/bin/webhook-start.sh` (sources `.picoclaw_keys` with `set -a`); `python3 webhook-server.py` direct → token unset → fail-closed 401 |
| `/info` returns fingerprintable data | Only on auth. Public `/` and `/health` return `{"status":"ok"}` only |
| Telegram `allow_from` accumulates duplicates | **Pre-`add-user` fix** (see git history). Current `channels-tool.sh` is idempotent; run `telegram dedupe-users` to clean legacy dupes |

---

## Documentation Index

For detailed guides, see [`docs/`](docs/):

0. [Termux & SSH Setup](docs/00-termux-ssh-setup.md) -- Termux install, SSH, user/IP, connect
1. [Hardware Setup](docs/01-hardware-setup.md) -- Device requirements, Termux apps, ADB
2. [PicoClaw Installation](docs/02-picoclaw-installation.md) -- Binary, TLS fix, config
3. [Providers Setup](docs/03-providers-setup.md) -- Azure, Ollama, Groq, Antigravity
4. [Telegram Integration](docs/04-telegram-integration.md) -- Bot, voice, streaming
5. [Device Control](docs/05-device-control.md) -- ADB, permissions, UI automation
6. [Resilience](docs/06-resilience.md) -- Boot, watchdog, verification
7. [Skills and MCP](docs/07-skills-and-mcp.md) -- Skills, 4 MCP servers
8. [Advanced Features](docs/08-advanced-features.md) -- Scraping, knowledge base, cron
9. [Remote Devices](docs/09-remote-devices.md) -- USB OTG control
10. [Complete Setup Guide](docs/10-complete-setup-guide.md) -- End-to-end from zero

---

<p align="center">
  <a href="README.md">📋 Back to README</a>
  &nbsp;&nbsp;|&nbsp;&nbsp;
  <a href="docs/01-hardware-setup.md">📖 Documentation</a>
</p>
