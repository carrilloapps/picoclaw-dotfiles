#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# install.sh -- One-click PicoClaw installer for Termux
# =============================================================================
# Run from Termux on an Android phone to set up PicoClaw from scratch.
#
# Usage:
#   curl -sL https://raw.githubusercontent.com/carrilloapps/picoclaw-dotfiles/main/utils/install.sh | bash
#
# Or clone and run:
#   git clone https://github.com/carrilloapps/picoclaw-dotfiles.git
#   cd picoclaw-dotfiles && bash utils/install.sh
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Colors and formatting
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No color

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
HOME_DIR="/data/data/com.termux/files/home"
PREFIX="/data/data/com.termux/files/usr"
PICOCLAW_DIR="$HOME_DIR/.picoclaw"
WORKSPACE_DIR="$PICOCLAW_DIR/workspace"
BIN_DIR="$HOME_DIR/bin"
MEDIA_DIR="$HOME_DIR/media"
BOOT_DIR="$HOME_DIR/.termux/boot"
CERT_PATH="$PREFIX/etc/tls/cert.pem"
PICOCLAW_VERSION="latest"
PICOCLAW_REPO="https://github.com/sipeed/picoclaw"
PICOCLAW_RELEASE_URL="$PICOCLAW_REPO/releases/latest/download/picoclaw_Linux_arm64.tar.gz"
INSTALLER_REPO="https://raw.githubusercontent.com/carrilloapps/picoclaw-dotfiles/main/utils"

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------
info()    { echo -e "${BLUE}[*]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; }
ask()     { echo -en "${CYAN}[?]${NC} $1"; }
divider() { echo -e "${BOLD}---${NC}"; }

confirm() {
    local prompt="$1"
    local default="${2:-y}"
    local yn
    if [ "$default" = "y" ]; then
        ask "$prompt [Y/n] "
    else
        ask "$prompt [y/N] "
    fi
    read -r yn
    yn="${yn:-$default}"
    case "$yn" in
        [Yy]*) return 0 ;;
        *) return 1 ;;
    esac
}

prompt_value() {
    local prompt="$1"
    local default="${2:-}"
    local value
    if [ -n "$default" ]; then
        ask "$prompt [$default]: "
    else
        ask "$prompt: "
    fi
    read -r value
    echo "${value:-$default}"
}

prompt_secret() {
    local prompt="$1"
    local value
    ask "$prompt: "
    read -rs value
    echo ""
    echo "$value"
}

