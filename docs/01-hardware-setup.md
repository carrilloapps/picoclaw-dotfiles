# 01 - Hardware Setup

This guide covers the hardware requirements and initial Termux setup for running PicoClaw on an Android phone.

---

## Device Requirements

PicoClaw runs on virtually any Android phone with **Android 11 or later**. The Go binary is compiled for `aarch64` (ARM64), which covers all modern Android devices. Minimum specs:

| Requirement | Minimum | Recommended |
| ----------- | ------- | ----------- |
| Android version | 11 (API 30) | 13+ (API 33+) |
| Architecture | `aarch64` / `arm64-v8a` | Same |
| RAM | 2 GB | 4 GB+ |
| Storage | 500 MB free | 2 GB+ free |
| Network | WiFi (for SSH + API calls) | WiFi + mobile data |

The PicoClaw binary itself is only ~27 MB and uses less than 10 MB of RAM at runtime. All heavy lifting (LLM inference) happens in the cloud.

### Author's Device

This implementation runs on a **Xiaomi Redmi Note 10 Pro** (codename `sweet`):

| Attribute | Value |
| --------- | ----- |
| **Model** | Xiaomi Redmi Note 10 Pro (M2101K6R) |
| **SoC** | Qualcomm Snapdragon 732G (SM7150) |
| **CPU** | Qualcomm Kryo 470 -- 8 cores, big.LITTLE |
| **RAM** | 6 GB LPDDR4X + 2 GB swap |
| **Storage** | 128 GB UFS 2.2 |
| **Display** | 6.67" AMOLED, 1080x2400 |
| **Camera** | 108 MP (back), 16 MP (front) |
| **Android** | 16 (API 36) via PixelOS custom ROM |
| **Kernel** | 4.14.x (SMP PREEMPT) |

Any old phone you have lying around will work. The whole point is to repurpose hardware that would otherwise collect dust.

---

## Step 1: Install Termux

Install **Termux** from [F-Droid](https://f-droid.org/en/packages/com.termux/), not from the Play Store. The Play Store version is outdated and will not work.

```
https://f-droid.org/en/packages/com.termux/
```

After installing, open Termux and run the initial setup:

```bash
pkg update && pkg upgrade -y
pkg install openssh
```

### Install Companion Apps

These are also from F-Droid:

| App | F-Droid Link | Purpose |
| --- | ------------ | ------- |
| **Termux:Boot** | [Link](https://f-droid.org/en/packages/com.termux.boot/) | Auto-start services on device boot |
| **Termux:API** | [Link](https://f-droid.org/en/packages/com.termux.api/) | Access Android hardware (camera, mic, sensors, GPS, SMS, calls) |

After installing Termux:Boot, open it once so Android registers it as a boot receiver.

After installing Termux:API, install the CLI bridge inside Termux:

```bash
pkg install termux-api
```

---

## Step 2: SSH Server Setup

Set up SSH so you can manage the device remotely from your workstation:

```bash
# Set a password for SSH authentication
passwd

# Start the SSH server
sshd

# Find your device IP
ifconfig | grep 'inet ' | grep -v 127.0.0.1
```

The SSH server listens on port **8022** by default in Termux.

### Test the Connection

From your workstation:

```bash
ssh <user>@<device-ip> -p 8022
```

Or using Python (recommended for Windows, which lacks `sshpass`):

```python
import paramiko

ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect('<device-ip>', port=8022, username='<user>', password='<password>')
stdin, stdout, stderr = ssh.exec_command('uname -a')
print(stdout.read().decode())
ssh.close()
```

---

## Step 3: Install Essential Packages

Install the core tools PicoClaw and its scripts depend on:

```bash
pkg install -y \
    python nodejs tmux cronie jq curl wget ffmpeg \
    git gh make clang imagemagick socat rsync \
    nmap openssl gnupg zip unzip android-tools
```

For a complete environment (262 packages as in the author's setup), see the `full_deploy.py` script which handles all package installation automatically.

---

## Step 4: Grant Android Permissions

PicoClaw's device control features (camera, microphone, location, SMS, calls, UI automation) require Android permissions granted to Termux. This requires a one-time USB ADB connection from a computer:

```bash
# From your computer (with adb installed), with the phone connected via USB:
bash utils/grant-permissions.sh
```

This grants 44 runtime permissions and 17 appops to Termux, Termux:API, and Termux:Boot. See [05-device-control.md](05-device-control.md) for the full list.

---

## Quick Alternative: One-Click Installer

If you want to skip the manual setup in the following guides, the one-click installer handles everything from this point forward (packages, binary, config, scripts, gateway):

```bash
curl -sL https://raw.githubusercontent.com/carrilloapps/picoclaw-dotfiles/main/utils/install.sh | bash
```

---

## Next Steps

With Termux set up and SSH working, proceed to [02 - PicoClaw Installation](02-picoclaw-installation.md).
