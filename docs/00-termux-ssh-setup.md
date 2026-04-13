# 00 — Termux & SSH Setup

Complete walkthrough for preparing an Android phone from zero: installing Termux, enabling SSH, finding your credentials, and connecting from a workstation. This is the prerequisite for all other guides.

## What You Need

| Item | Details |
|------|---------|
| **Android phone** | Android 11+ with `aarch64` (ARM64) — virtually all phones from 2018+ |
| **WiFi network** | Phone and workstation on the **same** WiFi network |
| **Workstation** | Windows, macOS, or Linux with Python 3.8+ |
| **F-Droid** | App store for installing Termux (NOT Google Play) |

> **Why not Google Play?** Google Play's Termux is outdated (v0.101) and broken. The F-Droid version (v0.118+) is actively maintained and receives updates.

---

## Step 1: Install Termux from F-Droid

### 1.1 Install F-Droid

1. Open the browser on your phone
2. Go to **https://f-droid.org**
3. Tap **"Download F-Droid"** — it downloads an APK
4. Open the downloaded APK and install it
   - If prompted, enable **"Install from unknown sources"** for your browser

### 1.2 Install the three Termux apps

Open F-Droid and install these three apps (search by name):

| App | Package | Purpose |
|-----|---------|---------|
| **Termux** | `com.termux` | Terminal emulator + Linux environment |
| **Termux:Boot** | `com.termux.boot` | Auto-start scripts on device boot |
| **Termux:API** | `com.termux.api` | Access camera, mic, GPS, SMS, sensors |

> **Important**: Open **Termux:Boot** once after installing so Android registers it. You don't need to do anything inside it — just open and close.

### 1.3 First time in Termux

Open the **Termux** app. You'll see a terminal with a `$` prompt. This is a full Linux environment running on your phone — you can install packages, run servers, and execute scripts.

```
Welcome to Termux!

Docs:       https://termux.dev/docs
Community:  https://termux.dev/community
$ _
```

Update the package repository first:

```bash
pkg update && pkg upgrade -y
```

This may take a few minutes. Accept any prompts with `Y`.

---

## Step 2: Install OpenSSH

SSH (Secure Shell) lets you connect to the phone's terminal from your workstation — so you can type commands on your computer and they execute on the phone.

```bash
pkg install -y openssh
```

This installs:
- `sshd` — the SSH **server** (runs on the phone, listens for connections)
- `ssh` — the SSH **client** (for connecting to other machines)
- `ssh-keygen`, `scp`, `sftp` — key management and file transfer tools

---

## Step 3: Set a Password

Termux doesn't have a password by default. You need one for SSH login:

```bash
passwd
```

It will prompt:

```
New password: _
Retype new password: _
New password was successfully set.
```

Type a password and press Enter (the characters won't appear on screen — that's normal). **Remember this password** — you'll need it to connect from your workstation.

> **Tip**: Use a strong but typeable password. You'll enter it often. Example: `MyDevice2024!`

---

## Step 4: Start the SSH Server

```bash
sshd
```

That's it — no output means it started successfully. The SSH server is now listening on **port 8022**.

### Why port 8022 and not 22?

Standard SSH uses port 22, but on Android only `root` can bind ports below 1024. Termux runs as a regular user, so it uses **8022** instead. This is a Termux convention — all tools and scripts in this project expect port 8022.

### Verify it's running

```bash
pgrep sshd
```

You should see one or more process IDs (numbers). If nothing appears, run `sshd` again.

---

## Step 5: Find Your Username

```bash
whoami
```

Output:

```
u0_a39
```

The username in Termux is **always** in the format `u0_aNN` where `NN` is a number assigned by Android when the app is installed. Common examples: `u0_a25`, `u0_a39`, `u0_a150`.

> **This number changes** if you uninstall and reinstall Termux. Always verify it with `whoami` after a fresh install.

You can also see it in the shell prompt — it's the part before `@`:

```
u0_a39@localhost ~ $
```

---

## Step 6: Find Your IP Address

The phone needs to be connected to WiFi. Run:

```bash
ifconfig
```

Look for the `wlan0` section — that's your WiFi interface:

```
wlan0: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 1500
        inet 192.168.1.101  netmask 255.255.255.0  broadcast 192.168.1.255
        inet6 fe80::xxxx:xxxx:xxxx:xxxx  prefixlen 64  scopeid 0x20<link>
        ether xx:xx:xx:xx:xx:xx  txqueuelen 3000  (Ethernet)
```

Your IP is the `inet` value: **`192.168.1.101`** in this example.

### Alternative methods

```bash
# Compact — shows only IP addresses
ifconfig wlan0 | grep 'inet '

# Using ip command
ip addr show wlan0 | grep 'inet '

# Quick one-liner
hostname -I
```

### If ifconfig is not found

```bash
pkg install -y net-tools
ifconfig
```

### Understanding the IP

| Part | Meaning |
|------|---------|
| `192.168.1.xxx` | Your local network (same for all devices on your WiFi) |
| `.101` | This specific device's address on the network |

> **The IP can change** when the phone reconnects to WiFi (DHCP assigns dynamic IPs). If your connection stops working, check the IP again with `ifconfig`. For a stable IP, assign a static IP in your router's settings.

---

## Step 7: Test the Connection Locally

Before connecting from your workstation, verify SSH works on the phone itself:

```bash
ssh localhost -p 8022
```

It will ask:

```
Are you sure you want to continue connecting (yes/no)? yes
u0_a39@localhost's password: _
```

Type `yes`, then your password. If you get a new shell prompt, SSH is working. Type `exit` to return.

---

## Step 8: Connect from Your Workstation

Now connect from your computer. You need three things:

| Value | How to find it | Example |
|-------|---------------|---------|
| **IP** | `ifconfig` on phone (Step 6) | `192.168.1.101` |
| **Port** | Always 8022 in Termux | `8022` |
| **User** | `whoami` on phone (Step 5) | `u0_a39` |
| **Password** | What you set in Step 3 | `MyDevice2024!` |

### From Windows (PowerShell or CMD)

```powershell
ssh u0_a39@192.168.1.101 -p 8022
```

### From macOS / Linux

```bash
ssh u0_a39@192.168.1.101 -p 8022
```

### If you don't have `ssh` command (older Windows)

Install OpenSSH client:

```powershell
# PowerShell (as Administrator)
Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0
```

Or use [PuTTY](https://putty.org): Host = your IP, Port = 8022.

---

## Step 9: Configure the `.env` File

The PicoClaw project uses a `.env` file to store all connection details and API keys. This file stays on your workstation and is **never committed to git**.

### 9.1 Create the file

```bash
cd picoclaw-dotfiles
cp .env.example .env
```

### 9.2 Fill in SSH credentials

Open `.env` in a text editor and set the values from Steps 5-6:

```bash
# Termux / Device SSH
DEVICE_SSH_HOST=192.168.1.101      # From ifconfig (Step 6)
DEVICE_SSH_PORT=8022                # Always 8022 in Termux
DEVICE_SSH_USER=u0_a39              # From whoami (Step 5)
DEVICE_SSH_PASSWORD=MyDevice2024!   # From passwd (Step 3)
```

### 9.3 Other credentials

The `.env` file also holds API keys and device info. Fill these in as you follow the later guides:

| Variable | Guide | Required? |
|----------|-------|-----------|
| `OLLAMA_API_KEY` | [03 - Providers](03-providers-setup.md) | At least one provider |
| `AZURE_OPENAI_API_KEY` | [03 - Providers](03-providers-setup.md) | Optional |
| `GROQ_API_KEY` | [03 - Providers](03-providers-setup.md) | Optional (needed for voice) |
| `TELEGRAM_BOT_TOKEN` | [04 - Telegram](04-telegram-integration.md) | For Telegram integration |
| `DEVICE_PIN` | [05 - Device Control](05-device-control.md) | For auto-unlock |

---

## Step 10: Test with Python (paramiko)

All PicoClaw management scripts use Python's `paramiko` library for SSH (because Windows doesn't have `sshpass` for password-based SSH scripting).

### 10.1 Install dependencies

```bash
pip install paramiko python-dotenv
```