check_command() {
    command -v "$1" >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# Step 0: Welcome banner
# ---------------------------------------------------------------------------
clear 2>/dev/null || true
echo ""
echo -e "${BOLD}${CYAN}"
echo "  ____  _            ____  _                "
echo " |  _ \\(_) ___ ___  / ___|| | __ ___      __"
echo " | |_) | |/ __/ _ \\| |   | |/ _\` \\ \\ /\\ / /"
echo " |  __/| | (_| (_) | |___| | (_| |\\ V  V / "
echo " |_|   |_|\\___\\___/ \\____|_|\\__,_| \\_/\\_/  "
echo ""
echo -e "${NC}${BOLD}  PicoClaw Installer for Termux${NC}"
echo -e "  Ultra-lightweight AI assistant on Android"
echo -e "  ${BLUE}https://github.com/carrilloapps/picoclaw-dotfiles${NC}"
echo ""
divider
echo ""
echo "  This script will set up PicoClaw on this device."
echo "  It will install packages, download the binary, configure"
echo "  API keys, and start the gateway."
echo ""
echo "  You will need:"
echo "    - An Ollama Cloud API key (free at ollama.com)"
echo "    - Optionally: Azure OpenAI, Groq, and Telegram credentials"
echo ""

if ! confirm "Continue with installation?"; then
    echo ""
    info "Installation cancelled."
    exit 0
fi

echo ""

# ---------------------------------------------------------------------------
# Step 1: Check prerequisites
# ---------------------------------------------------------------------------
info "Step 1/15: Checking prerequisites..."

# Must be running in Termux
if [ ! -d "/data/data/com.termux" ]; then
    error "This script must be run inside Termux on Android."
    error "Install Termux from F-Droid: https://f-droid.org/en/packages/com.termux/"
    exit 1
fi

# Check architecture
ARCH=$(uname -m)
if [ "$ARCH" != "aarch64" ]; then
    error "Unsupported architecture: $ARCH. PicoClaw requires aarch64 (ARM64)."
    exit 1
fi

# Check pkg is available
if ! check_command pkg; then
    error "'pkg' not found. Are you running inside Termux?"
    exit 1
fi

# Check basic tools
if ! check_command wget && ! check_command curl; then
    warn "Neither wget nor curl found. Installing curl..."
    pkg install -y curl
fi

success "Prerequisites OK (Termux on $ARCH)"
echo ""

# ---------------------------------------------------------------------------
# Step 2: Install Termux packages
# ---------------------------------------------------------------------------
info "Step 2/15: Installing Termux packages..."
echo "  This may take a few minutes on first run."
echo ""

pkg update -y

# Core packages (required)
CORE_PACKAGES="openssh ca-certificates python nodejs-lts tmux cronie jq curl wget"

# Extended packages (recommended)
EXTENDED_PACKAGES="ffmpeg git gh make clang imagemagick socat rsync zip unzip android-tools termux-api"

# Additional useful packages
EXTRA_PACKAGES="openssl gnupg nmap rclone aria2c sqlite yt-dlp speedtest-go traceroute whois iperf3"

info "Installing core packages..."
pkg install -y $CORE_PACKAGES

if confirm "Install extended packages (ffmpeg, git, imagemagick, etc.)?" "y"; then
    pkg install -y $EXTENDED_PACKAGES
fi

if confirm "Install extra packages (nmap, rclone, yt-dlp, etc.)?" "y"; then
    pkg install -y $EXTRA_PACKAGES 2>/dev/null || warn "Some extra packages may not be available"
fi

# Install Python packages for scraping (optional)
pip install --quiet httpx beautifulsoup4 2>/dev/null || true

success "Packages installed"
echo ""

# ---------------------------------------------------------------------------
# Step 3: Download PicoClaw binary
# ---------------------------------------------------------------------------
info "Step 3/15: Downloading PicoClaw binary..."

cd "$HOME_DIR"

if [ -f "$HOME_DIR/picoclaw.bin" ]; then
    warn "PicoClaw binary already exists at ~/picoclaw.bin"
    if ! confirm "Re-download and overwrite?" "n"; then
        success "Keeping existing binary"
    else
        curl -LO "$PICOCLAW_RELEASE_URL"
        tar xzf picoclaw_Linux_arm64.tar.gz
        mv -f picoclaw picoclaw.bin
        chmod +x picoclaw.bin picoclaw-launcher picoclaw-launcher-tui 2>/dev/null || true
        rm -f picoclaw_Linux_arm64.tar.gz
        success "PicoClaw binary downloaded and extracted"
    fi
elif [ -f "$HOME_DIR/picoclaw" ] && file "$HOME_DIR/picoclaw" | grep -q "ELF"; then
    info "Found PicoClaw binary at ~/picoclaw (renaming to ~/picoclaw.bin)"
    mv picoclaw picoclaw.bin
    success "Binary renamed to ~/picoclaw.bin"
else
    curl -LO "$PICOCLAW_RELEASE_URL"
    tar xzf picoclaw_Linux_arm64.tar.gz
    # If the tarball extracts a binary named 'picoclaw', rename it
    if [ -f "$HOME_DIR/picoclaw" ] && file "$HOME_DIR/picoclaw" | grep -q "ELF"; then
        mv picoclaw picoclaw.bin
    fi
    chmod +x picoclaw.bin picoclaw-launcher picoclaw-launcher-tui 2>/dev/null || true
    rm -f picoclaw_Linux_arm64.tar.gz
    success "PicoClaw binary downloaded and extracted"
fi

echo ""

# ---------------------------------------------------------------------------
# Step 4: Create TLS wrapper
# ---------------------------------------------------------------------------
info "Step 4/15: Creating TLS wrapper..."

cat > "$HOME_DIR/picoclaw" << 'WRAPPER'
#!/data/data/com.termux/files/usr/bin/bash
export SSL_CERT_FILE=/data/data/com.termux/files/usr/etc/tls/cert.pem
exec /data/data/com.termux/files/home/picoclaw.bin "$@"
WRAPPER
chmod +x "$HOME_DIR/picoclaw"

# Also create system-wide SSL fix
mkdir -p "$PREFIX/etc/profile.d"
echo 'export SSL_CERT_FILE=/data/data/com.termux/files/usr/etc/tls/cert.pem' > "$PREFIX/etc/profile.d/ssl-certs.sh"

success "TLS wrapper created at ~/picoclaw"
echo ""

# ---------------------------------------------------------------------------
# Step 5: Create directory structure
# ---------------------------------------------------------------------------
info "Step 5/15: Creating directory structure..."

mkdir -p "$BIN_DIR"
mkdir -p "$MEDIA_DIR"
mkdir -p "$PICOCLAW_DIR"
mkdir -p "$WORKSPACE_DIR"
mkdir -p "$WORKSPACE_DIR/sessions"
mkdir -p "$WORKSPACE_DIR/state"
mkdir -p "$WORKSPACE_DIR/skills"
mkdir -p "$WORKSPACE_DIR/knowledge"
mkdir -p "$WORKSPACE_DIR/memory"
mkdir -p "$BOOT_DIR"

# Copy wrapper to bin for PATH access
cp "$HOME_DIR/picoclaw" "$BIN_DIR/picoclaw"

success "Directory structure created"
echo "  ~/bin/          - Device scripts"
echo "  ~/media/        - Captured media (temp)"
echo "  ~/.picoclaw/    - Configuration and workspace"
echo ""

# ---------------------------------------------------------------------------
# Step 6: Configure shell environment
# ---------------------------------------------------------------------------
info "Step 6/15: Configuring shell environment..."

# .bashrc
cat > "$HOME_DIR/.bashrc" << 'BASHRC'
# PicoClaw shell configuration
export SSL_CERT_FILE=/data/data/com.termux/files/usr/etc/tls/cert.pem
export PATH="$HOME/bin:$PATH"

# Auto-start sshd if not running
pgrep -x sshd >/dev/null 2>&1 || sshd 2>/dev/null
BASHRC

# .bash_profile
cat > "$HOME_DIR/.bash_profile" << 'PROFILE'
# Source .bashrc for login shells
[ -f "$HOME/.bashrc" ] && . "$HOME/.bashrc"
PROFILE

success "Shell environment configured"
echo ""

# ---------------------------------------------------------------------------
# Step 7: Prompt for API keys
# ---------------------------------------------------------------------------
info "Step 7/15: API key configuration"
echo ""
echo "  PicoClaw needs at least one LLM provider to work."
echo "  Ollama Cloud is free and recommended for getting started."
echo ""

# --- Ollama Cloud ---
OLLAMA_KEY=""
OLLAMA_MODEL="deepseek-v3.2"
if confirm "Configure Ollama Cloud (free LLM provider)?" "y"; then
    echo ""
    echo "  Get a free API key at: https://ollama.com"
    echo "  Go to account settings and generate an API key."
    echo ""
    OLLAMA_KEY=$(prompt_secret "Ollama Cloud API key")
    if [ -n "$OLLAMA_KEY" ]; then
        OLLAMA_MODEL=$(prompt_value "Default model" "deepseek-v3.2")
        success "Ollama Cloud configured"
    else
        warn "No Ollama key provided, skipping"
    fi
fi
echo ""

# --- Azure OpenAI ---
AZURE_KEY=""
AZURE_URL=""
AZURE_DEPLOYMENT=""
AZURE_WHISPER=""
if confirm "Configure Azure OpenAI (enterprise, optional)?" "n"; then
    echo ""
    echo "  Get credentials from Azure Portal > OpenAI resource > Keys and Endpoint"
    echo ""
    AZURE_KEY=$(prompt_secret "Azure OpenAI API key")
    if [ -n "$AZURE_KEY" ]; then
        AZURE_URL=$(prompt_value "Azure OpenAI base URL (https://your-resource.openai.azure.com)")
        AZURE_DEPLOYMENT=$(prompt_value "LLM deployment name" "gpt-4o")
        AZURE_WHISPER=$(prompt_value "Whisper deployment name (for STT)" "whisper-1")
        success "Azure OpenAI configured"
    else
        warn "No Azure key provided, skipping"
    fi
fi
echo ""

# --- Groq ---
GROQ_KEY=""
if confirm "Configure Groq (free, fast inference + STT)?" "n"; then
    echo ""
    echo "  Get a free API key at: https://console.groq.com"
    echo ""
    GROQ_KEY=$(prompt_secret "Groq API key")
    if [ -n "$GROQ_KEY" ]; then
        success "Groq configured"
    else
        warn "No Groq key provided, skipping"
    fi
fi
echo ""

# Create ~/.picoclaw_keys for voice scripts
if [ -n "$AZURE_KEY" ] || [ -n "$GROQ_KEY" ]; then
    cat > "$HOME_DIR/.picoclaw_keys" << KEYS
AZURE_OPENAI_API_KEY="${AZURE_KEY}"
AZURE_OPENAI_BASE_URL="${AZURE_URL}"
AZURE_WHISPER_DEPLOYMENT="${AZURE_WHISPER}"
GROQ_KEY="${GROQ_KEY}"
KEYS
    chmod 600 "$HOME_DIR/.picoclaw_keys"
    success "Voice API keys saved to ~/.picoclaw_keys"
fi

# ---------------------------------------------------------------------------
# Step 8: Prompt for Telegram bot token
# ---------------------------------------------------------------------------
info "Step 8/15: Telegram bot configuration"
echo ""

TELEGRAM_TOKEN=""
TELEGRAM_OWNER=""
if confirm "Configure Telegram bot?" "n"; then
    echo ""
    echo "  Create a bot via @BotFather on Telegram."
    echo "  Get your user ID from @userinfobot on Telegram."
    echo ""
    TELEGRAM_TOKEN=$(prompt_secret "Telegram bot token (from @BotFather)")
    if [ -n "$TELEGRAM_TOKEN" ]; then
        TELEGRAM_OWNER=$(prompt_value "Your Telegram user ID (numeric)")
        success "Telegram configured"
    else
        warn "No Telegram token provided, skipping"
    fi
fi
echo ""

# Create security.yml
info "Creating security.yml..."
cat > "$PICOCLAW_DIR/.security.yml" << SECYML
channels:
  telegram:
    token: "${TELEGRAM_TOKEN}"
voice:
  groq_api_key: "${GROQ_KEY}"
  elevenlabs_api_key: ""
SECYML
chmod 600 "$PICOCLAW_DIR/.security.yml"
success "Security config saved"
echo ""

# ---------------------------------------------------------------------------
# Step 9: Prompt for device PIN
# ---------------------------------------------------------------------------
info "Step 9/15: Screen unlock PIN"
echo ""
echo "  PicoClaw can auto-unlock the screen for UI automation."
echo "  The PIN is stored locally at ~/.device_pin (never sent anywhere)."
echo ""

DEVICE_PIN=""
if confirm "Store device screen unlock PIN?" "n"; then
    DEVICE_PIN=$(prompt_secret "Device PIN")
    if [ -n "$DEVICE_PIN" ]; then
        echo "$DEVICE_PIN" > "$HOME_DIR/.device_pin"
        chmod 600 "$HOME_DIR/.device_pin"
        success "PIN saved to ~/.device_pin"
    fi
fi
echo ""

# ---------------------------------------------------------------------------
# Step 10: Create config.json
# ---------------------------------------------------------------------------
info "Step 10/15: Creating PicoClaw configuration..."

# Determine the primary provider and model
PRIMARY_PROVIDER="openai"
PRIMARY_MODEL_NAME="${OLLAMA_MODEL:-deepseek-v3.2}"
PRIMARY_MODEL_ID="openai/${PRIMARY_MODEL_NAME}"
PRIMARY_API_KEY="${OLLAMA_KEY}"
PRIMARY_BASE_URL="https://ollama.com/v1"

if [ -n "$AZURE_KEY" ] && [ -n "$AZURE_URL" ]; then
    PRIMARY_PROVIDER="azure"
    PRIMARY_MODEL_NAME="azure-gpt4o"
    PRIMARY_MODEL_ID="azure/${AZURE_DEPLOYMENT}"
    PRIMARY_API_KEY="$AZURE_KEY"
    PRIMARY_BASE_URL="$AZURE_URL"
fi

# Build providers JSON
PROVIDERS="{\"openai\":{\"base_url\":\"https://ollama.com/v1\",\"api_key\":\"${OLLAMA_KEY}\"}}"
if [ -n "$AZURE_KEY" ]; then
    PROVIDERS=$(echo "$PROVIDERS" | jq --arg key "$AZURE_KEY" --arg url "$AZURE_URL" \
        '. + {"azure":{"base_url":$url,"api_key":$key}}')
fi
if [ -n "$GROQ_KEY" ]; then
    PROVIDERS=$(echo "$PROVIDERS" | jq --arg key "$GROQ_KEY" \
        '. + {"groq":{"base_url":"https://api.groq.com/openai/v1","api_key":$key}}')
fi

# Build model_list
MODEL_LIST="[]"
if [ -n "$AZURE_KEY" ]; then
    MODEL_LIST=$(echo "$MODEL_LIST" | jq --arg name "azure-gpt4o" --arg model "azure/${AZURE_DEPLOYMENT}" \
        --arg key "$AZURE_KEY" --arg base "$AZURE_URL" \
        '. + [{"model_name":$name,"model":$model,"api_key":$key,"api_base":$base}]')
fi
if [ -n "$OLLAMA_KEY" ]; then
    MODEL_LIST=$(echo "$MODEL_LIST" | jq --arg name "$OLLAMA_MODEL" --arg model "openai/${OLLAMA_MODEL}" \
        --arg key "$OLLAMA_KEY" \
        '. + [{"model_name":$name,"model":$model,"api_key":$key,"api_base":"https://ollama.com/v1"}]')
fi

# Build channels
TELEGRAM_ENABLED="false"
TELEGRAM_ALLOW="[]"
if [ -n "$TELEGRAM_TOKEN" ]; then
    TELEGRAM_ENABLED="true"
    if [ -n "$TELEGRAM_OWNER" ]; then
        TELEGRAM_ALLOW="[$TELEGRAM_OWNER]"
    fi
fi

# Assemble config.json
cat > "$PICOCLAW_DIR/config.json" << CONFIGEOF
{
  "version": 1,
  "agents": {
    "defaults": {
      "workspace": "$WORKSPACE_DIR",
      "restrict_to_workspace": false,
      "allow_read_outside_workspace": false,
      "provider": "$PRIMARY_PROVIDER",
      "model_name": "$PRIMARY_MODEL_NAME",
      "max_tokens": 0,
      "max_tool_iterations": 0,
      "summarize_message_threshold": 0,
      "summarize_token_percent": 0,
      "steering_mode": "one-at-a-time",
      "tool_feedback": {
        "enabled": true,
        "max_args_length": 300
      }
    }
  },
  "providers": $(echo "$PROVIDERS" | jq .),
  "channels": {
    "telegram": {
      "enabled": $TELEGRAM_ENABLED,
      "allow_from": $TELEGRAM_ALLOW
    }
  },
  "model_list": $(echo "$MODEL_LIST" | jq .),
  "gateway": {
    "host": "",
    "port": 0,
    "hot_reload": false
  },
  "tools": {
    "exec": { "enabled": true, "allow_remote": true },
    "read_file": { "enabled": true },
    "write_file": { "enabled": true },
    "edit_file": { "enabled": true },
    "append_file": { "enabled": true },
    "list_dir": { "enabled": true },
    "web": { "enabled": true },
    "web_fetch": { "enabled": true },
    "cron": { "enabled": true },
    "skills": { "enabled": true },
    "find_skills": { "enabled": true },
    "install_skill": { "enabled": true },
    "message": { "enabled": true },
    "send_file": { "enabled": true },
    "spawn": { "enabled": true },
    "spawn_status": { "enabled": true },
    "subagent": { "enabled": true },
    "media_cleanup": { "enabled": true },
    "mcp": { "enabled": true }
  },
  "heartbeat": {
    "enabled": false,
    "interval": 0
  },
  "voice": {
    "echo_transcription": false
  }
}
CONFIGEOF

success "config.json created"
echo ""

# ---------------------------------------------------------------------------
# Step 11: Deploy device scripts
# ---------------------------------------------------------------------------
info "Step 11/15: Deploying device scripts to ~/bin/..."

# Check if we're running from a cloned repo
REPO_UTILS=""
if [ -f "./utils/transcribe.sh" ]; then
    REPO_UTILS="./utils"
elif [ -f "../utils/transcribe.sh" ]; then
    REPO_UTILS="../utils"
fi

deploy_script() {
    local name="$1"
    local dest="$2"
    local mode="${3:-755}"

    if [ -n "$REPO_UTILS" ] && [ -f "$REPO_UTILS/$name" ]; then
        cp "$REPO_UTILS/$name" "$dest"
    else
        # Download from GitHub
        curl -sL "$INSTALLER_REPO/$name" -o "$dest" 2>/dev/null
    fi

    if [ -f "$dest" ]; then
        chmod "$mode" "$dest"
        echo "  $dest"
    else
        warn "Failed to deploy $name"
    fi
}

# Deploy all scripts
deploy_script "transcribe.sh"       "$BIN_DIR/transcribe.sh"
deploy_script "tts-reply.sh"        "$BIN_DIR/tts-reply.sh"
deploy_script "adb-shell.sh"        "$BIN_DIR/adb-shell.sh"
deploy_script "adb-enable.sh"       "$BIN_DIR/adb-enable.sh"
deploy_script "ensure-unlocked.sh"  "$BIN_DIR/ensure-unlocked.sh"
deploy_script "ui-control.sh"       "$BIN_DIR/ui-control.sh"
deploy_script "ui-auto.py"          "$BIN_DIR/ui-auto.py"
deploy_script "media-capture.sh"    "$BIN_DIR/media-capture.sh"
deploy_script "media-cleanup.sh"    "$BIN_DIR/media-cleanup.sh"
deploy_script "device-context.sh"   "$BIN_DIR/device-context.sh"
deploy_script "watchdog.sh"         "$BIN_DIR/watchdog.sh"
deploy_script "scrape.sh"           "$BIN_DIR/scrape.sh"
deploy_script "switch-model.sh"     "$BIN_DIR/switch-model.sh"
deploy_script "auth-antigravity.sh" "$BIN_DIR/auth-antigravity.sh"

# Deploy boot script
deploy_script "boot-picoclaw.sh"    "$BOOT_DIR/start-picoclaw.sh"

# Deploy AGENT.md (static fallback — device-context.sh generates the real one later)
if [ ! -f "$WORKSPACE_DIR/AGENT.md" ]; then
    if [ -n "$REPO_UTILS" ] && [ -f "$REPO_UTILS/AGENT.md" ]; then
        cp "$REPO_UTILS/AGENT.md" "$WORKSPACE_DIR/AGENT.md"
        echo "  $WORKSPACE_DIR/AGENT.md (static fallback)"
    fi
fi

success "Device scripts deployed"
echo ""

# ---------------------------------------------------------------------------
# Step 12: Install MCP servers
# ---------------------------------------------------------------------------
info "Step 12/15: Installing MCP servers..."

if confirm "Install MCP servers (filesystem, memory, sequential-thinking, github)?" "y"; then
    npm install -g \
        @modelcontextprotocol/server-filesystem \
        @modelcontextprotocol/server-memory \
        @modelcontextprotocol/server-sequential-thinking \
        @modelcontextprotocol/server-github \
        2>/dev/null || warn "Some MCP servers failed to install (non-critical)"

    # Add MCP config to config.json
    TMPFILE=$(mktemp)
    jq '.tools.mcp.servers = {
        "filesystem": {
            "command": "npx",
            "args": ["-y", "@modelcontextprotocol/server-filesystem",
                     "/data/data/com.termux/files/home",
                     "/data/data/com.termux/files/home/.picoclaw/workspace",
                     "/data/data/com.termux/files/home/media",
                     "/data/data/com.termux/files/usr/tmp"]
        },
        "memory": {
            "command": "npx",
            "args": ["-y", "@modelcontextprotocol/server-memory"]
        },
        "sequential-thinking": {
            "command": "npx",
            "args": ["-y", "@modelcontextprotocol/server-sequential-thinking"]
        },
        "github": {
            "command": "npx",
            "args": ["-y", "@modelcontextprotocol/server-github"]
        }
    }' "$PICOCLAW_DIR/config.json" > "$TMPFILE" && mv "$TMPFILE" "$PICOCLAW_DIR/config.json"

    success "MCP servers installed and configured"
