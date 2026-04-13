# 12 — PicoClaw Dotfiles vs OpenClaw

Comprehensive capability comparison between **PicoClaw Dotfiles for Android** (this project) and **OpenClaw** (the reference AI assistant platform).

Legend: V = full support, ~ = partial, X = missing

---

## 1. Core Runtime

| Capability | OpenClaw | PicoClaw Dotfiles |
|------------|:--------:|:-----------------:|
| Single binary deployment | X (Node.js 24+) | V (Go, ~28 MB) |
| RAM footprint | ~1 GB typical | <20 MB idle |
| Boot time | 5-15 s | <1 s |
| Architectures | x64, arm64 | x64, arm64, RISC-V, MIPS, LoongArch |
| Mobile (Android/Termux) | Limited | V **Native** |
| IoT/embedded capable | X | V (runs on $10 hardware) |
| Self-healing watchdog | Container orchestrator | V 5-layer resilience |
| Auto-failover between LLM providers | V (auth rotation) | V `auto-failover.sh` + watchdog |
| Offline binary install | X (needs npm registry) | V `curl \| bash` |

---

## 2. LLM Providers

| Provider | OpenClaw | PicoClaw |
|---------|:--------:|:--------:|
| OpenAI | V | V |
| Anthropic Claude | V | V |
| Google AI Studio (Gemini) | V | V |
| Azure OpenAI | V | V |
| AWS Bedrock | ~ | V (build tag) |
| Groq | V | V |
| Ollama (Cloud + local) | V | V |
| Mistral / Cerebras / NIM | V | V |
| OpenRouter / DeepSeek | V | V |
| Qwen / GLM / Zhipu / Moonshot / Kimi | ~ | V |
| Xiaomi MiMo | X | V |
| GitHub Copilot OAuth | V | V |
| Antigravity (Google OAuth) | X | V |
| **Total providers** | ~18 | **30+** |

---

## 3. Chat Channels

| Channel | OpenClaw | PicoClaw |
|---------|:--------:|:--------:|
| Telegram | V | V |
| Discord | V | V |
| WhatsApp | V | V |
| Slack | V | V |
| Matrix | V | V |
| IRC | V | V |
| WeChat / WeCom | V | V |
| Feishu / Lark | V | V |
| LINE | V | V |
| QQ | X | V |
| DingTalk | X | V |
| OneBot protocol | X | V |
| Signal | V | X (roadmap) |
| iMessage | V | X |
| Google Chat | V | X |
| MS Teams | V | X |
| Mattermost | V | X |
| Twitch | V | X |

---

## 4. Agent Tools (first-class)

| Tool | OpenClaw | PicoClaw |
|------|:--------:|:--------:|
| exec (shell) | V | V (with `allow_remote`) |
| read/write/edit/append file | V | V |
| list_dir | V | V |
| web_search | V (5 engines) | V (7 engines) |
| web_fetch | V + Firecrawl | V + `scrape.sh` cascade |
| **browser (CDP)** | V (full control) | **V** `browser-tool.sh` (chromium-browser) |
| **image analysis / OCR** | V | **V** `image-tool.sh` (ImageMagick + tesseract) |
| **PDF analysis** | V | **V** `pdf-tool.sh` (poppler + OCR) |
| **document conversion** | ~ (skill) | **V** `document-tool.sh` (pandoc, 40+ formats) |
| **media download/edit** | ~ (skill) | **V** `media-tool.sh` (yt-dlp + ffmpeg, 1000+ sites) |
| **QR code gen/scan** | ~ (skill) | **V** `qr-tool.sh` |
| **code interpreter** | ~ (skill) | **V** `code-run.sh` (16 languages) |
| **RAG** | ~ (skill, QMD) | **V** `rag-tool.sh` (BM25 + Gemini embeddings hybrid) |
| **workflow engine** | V (Lobster) | **V** `workflow.sh` |
| **wakeups/scheduling** | V | V `wakeup.sh` + cron |
| **webhook server** | Gmail PubSub | **V** `webhook-server.py` (Flask + HMAC + CF Access) |
| cron | V | V |
| send_file | ~ (inline) | V |
| media_cleanup | X | V |
| message channel ops | V | V |
| spawn / subagent | V | V |
| MCP client | V | V |
| MCP server | V | X (roadmap) |

---

## 5. Code Execution (PicoClaw wins here)

| Language | OpenClaw | PicoClaw `code-run.sh` |
|----------|:--------:|:----------------------:|
| Python 3 | ~ (skill) | V |
| Node.js / JavaScript | ~ (skill) | V |
| **Deno / TypeScript** | X | **V** |
| Bash | V (exec) | V |
| **Go** | X | **V** |
| **Rust** | X | **V** |
| **PHP 8** | X | **V** |
| **Ruby** | X | **V** |
| **Perl** | X | **V** |
| **Lua** | X | **V** |
| **Java** | X | **V** |
| **Kotlin** | X | **V** |
| **Swift** | X | **V** |
| **Elixir** | X | **V** |
| **Zig** | X | **V** |
| SQL (SQLite) | ~ (MCP) | V |
| AWK / sed | V (exec) | V |
| Safe eval | X | V |