### 10.2 Test the connection

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
stdin, stdout, stderr = ssh.exec_command('echo OK && whoami && uname -a')
print(stdout.read().decode('utf-8', errors='replace'))
ssh.close()
```

Expected output:

```
OK
u0_a39
Linux localhost 4.14.xxx ... aarch64 Android
```

### 10.3 Or use the project's connect.py

```bash
python scripts/connect.py status
# If PicoClaw is not installed yet, this will error — that's expected.

python scripts/connect.py "whoami && uname -m"
# This should work and return your username and architecture.
```

---

## Step 11: Make SSH Persistent

By default, `sshd` stops when you close Termux. To keep it running:

### Auto-start sshd in .bashrc

Add to `~/.bashrc` on the phone:

```bash
# Start sshd if not running
if ! pgrep -x sshd > /dev/null; then
    sshd
fi
```

### Auto-start on boot (Termux:Boot)

Create the boot script:

```bash
mkdir -p ~/.termux/boot
cat > ~/.termux/boot/start-sshd.sh << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
sshd
EOF
chmod +x ~/.termux/boot/start-sshd.sh
```

Now SSH starts automatically when the phone boots — even without opening the Termux app.

> **Note**: The full PicoClaw installer (`install.sh`) sets up a more complete boot script that also starts the gateway, watchdog, ADB bridge, and wake lock. This simple version is just for SSH.

---

## Quick Reference

Once everything is set up, here's your cheat sheet:

```bash
# === On the phone (Termux) ===
whoami                              # Show username (u0_aNN)
ifconfig wlan0 | grep 'inet '      # Show IP address
sshd                                # Start SSH server
pgrep sshd                         # Check if SSH is running
passwd                              # Change password

# === From your workstation ===
ssh u0_a39@192.168.1.101 -p 8022   # Connect via SSH
python scripts/connect.py "cmd"     # Run command via Python
make status                         # PicoClaw status (after install)
```

---

## Troubleshooting

### "Connection refused" on port 8022

**Cause**: `sshd` is not running on the phone.

**Fix**: Open Termux on the phone and run:
```bash
sshd
```

### "Connection timed out"

**Cause**: Wrong IP, or phone and workstation are on different networks.

**Fix**:
1. Verify the phone is connected to WiFi (not mobile data)
2. Run `ifconfig` on the phone to get the current IP
3. Make sure your workstation is on the **same** WiFi network
4. Update `DEVICE_SSH_HOST` in `.env` with the new IP

### "Permission denied (password)"

**Cause**: Wrong username or password.

**Fix**:
1. Run `whoami` on the phone to verify the username
2. Run `passwd` on the phone to reset the password
3. Update `DEVICE_SSH_USER` and `DEVICE_SSH_PASSWORD` in `.env`

### IP changed after reboot

**Cause**: DHCP assigned a new IP.

**Fix**: Run `ifconfig` on the phone, update `.env` with the new IP.

**Permanent fix**: Assign a static IP in your router's DHCP settings (bind the phone's MAC address to a fixed IP). The MAC address is shown in `ifconfig` as the `ether` value.

### "No route to host"

**Cause**: Phone's WiFi is off or phone is in sleep mode.

**Fix**:
1. Wake the phone screen
2. Verify WiFi is connected
3. Disable battery optimization for Termux: **Settings > Apps > Termux > Battery > Unrestricted**

### `ifconfig` command not found

```bash
pkg install -y net-tools
```

### Username changed after reinstalling Termux

Android assigns a new `u0_aNN` user ID each time Termux is installed. Run `whoami` and update `.env`.

---

## What Happens Next

With SSH working, you're ready to install PicoClaw. There are two paths:

| Method | When to use |
|--------|-------------|
| **[One-click installer](01-hardware-setup.md#quick-setup-recommended)** | Fresh setup, run `install.sh` on the phone or via SSH |
| **[Remote deploy](02-picoclaw-installation.md#full-automated-deployment)** | Deploy from workstation with `full_deploy.py` |

Both methods require SSH to be working — which you've just set up.

---

<p align="center">
  &nbsp;&nbsp;
  <a href="../README.md">README</a>
  &nbsp;&nbsp;|&nbsp;&nbsp;
  <a href="01-hardware-setup.md">Hardware Setup &rarr;</a>
</p>