else
    info "Skipping MCP servers"
fi
echo ""

# ---------------------------------------------------------------------------
# Step 13: Setup boot script + watchdog cron
# ---------------------------------------------------------------------------
info "Step 13/15: Setting up boot script and watchdog..."

# Install watchdog cron (idempotent)
(crontab -l 2>/dev/null | grep -v watchdog; echo "* * * * * $BIN_DIR/watchdog.sh >> $HOME_DIR/watchdog.log 2>&1") | crontab -

# Install hourly media cleanup
(crontab -l 2>/dev/null | grep -v media-cleanup; echo "0 * * * * $BIN_DIR/media-cleanup.sh >> /dev/null 2>&1") | crontab -

# Start crond if not running
pgrep crond >/dev/null 2>&1 || crond 2>/dev/null || true

# Start sshd if not running
pgrep -x sshd >/dev/null 2>&1 || sshd 2>/dev/null || true

# Acquire wake lock
termux-wake-lock 2>/dev/null || true

success "Boot script and watchdog configured"
echo "  Watchdog: runs every minute via cron"
echo "  Media cleanup: runs every hour via cron"
echo "  Boot script: ~/.termux/boot/start-picoclaw.sh"
echo ""

# ---------------------------------------------------------------------------
# Step 14: Setup ADB self-bridge and start gateway
# ---------------------------------------------------------------------------
info "Step 14/15: Setting up ADB self-bridge..."