**PicoClaw supports 16+ languages natively.** OpenClaw requires skills or extensions for anything beyond JS/Python.

---

## 6. Device Control (Android-specific)

| Capability | OpenClaw | PicoClaw |
|------------|:--------:|:--------:|
| ADB self-bridge | X | V (localhost:5555, port auto-detection) |
| 44 runtime permissions | X | V (`grant-permissions.sh`) |
| UI automation (tap/swipe/type) | iOS/Android companion apps | V `ui-control.sh` (40+ commands) |
| Screen capture | Via companion app | V `media-capture.sh screenshot` |
| Camera (photo/video) | V (via node) | V (Termux:API + ADB) |
| Microphone recording | V | V |
| Notifications (read) | V (via node) | V `notifications.sh` (via ADB dumpsys) |
| SMS (read/send) | V | V (Termux:API) |
| GPS / location | V (via node) | V (Termux:API) |
| Sensors (accelerometer, etc.) | V | V (Termux:API, 70+ commands) |
| Bluetooth / WiFi scan | X | V (Termux:API) |
| Battery / power management | V | V |
| Auto-unlock with PIN | X | V `ensure-unlocked.sh` |

---

## 7. Voice Pipeline

| Feature | OpenClaw | PicoClaw |
|---------|:--------:|:--------:|
| STT (transcription) | V Whisper | V `transcribe.sh` (Azure + Groq cascade) |
| TTS providers | V ElevenLabs, Edge, MiniMax, OpenAI | V Azure + Edge TTS (6 voices ES/EN) |
| Wake word detection | V (macOS/iOS) | X |
| Continuous talk mode | V | X |
| Push-to-talk | V | X |
| In-chat TTS directives | V `[[tts:...]]` | ~ |
| Voice message auto-reply | V | V (agent uses `tts-reply.sh`) |

---

## 8. Security & Hardening

| Feature | OpenClaw | PicoClaw |
|---------|:--------:|:--------:|
| Secrets separate from config | Via env | V `security.yml` (chmod 600) |
| DM pairing policy | V (code-based) | X |
| Per-channel allowlist | V | V (Telegram) |
| Sandbox mode (tools) | V (per agent) | V (workspace restriction + exec allow/deny) |
| Elevated shell toggle | V | V (`allow_remote`) |
| SSRF protection | V | V (scrape.sh deny patterns) |
| Gateway network binding | Configurable | V 127.0.0.1 only |
| SSH hardening | Host-level | V (MaxAuthTries 3, keepalive) |
| File permissions | N/A | V 600 secrets, 700 scripts |
| **Audit log** | ~ | **V** `audit-log.sh` (JSON-Lines) |
| **Webhook HMAC verification** | Custom | **V** (GitHub, GitLab, generic) |
| **Cloudflare Access JWT** | X | **V** |
| **Cloudflare Tunnel** (zero-trust) | X | **V** `cloudflare-tool.sh` |
| **Rate limiting** | ~ (custom) | **V** (per-IP sliding window) |
| **IP allowlist** | Per-channel | **V** (on webhook server) |
| **Doctor/diagnostics** | V | V `make info` + `verify_resilience.py` |

---

## 9. Automation & Orchestration

| Feature | OpenClaw | PicoClaw |
|---------|:--------:|:--------:|
| Cron jobs | V | V (full CRUD) |
| One-shot wakeups | V | V `wakeup.sh` |
| Typed workflows with deps | V (Lobster) | V `workflow.sh` |
| Webhooks | V (GitHub, Gmail) | V `webhook-server.py` (GitHub, GitLab, generic) |
| Heartbeat (proactive) | V | V (config) |
| RSS/feeds | ~ (skill) | ~ (via cron + scrape) |
| Calendar integration | V (Google) | ~ (via exec) |
| Email triggers (IMAP/Gmail) | V (PubSub) | ~ (via cron) |
| File watch (inotify) | X | ~ (via exec) |

---

## 10. Observability

| Feature | OpenClaw | PicoClaw |
|---------|:--------:|:--------:|
| Live gateway health endpoint | V | V `/health` |
| **Prometheus metrics endpoint** | ~ | **V** `/metrics` |
| Structured logging | V | V (JSON gateway log) |
| **Audit trail (JSON)** | ~ | **V** `audit-log.sh` |
| **LLM cost tracking** | ~ (custom) | **V** `cost-tracker.sh` (per-model, per-session) |
| Usage analytics | V (dashboard) | V (CSV export) |
| **Budget alerts** | X | **V** (monthly threshold) |

---

## 11. RAG & Knowledge Base

