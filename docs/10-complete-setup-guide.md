# 10 — Complete Setup Guide

End-to-end guide for setting up PicoClaw on a new Android device. Covers everything from unboxing to a fully operational, self-healing AI assistant. Based on a real deployment on a Xiaomi Redmi Note 10 Pro with Android 16.

---

## Prerequisites

| Item | Details |
|------|---------|
| Android phone | Android 11+, aarch64 (any phone from 2018+) |
| WiFi | Phone and workstation on the same network |
| Workstation | Windows/macOS/Linux with Python 3.8+ and ADB |
| F-Droid | For installing Termux (NOT Google Play) |
| API key | At least one: [Google AI Studio](https://aistudio.google.com/apikey) (free, recommended), [Ollama](https://ollama.com) (free), Azure, or Groq |

---

## Phase 1: Prepare the Phone (5 minutes)

### 1.1 Install Termux apps from F-Droid

Open F-Droid on the phone and install:

- **Termux** — terminal and Linux environment
- **Termux:Boot** — auto-start scripts on boot (open once after install)
- **Termux:API** — camera, mic, GPS, SMS, sensors

### 1.2 Enable Developer Options

1. **Settings > About Phone** — tap "Build number" 7 times
2. **Settings > System > Developer Options** — enable:
   - **USB Debugging**
   - **Wireless Debugging**

### 1.3 Start SSH in Termux

Open Termux and run:

```bash
pkg update && pkg upgrade -y
pkg install -y openssh
passwd        # Set a password — remember it
sshd          # Start SSH server on port 8022
```

Find your IP and username:

```bash
ifconfig wlan0 | grep 'inet '    # Your IP (e.g., 192.168.1.101)
whoami                             # Your username (e.g., u0_a39)
```

---

## Phase 2: Configure the Workstation (3 minutes)

### 2.1 Clone and configure

```bash
git clone https://github.com/carrilloapps/picoclaw-dotfiles.git
cd picoclaw-dotfiles
pip install paramiko python-dotenv
cp .env.example .env
```

### 2.2 Fill in `.env`

Edit `.env` with your values:

```bash
# Required: SSH connection
DEVICE_SSH_HOST=192.168.1.101      # From ifconfig
DEVICE_SSH_PORT=8022
DEVICE_SSH_USER=u0_a39             # From whoami
DEVICE_SSH_PASSWORD=YourPassword   # From passwd

# Required: At least one LLM provider
OLLAMA_API_KEY=your_key_here
OLLAMA_MODEL=gpt-oss:120b

# Optional: Azure, Groq, Telegram
# See .env.example for all options
```

### 2.3 Test SSH

```bash
python scripts/connect.py "echo OK && whoami"
```

---

## Phase 3: Install PicoClaw (2 options)

### Option A: One-click from Termux (on phone or via SSH)

```bash
# SSH into the phone
ssh u0_a39@192.168.1.101 -p 8022

# Run the installer
curl -sL https://raw.githubusercontent.com/carrilloapps/picoclaw-dotfiles/main/utils/install.sh | bash
```

The installer handles all 15 steps automatically: packages, binary, TLS wrapper, config, scripts, MCP servers, boot script, watchdog, and gateway.

### Option B: Remote deploy from workstation

```bash
python scripts/full_deploy.py
```

This runs 12 steps: packages, storage, file deployment, AGENT.md generation, config verification, cron setup, gateway start, ADB check, and E2E test.

---

## Phase 4: Grant Android Permissions (one-time, 2 minutes)

This is the only step that requires interaction with the phone screen. Choose one method:

### Option A: Wireless Debugging (no USB cable)

1. On the phone: **Settings > Developer Options > Wireless Debugging > Pair device with pairing code**
2. Note the **6-digit code** and the **IP:port**
3. On your workstation:

```bash
# Pair (use the code and port from the phone screen)
adb pair 192.168.1.101:42383 481272

# Find the debug port on the Wireless Debugging screen (different from pair port)
adb connect 192.168.1.101:41777

# Grant all permissions + enable ADB TCP 5555
bash utils/grant-permissions.sh
```

4. On the phone: accept the **"Allow USB debugging?"** dialog
5. Setup the self-bridge from Termux:

```bash
python scripts/connect.py "adb connect localhost:5555"
```

### Option B: USB cable

```bash
# Connect phone via USB
adb devices                        # Accept prompt on phone screen
bash utils/grant-permissions.sh    # Grants everything + enables TCP 5555
```

### What gets granted

| Category | Count | Examples |
|----------|-------|---------|
| Runtime permissions | 44 | Camera, mic, location, SMS, contacts, storage |
| App operations | 40 | Background execution, wake lock, screen overlay |
| Battery whitelist | 3 apps | Termux, Termux:API, Termux:Boot |
| Auto-revoke disabled | 6 perms | Camera, mic, location, SMS, phone, contacts |
| ADB TCP | port 5555 | Self-bridge for UI automation |
| Notification listener | via `cmd notification` | For `termux-notification-list` |

---

## Phase 5: Verify (1 minute)

```bash
make status        # PicoClaw status
make health        # API connectivity
make info          # Full device diagnostic
make verify        # 8-phase resilience verification
```

Or the quick check:

```bash
python scripts/connect.py "~/picoclaw status"
python scripts/connect.py "curl -sf http://127.0.0.1:18790/health"
python scripts/connect.py "~/bin/notifications.sh --count"
```

---

## What's Running After Setup

### Services

| Service | How | Recovery |
|---------|-----|----------|
| SSH server (port 8022) | `sshd` | Watchdog restarts in 60s |
| PicoClaw gateway (port 18790) | tmux session `picoclaw` | Watchdog restarts in 60s |
| ADB self-bridge (port 5555) | `adb connect localhost:5555` | Watchdog reconnects in 60s |
| Cron daemon | `crond` | termux-job-scheduler restarts in 5min |
| Wake lock | `termux-wake-lock` | Reacquired by watchdog |

### Cron Schedule

| Frequency | Job | Purpose |
|-----------|-----|---------|
| Every minute | `watchdog.sh` | Monitor + restart sshd, gateway, ADB |
| Every hour | `media-cleanup.sh` | Delete temp media >60min old |
| Every 6 hours | Disk monitor | Log warning if >90% full |
| Weekly (Sunday) | Session cleanup | Delete sessions >7 days old |
| Every 5 min | `backup-monitor.sh` | OS-level: restart crond/sshd (termux-job-scheduler) |

### 5 Resilience Layers

| Layer | Trigger | Restarts |
|-------|---------|----------|
| Termux:Boot | Device reboot | Everything |
| Watchdog cron | Every 60s | sshd, gateway, ADB |
| termux-job-scheduler | Every 5min | crond, sshd |
| .bashrc guards | Every shell | sshd, crond |
| Wake lock | Permanent | Prevents Android kill |
| LLM auto-failover | Boot + on 429/500/503 errors | LLM provider (Azure → Ollama → Antigravity → Google) |

### Security

| Control | Setting |
|---------|---------|
| Secrets (config, security.yml, keys, PIN) | `chmod 600` |
| Scripts and binaries | `chmod 700` |
| API keys | Only in `security.yml`, not in `config.json` |
| Gateway | Bound to `127.0.0.1` only |
| SSH | MaxAuthTries=3, no empty passwords |

---

## Troubleshooting

### LLM returns 503 or 429 errors

**Cause**: The active LLM provider is rate-limited or experiencing high demand.

**Automatic fix**: The watchdog detects these errors in `gateway.log` and runs `~/bin/auto-failover.sh` to switch providers. This happens within 60 seconds (cooldown: 5 min between failover attempts).

**Manual trigger**:

```bash
# On device
~/bin/auto-failover.sh

# From workstation
make failover                  # Full: switch + restart gateway
make failover-check            # Just check which is best available
```

### Gateway exits silently (writes PID then removes it)

**Cause**: `security.yml` missing API keys in `model_list` section (v0.2.6).

**Fix**: Add API keys to `~/.picoclaw/.security.yml`:

```yaml
model_list:
  azure-gpt4o:0:
    api_keys:
      - "YOUR_AZURE_KEY"
  gpt-oss:120b:0:
    api_keys:
      - "YOUR_OLLAMA_KEY"
```

### `invalid gateway port: 0`

**Cause**: v0.2.6 requires explicit port.

**Fix**: Set `gateway.port` to `18790` in `config.json`.

### ADB self-bridge not connecting after reboot

**Cause**: `persist.adb.tcp.port` requires root to set.

**Fix**: Keep Wireless Debugging enabled in Android Developer Options. The boot script retries `adb connect localhost:5555` on every boot.

### `termux-notification-list` returns empty

**Cause**: Android requires manual toggle for notification listener.

**Fix**: Use `~/bin/notifications.sh` instead (reads via ADB, no permission needed):

```bash
~/bin/notifications.sh --summary   # One-line per notification
~/bin/notifications.sh --unread    # Only unread, as JSON
```

### `aria2c` package not found

**Cause**: Package name is `aria2` in Termux.

### Config auto-migration wipes security.yml

**Cause**: First `picoclaw status` migrates config v1 to v2 and empties `model_list` keys in security.yml.

**Fix**: Always verify `security.yml` after running any PicoClaw command for the first time.

---

## File Layout (after setup)

```
~/
|-- picoclaw              # TLS wrapper script (3 lines)
|-- picoclaw.bin          # Go binary (28 MB, aarch64)
|-- bin/                  # 17 device scripts
|   |-- picoclaw          # Wrapper copy
|   |-- watchdog.sh       # Service monitor (every 60s)
|   |-- backup-monitor.sh # Backup monitor (every 5min)
|   |-- notifications.sh  # Read notifications via ADB
|   |-- transcribe.sh     # STT (Azure/Groq cascade)
|   |-- tts-reply.sh      # TTS (Azure/Edge, 6 voices)
|   |-- ui-control.sh     # 40+ UI commands
|   |-- ensure-unlocked.sh # Auto-unlock with PIN
|   |-- media-capture.sh  # Photo/audio/screenshot
|   |-- device-context.sh # AGENT.md generator
|   +-- ...               # 7 more scripts
|-- media/                # Temp media (cleaned hourly)
|-- storage/              # Symlinks to /sdcard
|-- .picoclaw/
|   |-- config.json       # Main config (v2, no API keys)
|   |-- .security.yml     # API keys + tokens (chmod 600)
|   |-- gateway.log       # Gateway output
|   +-- workspace/
|       |-- AGENT.md      # Agent persona (1000+ lines, auto-generated)
|       |-- sessions/     # Chat sessions
|       |-- skills/       # Installed skills
|       +-- knowledge/    # Knowledge base
|-- .picoclaw_keys        # Voice API keys (chmod 600)
|-- .device_pin           # Screen unlock PIN (chmod 600)
|-- .termux/boot/
|   +-- start-picoclaw.sh # Auto-start on boot
+-- watchdog.log          # Service restart log
```

---

## Quick Reference

```bash
# === From workstation ===
make status                    # PicoClaw status
make info                      # Full device diagnostic
make gateway-restart           # Restart gateway
make agent MSG="Hello"         # Send message
make model M=deepseek-v3.2    # Switch model
make failover                  # Switch to best available LLM provider
make failover-check            # Check which provider is best (dry run)
make verify                    # 8-phase resilience test

# === From Termux (SSH) ===
./picoclaw status              # Status
./picoclaw agent -m "Hello"    # Chat
tmux attach -t picoclaw        # Gateway logs
~/bin/auto-failover.sh         # Switch to best LLM provider
~/bin/notifications.sh --summary  # Read notifications
~/bin/ui-control.sh status     # Screen/battery/app state
~/bin/media-capture.sh photo   # Take photo
crontab -l                     # View cron schedule
cat ~/watchdog.log             # Restart history
cat ~/failover.log             # LLM failover history
```

---

<p align="center">
  <a href="09-remote-devices.md">&larr; Remote Devices</a>
  &nbsp;&nbsp;|&nbsp;&nbsp;
  <a href="../README.md">README</a>
</p>