# Try to enable ADB TCP (may fail without prior USB ADB setup)
ADB_OK=false
if check_command adb; then
    adb start-server 2>/dev/null || true
    setprop service.adb.tcp.port 5555 2>/dev/null || true
    (stop adbd 2>/dev/null; start adbd 2>/dev/null) || true
    sleep 2
    if adb connect localhost:5555 2>/dev/null | grep -q "connected"; then
        ADB_OK=true
        success "ADB self-bridge connected (localhost:5555)"
    else
        warn "ADB self-bridge not available (requires prior USB ADB setup)"
    fi
else
    warn "adb not installed -- install with: pkg install android-tools"
fi

echo ""
info "Starting PicoClaw gateway..."

# Check if there's at least one provider configured
if [ -z "$OLLAMA_KEY" ] && [ -z "$AZURE_KEY" ]; then
    warn "No LLM provider configured. Gateway will start but won't process messages."
    warn "Run the installer again or edit ~/.picoclaw/config.json manually."
fi

# Kill any existing gateway
tmux kill-session -t picoclaw 2>/dev/null || true
sleep 1

# Start gateway in tmux
if check_command tmux; then
    tmux new-session -d -s picoclaw \
        "$HOME_DIR/picoclaw.bin gateway > $PICOCLAW_DIR/gateway.log 2>&1"
    sleep 3

    if tmux has-session -t picoclaw 2>/dev/null; then
        success "Gateway started in tmux session 'picoclaw'"
    else
        warn "Gateway may have failed to start. Check: cat ~/.picoclaw/gateway.log"
    fi