| Feature | OpenClaw | PicoClaw |
|---------|:--------:|:--------:|
| Local knowledge base | ~ (skill) | V `rag-tool.sh` (SQLite) |
| **BM25 keyword search** | ~ | **V** (SQLite FTS5, porter+unicode61) |
| **Semantic search (embeddings)** | V (cloud) | **V** (Gemini text-embedding-004, 768-dim) |
| **Hybrid search (RRF fusion)** | V | **V** (Reciprocal Rank Fusion) |
| Local vector DB | LanceDB | SQLite (vectors as BLOBs) |
| URL indexing | ~ | V `add-url` |
| PDF indexing | ~ (skill) | V `add-pdf` |
| Document dedup (hash) | ~ | V |
| Incremental reindex | ~ | V `reindex` |
| Multi-doc query fusion | V | V |

---

## 12. Developer Experience

| Feature | OpenClaw | PicoClaw |
|---------|:--------:|:--------:|
| One-click install | Brew/npm/Docker | V `curl \| bash` from Termux |
| Remote deploy from laptop | ~ | V `full_deploy.py` (12 steps) |
| Makefile / task runner | ~ | V 30+ targets |
| Interactive config wizard | V `onboard` | V `install.sh` prompts |
| Hot reload config | V | V (config auto-migration) |
| TUI launcher | X | V |
| Web UI launcher | V | V (basic) |
| GitHub Actions CI | V | V (lint, syntax, secret scan) |
| Pre-commit hooks | V | ~ |

---

## 13. Skills & Plugins

| Feature | OpenClaw | PicoClaw |
|---------|:--------:|:--------:|
| ClawHub marketplace | V (5,700+ skills) | V (compatible) |
| Custom skills | V | V |
| Global/workspace skills | V | V |
| Per-agent skill allowlists | V | ~ |
| Plugin architecture | V (bundled/managed) | X (skills only) |
| Channel plugins | V | X |
| Provider plugins | V | ~ (config-based) |

---

## Summary Score

| Category | OpenClaw | PicoClaw Dotfiles | Winner |
|----------|---------:|------------------:|:------:|
| Core runtime footprint | 7/10 | **10/10** | PicoClaw |
| LLM providers | 9/10 | **10/10** | PicoClaw |
| Chat channels | **10/10** | 8/10 | OpenClaw |
| Agent tools | **10/10** | 9/10 | OpenClaw |
| Code execution languages | 5/10 | **10/10** | PicoClaw |
| Device control (Android) | 7/10 | **10/10** | PicoClaw |
| Voice | **10/10** | 7/10 | OpenClaw |
| Security | 8/10 | **10/10** | PicoClaw |
| Automation | **10/10** | 9/10 | OpenClaw |
| Observability | 8/10 | **10/10** | PicoClaw |
| RAG | 8/10 | **9/10** | PicoClaw |
| DX / Install | **10/10** | 9/10 | OpenClaw |
| Skills | **10/10** | 7/10 | OpenClaw |
| **TOTAL** | **112/130** | **118/130** | **PicoClaw** |

---

## Where PicoClaw Wins

1. **30+ LLM providers** (more than OpenClaw's ~18)
2. **16+ code execution languages** (Go, Rust, PHP, Ruby, Swift, Kotlin, Elixir, Zig, etc. vs OpenClaw's Python/JS via skills)
3. **Hybrid RAG** with BM25 + Gemini embeddings + RRF fusion
4. **Deeper Android integration**: ADB self-bridge, 44 permissions, UI automation, 70+ Termux:API commands
5. **Production security**: HMAC, Cloudflare Access, CF Tunnel, rate limiting, IP allowlist, audit log
6. **Prometheus metrics + cost tracker** built-in
7. **Single Go binary** — no Node.js runtime
8. **Ultra-low RAM** (<20 MB idle) — runs on ancient phones
9. **5-layer resilience** (boot script + watchdog + job-scheduler + .bashrc guards + wake lock)
10. **Multi-arch binaries** (x64, arm64, RISC-V, MIPS, LoongArch)

## Where OpenClaw Wins

1. More chat channels (Signal, iMessage, Google Chat, MS Teams, etc.)
2. Full browser automation with CDP profile isolation
3. Voice Wake + Talk Mode + PTT (desktop/mobile companions)
4. Plugin architecture with full lifecycle
5. ClawHub marketplace integration is deeper
6. Native mobile companion apps (iOS/Android/macOS)
7. DM pairing policy

## Hybrid Approach

PicoClaw and OpenClaw can coexist. Use OpenClaw as the main desktop assistant; use PicoClaw on recycled phones as always-on field agents that synchronize via MCP or Telegram.

---

<p align="center">
  <a href="11-power-tools.md">&larr; Power Tools</a>
  &nbsp;&nbsp;|&nbsp;&nbsp;
  <a href="../README.md">README</a>
</p>
