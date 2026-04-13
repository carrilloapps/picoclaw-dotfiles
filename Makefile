# =============================================================================
# PicoClaw — Cross-Platform Makefile
# =============================================================================
# Works on: Linux, macOS, Windows (Git Bash / MSYS2 / WSL), Android (Termux)
#
# Prerequisites:
#   - Python 3.6+
#   - pip install paramiko
#   - .env file with credentials (run: make setup)
#
# Optional:
#   - adb (Android Debug Bridge) for USB-based device management
#   - scrcpy for screen mirroring
# =============================================================================

# ---------------------------------------------------------------------------
# Platform detection
# ---------------------------------------------------------------------------
UNAME_S := $(shell uname -s 2>/dev/null || echo Windows)
UNAME_M := $(shell uname -m 2>/dev/null || echo unknown)

# Detect if running inside Termux (Android)
IS_TERMUX := $(shell test -d /data/data/com.termux && echo 1 || echo 0)

# Python binary (prefer python3, fall back to python)
PYTHON := $(shell command -v python3 2>/dev/null || command -v python 2>/dev/null)
PIP := $(shell command -v pip3 2>/dev/null || command -v pip 2>/dev/null)

# ADB / scrcpy (optional)
ADB := $(shell command -v adb 2>/dev/null)
SCRCPY := $(shell command -v scrcpy 2>/dev/null)

# Project paths
SCRIPTS := scripts
ENV_FILE := .env
ENV_EXAMPLE := .env.example

# Default message for agent target
MSG ?= "Hello from Makefile"

# ---------------------------------------------------------------------------
# Help (default target)
# ---------------------------------------------------------------------------
.PHONY: help
help:
	@echo ""
	@echo "  PicoClaw Makefile — Cross-platform device management"
	@echo "  ===================================================="
	@echo ""
	@echo "  Platform: $(UNAME_S) ($(UNAME_M)) | Python: $(PYTHON)"
	@echo "  Termux:   $(if $(filter 1,$(IS_TERMUX)),YES — running on Android,No)"
	@echo "  ADB:      $(if $(ADB),$(ADB),not found)"
	@echo "  scrcpy:   $(if $(SCRCPY),$(SCRCPY),not found)"
	@echo ""
	@echo "  SETUP"
	@echo "    make setup            Create .env from template and install deps"
	@echo "    make install          Install Python dependencies (paramiko)"
	@echo "    make env              Create .env from .env.example"
	@echo "    make check            Verify all prerequisites are met"
	@echo ""
	@echo "  DEPLOYMENT"
	@echo "    make deploy           Deploy TLS wrapper + shell profiles to device"
	@echo "    make deploy-config    Push config template to device"
	@echo "    make setup-voice      Configure Groq Whisper for voice transcription"
	@echo "    make voice-status     Check voice transcription config"
	@echo "    make deploy-context   Generate full device context in AGENT.md"
	@echo ""
	@echo "  GATEWAY (Telegram, Discord, etc.)"
	@echo "    make gateway-start    Start gateway in persistent tmux session"
	@echo "    make gateway-stop     Stop gateway"
	@echo "    make gateway-restart  Restart gateway"
	@echo "    make gateway-status   Check if gateway is running"
	@echo "    make gateway-logs     Show recent gateway logs"
	@echo "    make gateway-follow   Follow gateway logs in real-time"
	@echo ""
	@echo "  LLM PROVIDER FAILOVER"
	@echo "    make failover-check   Check which provider is best available (dry run)"
	@echo "    make failover         Run failover: switch to best available + restart gateway"
	@echo ""
	@echo "  DIAGNOSTICS"
	@echo "    make status           Quick PicoClaw status check"
	@echo "    make info             Full device diagnostic report"
	@echo "    make logs             Show recent PicoClaw session logs"
	@echo "    make health           Connectivity + API health check"
	@echo ""
	@echo "  AGENT"
	@echo '    make agent MSG="Hi"   Send a message to the PicoClaw agent'
	@echo '    make agent-debug MSG="Hi"  Same, with debug logging'
	@echo ""
	@echo "  MODELS"
	@echo "    make models           List available Ollama Cloud models"
	@echo "    make model M=glm-5    Switch to a different model"
	@echo ""
	@echo "  CONFIGURATION"
	@echo "    make config           Dump current config (secrets masked)"
	@echo "    make config-get K=agents.defaults.model_name"
	@echo "    make config-set K=agents.defaults.model_name V=glm-5"
	@echo "    make enable-tool T=exec       Enable a PicoClaw tool"
	@echo "    make enable-channel C=telegram Enable a messaging channel"
	@echo ""
	@echo "  REMOTE SHELL"
	@echo '    make ssh CMD="uname -a"       Run a command on the device'
	@echo "    make shell                     Open interactive SSH session"
	@echo ""
	@echo "  PERMISSIONS (requires USB ADB)"
	@echo "    make grant-permissions  Grant ALL Android permissions to Termux"
	@echo ""
	@echo "  ADB & SCRCPY (optional — requires USB or Wi-Fi ADB)"
	@echo "    make adb-connect      Connect to device via ADB Wi-Fi"
	@echo "    make adb-shell        Open ADB shell"
	@echo "    make adb-push F=file  Push a local file to device ~/  "
	@echo "    make adb-pull F=file  Pull a remote file from device ~/"
	@echo "    make screen           Start scrcpy screen mirror"
	@echo "    make screen-record    Record device screen (5 min max)"
	@echo ""
	@echo "  RESILIENCE, SCRAPING & KNOWLEDGE"
	@echo "    make verify           8-phase resilience verification"
	@echo "    make install-scraping Install web scraping stack on device"
	@echo "    make setup-knowledge  Create knowledge base on device"
	@echo ""
	@echo "  MAINTENANCE"
	@echo "    make clean            Remove Python cache files"
	@echo "    make clean-sessions   Clear PicoClaw session history on device"
	@echo ""

