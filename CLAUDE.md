# PicoClaw Dotfiles -- Claude Code Session Context

> Operational context for Claude Code sessions. For full documentation, see [`docs/`](docs/).

---

## Project Overview

PicoClaw is an ultra-lightweight AI assistant (Go binary, ~27 MB) running on a **Xiaomi Redmi Note 10 Pro** (Snapdragon 732G) via Termux. Cloud LLM providers handle inference.

- **Repo**: `D:\Desarrollo\AI\PicoClaw` (57 files)
- **Device**: Xiaomi Redmi Note 10 Pro (M2101K6R, codename `sweet`, PixelOS Android 16)
- **PicoClaw version**: v0.2.4
- **PicoClaw upstream**: [github.com/sipeed/picoclaw](https://github.com/sipeed/picoclaw)
- **Author**: [@carrilloapps](https://github.com/carrilloapps)

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
- **API key duplication**: config.json requires keys in BOTH `providers` AND `model_list` entries (v0.2.4 quirk).
- **Gateway**: Runs in `tmux` session `picoclaw`, long-polls Telegram. Health: `http://127.0.0.1:18790`.
- **ADB self-bridge**: `localhost:5555`, provides uid=2000 shell access without root.
- **Watchdog**: `~/bin/watchdog.sh` every minute via cron -- restarts sshd, gateway, ADB.
- **Boot**: `~/.termux/boot/start-picoclaw.sh` brings up everything on reboot.

### Providers (fallback chain)

Azure GPT-4o --> Ollama Cloud --> Groq --> Antigravity (Google OAuth, last resort)

### Voice Pipeline

- **STT**: `~/bin/transcribe.sh` (Azure Whisper --> Groq Whisper cascade)
- **TTS**: `~/bin/tts-reply.sh` (Azure TTS --> Edge TTS, 6 voices)
- Built-in transcription is broken in v0.2.4. Scripts work around it via `exec` tool.

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
|-- bin/                  # 16 device scripts (transcribe, tts, adb, ui, media, watchdog, scrape, model switch)
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
|-- docs/                 # 8 step-by-step guides
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
| `exec is restricted to internal channels` | Set `tools.exec.allow_remote: true` |
| Voice not transcribing | Deploy `transcribe.sh`, keys in `~/.picoclaw_keys`, instructions in AGENT.md |
| Stale session context | `make clean-sessions` or use `-s "cli:fresh"` |
| Windows encoding errors | `PYTHONIOENCODING=utf-8` + `sys.stdout.buffer.write()` |
| `$@` eaten in heredocs | Use SFTP with `\x24@` hex escape |

---

## Documentation Index

For detailed guides, see [`docs/`](docs/):

1. [Hardware Setup](docs/01-hardware-setup.md) -- Device requirements, Termux, SSH
2. [PicoClaw Installation](docs/02-picoclaw-installation.md) -- Binary, TLS fix, config
3. [Providers Setup](docs/03-providers-setup.md) -- Azure, Ollama, Groq, Antigravity
4. [Telegram Integration](docs/04-telegram-integration.md) -- Bot, voice, streaming
5. [Device Control](docs/05-device-control.md) -- ADB, permissions, UI automation
6. [Resilience](docs/06-resilience.md) -- Boot, watchdog, verification
7. [Skills and MCP](docs/07-skills-and-mcp.md) -- Skills, 4 MCP servers
8. [Advanced Features](docs/08-advanced-features.md) -- Scraping, knowledge base, cron

---

<p align="center">
  <a href="README.md">📋 Back to README</a>
  &nbsp;&nbsp;|&nbsp;&nbsp;
  <a href="docs/01-hardware-setup.md">📖 Documentation</a>
</p>