else
    warn "tmux not found. Install with: pkg install tmux"
    warn "Start the gateway manually: ./picoclaw gateway"
fi

echo ""

# ---------------------------------------------------------------------------
# Step 15: Grant permissions message
# ---------------------------------------------------------------------------
info "Step 15/15: Android permissions"
echo ""
echo -e "  ${YELLOW}IMPORTANT:${NC} For full device control (camera, mic, UI automation),"
echo "  you need to grant Android permissions from a computer with USB ADB."
echo ""
echo "  Connect the phone via USB to a computer and run:"
echo ""
echo -e "    ${BOLD}bash utils/grant-permissions.sh${NC}"
echo ""
echo "  Or from the PicoClaw repo:"
echo ""
echo -e "    ${BOLD}make grant-permissions${NC}"
echo ""
echo "  This is a one-time setup. PicoClaw works without it, but camera,"
echo "  microphone, and UI automation features will be limited."
echo ""

# ---------------------------------------------------------------------------
# Generate AGENT.md with full device context
# ---------------------------------------------------------------------------
info "Generating AGENT.md with full device capabilities..."

if [ -x "$BIN_DIR/device-context.sh" ]; then
    "$BIN_DIR/device-context.sh" >/dev/null 2>&1 && \
        success "AGENT.md generated with all capabilities" || \
        warn "AGENT.md generation failed. Run manually: ~/bin/device-context.sh"