# ---------------------------------------------------------------------------
# Setup & Prerequisites
# ---------------------------------------------------------------------------
.PHONY: setup install env check

setup: env install
	@echo ""
	@echo "[OK] Setup complete. Edit .env with your credentials, then run:"
	@echo "     make check"

install:
	@echo "[*] Installing Python dependencies..."
	$(PIP) install paramiko
	@echo "[OK] Dependencies installed."

env:
	@if [ ! -f $(ENV_FILE) ]; then \
		cp $(ENV_EXAMPLE) $(ENV_FILE); \
		echo "[OK] Created .env from .env.example — edit it with your real values."; \
	else \
		echo "[OK] .env already exists."; \
	fi

check:
	@echo "Checking prerequisites..."
	@echo -n "  Python:   " && $(PYTHON) --version 2>&1 || echo "MISSING"
	@echo -n "  paramiko: " && $(PYTHON) -c "import paramiko; print(paramiko.__version__)" 2>&1 || echo "MISSING (run: make install)"
	@echo -n "  .env:     " && (test -f $(ENV_FILE) && echo "OK" || echo "MISSING (run: make env)")
	@echo -n "  ADB:      " && ($(ADB) version 2>/dev/null | head -1 || echo "not installed (optional)")
	@echo -n "  scrcpy:   " && ($(SCRCPY) --version 2>/dev/null || echo "not installed (optional)")
	@echo ""

# Guard: ensure .env exists before running any device command
.env:
	@echo "ERROR: .env file not found. Run 'make setup' first."
	@exit 1

# ---------------------------------------------------------------------------
# Deployment
# ---------------------------------------------------------------------------
.PHONY: deploy deploy-config

deploy: $(ENV_FILE)
	@echo "[*] Deploying TLS wrapper to device..."
	$(PYTHON) $(SCRIPTS)/deploy_wrapper.py

deploy-config: $(ENV_FILE)
	@echo "[*] Pushing config template to device..."
	$(PYTHON) -c "\
import sys; sys.path.insert(0, 'scripts'); \
from connect import connect; \
ssh = connect(); sftp = ssh.open_sftp(); \
sftp.put('config/config.template.json', '/data/data/com.termux/files/home/.picoclaw/config.json.template'); \
sftp.put('config/security.template.yml', '/data/data/com.termux/files/home/.picoclaw/.security.yml.template'); \
sftp.close(); ssh.close(); \
print('[OK] Templates pushed.')"

