# 01 — Hardware Setup

## Device Requirements

PicoClaw runs on any **Android 11+** phone with `aarch64` (ARM64). The binary is ~27 MB and uses <10 MB RAM — all LLM inference happens in the cloud.

| Requirement | Minimum | Recommended |
| ----------- | ------- | ----------- |
| Android | 11 (API 30) | 13+ (API 33+) |
| Architecture | `aarch64` / `arm64-v8a` | Same |
| RAM | 2 GB | 4+ GB |
| Storage | 500 MB free | 2+ GB free |
| Network | WiFi | WiFi + mobile data |

### Author's Device

| | |
| --- | --- |
| **Model** | Xiaomi Redmi Note 10 Pro (M2101K6R, codename `sweet`) |
| **SoC** | Qualcomm Snapdragon 732G (SM7150), 8-core Kryo 470 |
| **RAM** | 6 GB LPDDR4X + 2 GB swap |
| **Storage** | 128 GB UFS 2.2 |
| **Display** | 6.67" AMOLED, 1080×2400 |
| **Camera** | 108 MP back, 16 MP front |
| **Android** | 16 (API 36) via PixelOS |

---

## Quick Setup (Recommended)

Install the three Termux apps from **F-Droid** (NOT Play Store):

| App | Link | Purpose |
| --- | ---- | ------- |
| **Termux** | [F-Droid](https://f-droid.org/en/packages/com.termux/) | Terminal + Linux environment |
| **Termux:Boot** | [F-Droid](https://f-droid.org/en/packages/com.termux.boot/) | Auto-start on device boot |
| **Termux:API** | [F-Droid](https://f-droid.org/en/packages/com.termux.api/) | Camera, mic, GPS, SMS, sensors |

> Open Termux:Boot once after installing so Android registers it.

Then run the **one-click installer** — it handles SSH, packages, PicoClaw binary, config, scripts, and gateway:

```bash
pkg update && pkg upgrade -y && pkg install -y curl
curl -sL https://raw.githubusercontent.com/carrilloapps/picoclaw-dotfiles/main/utils/install.sh | bash
```

The installer will:
1. Install all 262 packages (openssh, python, node, ffmpeg, nmap, git, etc.)
2. Download and configure PicoClaw with TLS wrapper
3. Prompt you for API keys (Azure, Ollama, Groq)
4. Prompt for Telegram bot token
5. Set up SSH server, boot script, watchdog, and cron jobs
6. Start the gateway

After it finishes, SSH is running on port **8022**. Find your IP:

```bash
ifconfig | grep 'inet ' | grep -v 127.0.0.1
```

Test from your workstation: `ssh <user>@<device-ip> -p 8022`

---

## Granting Android Permissions

PicoClaw's device control (camera, mic, location, SMS, UI automation) needs Android permissions granted via USB ADB from a computer **one time**:

```bash
# From your computer, phone connected via USB:
git clone https://github.com/carrilloapps/picoclaw-dotfiles.git
bash picoclaw-dotfiles/utils/grant-permissions.sh
```

This grants 44 runtime permissions + 17 appops to all Termux apps. Details in [05 — Device Control](05-device-control.md).

---

## Manual Setup (Advanced)

<details>
<summary>If you prefer step-by-step instead of the one-click installer...</summary>

### SSH Server

```bash
pkg install -y openssh
passwd          # Set a password
sshd            # Start SSH server (port 8022)
```

### Essential Packages

```bash
pkg install -y \
    python nodejs tmux cronie jq curl wget ffmpeg \
    git gh make clang imagemagick socat rsync \
    nmap openssl gnupg zip unzip android-tools \
    termux-api ca-certificates
```

### Termux:API CLI

```bash
pkg install -y termux-api
```

Then continue to [02 — PicoClaw Installation](02-picoclaw-installation.md).

</details>

---

## ADB Setup (Required for Full Device Control)

ADB gives PicoClaw elevated Android shell access (uid=2000) for UI automation, screenshots, app control, and permissions grants. Initial setup requires a USB cable; after that, everything runs wirelessly over loopback.

### On the Phone (One Time)

1. **Settings → About Phone** — tap "Build number" 7 times to enable Developer Options.
2. **Settings → System → Developer Options** — enable:
   - **USB Debugging**
   - **Wireless Debugging** (Android 11+)
3. Connect the phone via USB cable to your computer.

### On the Computer

Install ADB:

```bash
# Windows
scoop install adb
# macOS
brew install android-platform-tools
# Linux
sudo apt install adb
# Termux (on the device itself)
pkg install android-tools
```

Verify and grant permissions:

```bash
adb devices              # Phone should appear — accept the prompt on screen
bash utils/grant-permissions.sh   # Grant 44 runtime permissions + 17 appops
adb tcpip 5555           # Enable wireless ADB (so USB cable can be unplugged)
```

### PicoClaw's ADB Self-Bridge

After first setup, PicoClaw connects to itself via `adb connect localhost:5555` (loopback — no USB or network exposure). The boot script re-enables this on every reboot. The watchdog reconnects it if it drops. No USB cable required after initial setup.

---

## Remote Management from a Workstation (Optional)

If you want to control the device from your PC using the Makefile and Python scripts:

```bash
# Clone the repo on your workstation
git clone https://github.com/carrilloapps/picoclaw-dotfiles.git
cd picoclaw-dotfiles
pip install paramiko
cp .env.example .env
# Edit .env with your device IP, SSH port, credentials, and API keys
```

Then use the Makefile — all commands run over SSH, no USB needed:

```bash
make help               # Show all 30+ available commands
make status             # Check PicoClaw status
make info               # Full device diagnostic
make deploy             # Deploy TLS wrapper + scripts
make gateway-start      # Start Telegram gateway
make gateway-restart    # Restart gateway
make agent MSG="Hello"  # Send message to agent
make verify             # Run 8-phase resilience test
make models             # List available LLM models
make config             # Show current config (secrets masked)
```

Remote management is completely optional — the phone runs autonomously after `install.sh` finishes.

---

## Next Steps

→ [02 — PicoClaw Installation](02-picoclaw-installation.md)
