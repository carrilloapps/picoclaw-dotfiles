# Documentation

Step-by-step guides for deploying and configuring PicoClaw on an Android phone via Termux.

## Guides

| # | Guide | Topics |
| - | ----- | ------ |
| 00 | [Termux & SSH Setup](00-termux-ssh-setup.md) | Termux install, SSH server, find user/IP, connect from workstation |
| 01 | [Hardware Setup](01-hardware-setup.md) | Device requirements, Termux apps, ADB setup |
| 02 | [PicoClaw Installation](02-picoclaw-installation.md) | Binary download, TLS fix, config, AGENT.md generation |
| 03 | [Providers Setup](03-providers-setup.md) | Azure, Ollama, Groq, Antigravity, model switching |
| 04 | [Telegram Integration](04-telegram-integration.md) | Bot setup, voice pipeline (STT + TTS), 6 voices |
| 05 | [Device Control](05-device-control.md) | ADB self-bridge, 44 permissions, UI automation |
| 06 | [Resilience](06-resilience.md) | Boot script, watchdog, heartbeat, auto-recovery |
| 07 | [Skills & MCP](07-skills-and-mcp.md) | 31 skills, 4 MCP servers, 146 tools |
| 08 | [Advanced Features](08-advanced-features.md) | Web scraping, knowledge base, cron jobs, media |
| 09 | [Remote Devices](09-remote-devices.md) | Control Android/iPhone/RPi/USB via OTG |
| 10 | [Complete Setup Guide](10-complete-setup-guide.md) | End-to-end deployment from zero to running |
| 11 | [Power Tools](11-power-tools.md) | 10 specialized tools: PDF, image, RAG, code-run, workflows, webhooks, media |
| 12 | [vs OpenClaw](12-vs-openclaw.md) | Detailed capability comparison and scoring |
| 13 | [Central Memory](13-central-memory.md) | RAG-as-memory architecture, hybrid search, Cloudflare Tunnel |
| 14 | [Self-Administration](14-self-administration.md) | Live channel management + backup/restore/upgrade/pkg via chat |
| 15 | [Webhook Security & Activation](15-webhook-security.md) | Complete security setup + Cloudflare Tunnel activation |
| 16 | [Resilience & Dynamic Webhooks](16-resilience-and-dynamic-webhooks.md) | Reboot recovery, multi-network, chat-created forms/routes |

## Quick Start

The fastest path is the one-click installer — run from Termux:

```bash
curl -sL https://raw.githubusercontent.com/carrilloapps/picoclaw-dotfiles/main/utils/install.sh | bash
```

Then follow the guides above for customization.

## Other Documentation

| File | Description |
| ---- | ----------- |
| [README.md](../README.md) | Project overview and architecture |
| [CLAUDE.md](../CLAUDE.md) | AI session context for Claude Code |
| [SECRETS.md](../SECRETS.md) | Credential management guide |
| [CONTRIBUTING.md](../CONTRIBUTING.md) | How to contribute |
| [scripts/README.md](../scripts/README.md) | Python management scripts |
| [utils/README.md](../utils/README.md) | Device-side scripts and utilities |
| [config/README.md](../config/README.md) | Configuration templates |
| [assets/README.md](../assets/README.md) | Photos and screenshots |

---

<p align="center">
  <a href="../README.md">📋 Back to README</a>
</p>