# ---------------------------------------------------------------------------
# Voice Transcription
# ---------------------------------------------------------------------------
.PHONY: setup-voice voice-status

setup-voice: $(ENV_FILE)
	@$(PYTHON) $(SCRIPTS)/setup_voice.py

voice-status: $(ENV_FILE)
	@$(PYTHON) $(SCRIPTS)/setup_voice.py --status

deploy-context: $(ENV_FILE)
	@echo "[*] Deploying device-context.sh and generating AGENT.md..."
	@$(PYTHON) -c "\
import sys; sys.path.insert(0, 'scripts'); \
from connect import connect, run; \
ssh = connect(); sftp = ssh.open_sftp(); \
sftp.put('utils/device-context.sh', '/data/data/com.termux/files/home/bin/device-context.sh'); \
sftp.close(); \
run(ssh, 'chmod +x ~/bin/device-context.sh'); \
out, err = run(ssh, '~/bin/device-context.sh', timeout=30); \
print(out); ssh.close()"

# ---------------------------------------------------------------------------
# Gateway (Telegram, Discord, etc.)
# ---------------------------------------------------------------------------
.PHONY: gateway-start gateway-stop gateway-restart gateway-status gateway-logs gateway-follow

gateway-start: $(ENV_FILE)
	@$(PYTHON) $(SCRIPTS)/gateway.py start

gateway-stop: $(ENV_FILE)
	@$(PYTHON) $(SCRIPTS)/gateway.py stop

gateway-restart: $(ENV_FILE)
	@$(PYTHON) $(SCRIPTS)/gateway.py restart

gateway-status: $(ENV_FILE)
	@$(PYTHON) $(SCRIPTS)/gateway.py status

gateway-logs: $(ENV_FILE)
	@$(PYTHON) $(SCRIPTS)/gateway.py logs

gateway-follow: $(ENV_FILE)
	@$(PYTHON) $(SCRIPTS)/gateway.py logs -f

# ---------------------------------------------------------------------------
# LLM provider failover
# ---------------------------------------------------------------------------
.PHONY: failover failover-check

failover: $(ENV_FILE)
	@$(PYTHON) $(SCRIPTS)/connect.py "~/bin/auto-failover.sh"

failover-check: $(ENV_FILE)
	@$(PYTHON) $(SCRIPTS)/connect.py "~/bin/auto-failover.sh --check"

# ---------------------------------------------------------------------------
# Diagnostics
# ---------------------------------------------------------------------------
.PHONY: status info logs health

status: $(ENV_FILE)
	@$(PYTHON) $(SCRIPTS)/connect.py status

info: $(ENV_FILE)
	@$(PYTHON) $(SCRIPTS)/device_info.py

logs: $(ENV_FILE)
	@$(PYTHON) $(SCRIPTS)/connect.py "cat ~/.picoclaw/workspace/sessions/agent_main_main.jsonl 2>/dev/null | tail -50"

health: $(ENV_FILE)
	@echo "[*] Checking SSH connectivity..."
	@$(PYTHON) $(SCRIPTS)/connect.py "echo SSH_OK" && echo "  SSH: OK" || echo "  SSH: FAILED"
	@echo "[*] Checking PicoClaw binary..."
	@$(PYTHON) $(SCRIPTS)/connect.py "test -x ~/picoclaw && echo BINARY_OK" && echo "  Binary: OK" || echo "  Binary: MISSING"
	@echo "[*] Checking Ollama Cloud API..."
	@$(PYTHON) $(SCRIPTS)/connect.py "SSL_CERT_FILE=/data/data/com.termux/files/usr/etc/tls/cert.pem curl -s -o /dev/null -w '%{http_code}' https://ollama.com/v1/models -H \"Authorization: Bearer \$$(grep api_key ~/.picoclaw/config.json | head -1 | sed 's/.*: *\"//;s/\".*//')\"" | grep -q 200 && echo "  Ollama API: OK" || echo "  Ollama API: FAILED"
	@echo "[*] Done."

# ---------------------------------------------------------------------------
# Agent
# ---------------------------------------------------------------------------
.PHONY: agent agent-debug