else
    warn "device-context.sh not found. AGENT.md using static template."
fi

echo ""

# ---------------------------------------------------------------------------
# Success summary
# ---------------------------------------------------------------------------
divider
echo ""
echo -e "${GREEN}${BOLD}  Installation complete!${NC}"
echo ""
echo "  PicoClaw is running on this device."
echo ""
echo -e "  ${BOLD}Quick commands:${NC}"
echo "    ./picoclaw status           # Check status"
echo "    ./picoclaw agent -m 'Hello' # Send a message"
echo "    tmux attach -t picoclaw     # View gateway logs"
echo ""

if [ -n "$TELEGRAM_TOKEN" ]; then
    echo -e "  ${BOLD}Telegram:${NC}"
    echo "    Your bot is active. Send it a message on Telegram!"
    echo ""
fi

echo -e "  ${BOLD}Manage from a workstation:${NC}"
echo "    git clone https://github.com/carrilloapps/picoclaw-dotfiles.git"
echo "    cd picoclaw-dotfiles && make setup"
echo "    make status               # Check device"
echo "    make gateway-restart      # Restart gateway"
echo "    make info                 # Full diagnostic"
echo ""

echo -e "  ${BOLD}Documentation:${NC}"
echo "    https://github.com/carrilloapps/picoclaw-dotfiles"
echo ""

if [ "$ADB_OK" = false ]; then
    echo -e "  ${YELLOW}Note:${NC} ADB self-bridge is not connected."
    echo "  UI automation and camera features require USB ADB setup first."
    echo "  See: https://github.com/carrilloapps/picoclaw-dotfiles/blob/main/docs/05-device-control.md"
    echo ""
fi

echo -e "  ${CYAN}Enjoy your AI assistant!${NC}"
echo ""