agent: $(ENV_FILE)
	@$(PYTHON) $(SCRIPTS)/connect.py "SSL_CERT_FILE=/data/data/com.termux/files/usr/etc/tls/cert.pem ./picoclaw agent -s cli:make -m $(MSG) 2>&1"

agent-debug: $(ENV_FILE)
	@$(PYTHON) $(SCRIPTS)/connect.py "SSL_CERT_FILE=/data/data/com.termux/files/usr/etc/tls/cert.pem ./picoclaw agent -d -s cli:make-debug -m $(MSG) 2>&1"

# ---------------------------------------------------------------------------
# Models
# ---------------------------------------------------------------------------
.PHONY: models model

models: $(ENV_FILE)
	@$(PYTHON) $(SCRIPTS)/change_model.py --list

model: $(ENV_FILE)
ifndef M
	@echo "Usage: make model M=<model_name>"
	@echo "Example: make model M=deepseek-v3.2"
	@echo ""
	@echo "Run 'make models' to see available models."
else
	@$(PYTHON) $(SCRIPTS)/change_model.py $(M)
endif

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
.PHONY: config config-get config-set enable-tool enable-channel

config: $(ENV_FILE)
	@$(PYTHON) $(SCRIPTS)/edit_config.py

config-get: $(ENV_FILE)
ifndef K
	@echo "Usage: make config-get K=<dotted.path>"
	@echo "Example: make config-get K=agents.defaults.model_name"
else
	@$(PYTHON) $(SCRIPTS)/edit_config.py get $(K)
endif

config-set: $(ENV_FILE)
ifndef K
	@echo "Usage: make config-set K=<dotted.path> V=<value>"
else ifndef V
	@echo "Usage: make config-set K=$(K) V=<value>"
else
	@$(PYTHON) $(SCRIPTS)/edit_config.py set $(K) $(V)
endif

enable-tool: $(ENV_FILE)
ifndef T
	@echo "Usage: make enable-tool T=<tool_name>"
	@echo "Available tools:"
	@$(PYTHON) $(SCRIPTS)/edit_config.py enable-tool __list__ 2>&1 || true
else
	@$(PYTHON) $(SCRIPTS)/edit_config.py enable-tool $(T)
endif

enable-channel: $(ENV_FILE)
ifndef C
	@echo "Usage: make enable-channel C=<channel_name>"
	@$(PYTHON) $(SCRIPTS)/edit_config.py enable-channel __list__ 2>&1 || true
else
	@$(PYTHON) $(SCRIPTS)/edit_config.py enable-channel $(C)
endif

# ---------------------------------------------------------------------------
# Remote Shell
# ---------------------------------------------------------------------------
.PHONY: ssh shell

ssh: $(ENV_FILE)
ifndef CMD
	@echo "Usage: make ssh CMD=\"<command>\""
	@echo "Example: make ssh CMD=\"uname -a\""
else
	@$(PYTHON) $(SCRIPTS)/connect.py $(CMD)
endif

shell: $(ENV_FILE)
	@echo "[*] Opening interactive SSH session..."
	@echo "    (Credentials are in .env — copy them when prompted)"
	@echo ""
	@. $(ENV_FILE) 2>/dev/null; \
	HOST=$$(grep DEVICE_SSH_HOST $(ENV_FILE) | cut -d= -f2); \
	PORT=$$(grep DEVICE_SSH_PORT $(ENV_FILE) | cut -d= -f2); \
	USER=$$(grep DEVICE_SSH_USER $(ENV_FILE) | cut -d= -f2); \
	echo "Connecting: ssh $$USER@$$HOST -p $$PORT"; \
	ssh $$USER@$$HOST -p $$PORT

# ---------------------------------------------------------------------------
# Permissions (requires USB ADB)
# ---------------------------------------------------------------------------
.PHONY: grant-permissions

grant-permissions:
	@echo "[*] Granting ALL Android permissions to Termux..."
	@bash utils/grant-permissions.sh

# ---------------------------------------------------------------------------
# ADB & scrcpy (optional — for USB or Wi-Fi ADB access)
# ---------------------------------------------------------------------------
.PHONY: adb-connect adb-shell adb-push adb-pull adb-termux screen screen-record

# Device IP for ADB Wi-Fi (read from .env)
_ADB_HOST = $(shell grep DEVICE_SSH_HOST $(ENV_FILE) 2>/dev/null | cut -d= -f2)
_ADB_PORT ?= 5555

adb-connect:
ifndef ADB
	@echo "ERROR: adb not found. Install Android SDK Platform Tools."
	@echo "  Windows: scoop install adb  OR  choco install adb"
	@echo "  macOS:   brew install android-platform-tools"
	@echo "  Linux:   sudo apt install adb"
	@echo "  Termux:  pkg install android-tools"
else
	@echo "[*] Connecting ADB over Wi-Fi to $(_ADB_HOST):$(_ADB_PORT)..."
	@echo "    (Device must have ADB Wi-Fi enabled first)"
	$(ADB) connect $(_ADB_HOST):$(_ADB_PORT)
endif

adb-shell:
ifndef ADB
	@echo "ERROR: adb not found."
else
	$(ADB) shell
endif

adb-push:
ifndef ADB
	@echo "ERROR: adb not found."
else ifndef F
	@echo "Usage: make adb-push F=<local_file>"
else
	$(ADB) push $(F) /data/data/com.termux/files/home/
	@echo "[OK] Pushed $(F) to device ~/."
endif

adb-pull:
ifndef ADB
	@echo "ERROR: adb not found."
else ifndef F
	@echo "Usage: make adb-pull F=<remote_filename>"
	@echo "Example: make adb-pull F=.picoclaw/config.json"
else
	$(ADB) pull /data/data/com.termux/files/home/$(F) ./
	@echo "[OK] Pulled $(F) to current directory."
endif

adb-termux:
ifndef ADB
	@echo "ERROR: adb not found."
else
	@echo "[*] Launching Termux via ADB..."
	$(ADB) shell am start -n com.termux/.app.TermuxActivity
endif

screen:
ifndef SCRCPY
	@echo "ERROR: scrcpy not found. Install it:"
	@echo "  Windows: scoop install scrcpy  OR  choco install scrcpy"
	@echo "  macOS:   brew install scrcpy"
	@echo "  Linux:   sudo apt install scrcpy"
else
	@echo "[*] Starting screen mirror..."
	@echo "    (Device must be connected via USB or ADB Wi-Fi)"
	$(SCRCPY) --window-title "PicoClaw Device" --stay-awake
endif

screen-record:
ifndef SCRCPY
	@echo "ERROR: scrcpy not found."
else
	@echo "[*] Recording screen (Ctrl+C to stop, 5 min max)..."
	$(SCRCPY) --record picoclaw-recording.mp4 --max-fps 30 --time-limit 300
endif

# ---------------------------------------------------------------------------
# Resilience, Scraping & Knowledge
# ---------------------------------------------------------------------------
.PHONY: verify install-scraping setup-knowledge

verify: $(ENV_FILE)
	@echo "[*] Running 8-phase resilience verification..."
	@$(PYTHON) $(SCRIPTS)/verify_resilience.py

install-scraping: $(ENV_FILE)
	@echo "[*] Installing web scraping stack on device..."
	@$(PYTHON) $(SCRIPTS)/install_scraping.py

setup-knowledge: $(ENV_FILE)
	@echo "[*] Setting up knowledge base on device..."
	@$(PYTHON) $(SCRIPTS)/setup_knowledge.py

# ---------------------------------------------------------------------------
# Maintenance
# ---------------------------------------------------------------------------
.PHONY: clean clean-sessions

clean:
	@echo "[*] Cleaning Python cache..."
	@find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
	@find . -type f -name "*.pyc" -delete 2>/dev/null || true
	@echo "[OK] Clean."

clean-sessions: $(ENV_FILE)
	@echo "[*] Clearing PicoClaw session history on device..."
	@$(PYTHON) $(SCRIPTS)/connect.py "rm -f ~/.picoclaw/workspace/sessions/*.jsonl ~/.picoclaw/workspace/sessions/*.json 2>/dev/null && echo CLEARED"
	@echo "[OK] Sessions cleared."
