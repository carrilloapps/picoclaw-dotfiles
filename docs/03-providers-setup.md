# 03 - Providers Setup

PicoClaw supports multiple LLM providers with automatic fallback. This guide covers configuring each provider and the model switching system.

---

## Provider Architecture

```mermaid
graph LR
    subgraph "LLM Inference (fallback chain)"
        A["Azure OpenAI<br/>GPT-4o"] -->|"if unavailable"| B["Ollama Cloud<br/>(free tier)"]
        B -->|"if unavailable"| C["Groq<br/>(fast, free)"]
        C -->|"if unavailable"| D["Antigravity<br/>Gemini (OAuth)"]
    end

    subgraph "Speech-to-Text"
        S1["Azure Whisper"] -->|"if unavailable"| S2["Groq Whisper<br/>large-v3"]
    end

    subgraph "Text-to-Speech"
        T1["Azure TTS"] -->|"if unavailable"| T2["Edge TTS<br/>(free)"]
    end

    style A fill:#0078d4,color:#fff
    style S1 fill:#0078d4,color:#fff
    style T1 fill:#0078d4,color:#fff
    style C fill:#f55036,color:#fff
    style S2 fill:#f55036,color:#fff
    style T2 fill:#4a90d9,color:#fff
```

---

## Supported Provider Prefixes

| Prefix | Provider |
| ------ | -------- |
| `openai/` | OpenAI, Ollama Cloud, any OpenAI-compatible API |
| `azure/` | Azure OpenAI (deployment-based URLs) |
| `anthropic/` | Claude (native Anthropic API) |
| `groq/` | Groq (fast inference, free tier) |
| `antigravity/` | Google Cloud AI / Gemini (OAuth) |
| `github-copilot/` | GitHub Copilot (OAuth) |
| `mistral/` | Mistral AI |
| `openrouter/` | OpenRouter (multi-model gateway) |
| `kimi/` | Moonshot (Kimi) |
| `minimax/` | MiniMax |
| `cerebras/` | Cerebras |
| `bedrock/` | AWS Bedrock |

---

## Azure OpenAI (Enterprise)

Azure OpenAI provides dedicated deployments with enterprise SLAs. Used as the primary provider in this implementation.

### Setup

1. Create an Azure OpenAI resource in the [Azure Portal](https://portal.azure.com).
2. Deploy a model (e.g., `gpt-4o`) in Azure AI Studio.
3. Copy the endpoint URL and API key from "Keys and Endpoint".

### Configuration

In `.env`:

```bash
AZURE_OPENAI_BASE_URL=https://your-resource.openai.azure.com
AZURE_OPENAI_API_KEY=<32-char-hex-key>
AZURE_OPENAI_DEPLOYMENT=gpt-4o-2
AZURE_OPENAI_API_VERSION=2024-06-01
```

In `config.json` on the device:

```json
{
  "providers": {
    "azure": {
      "base_url": "https://your-resource.openai.azure.com",
      "api_key": "<key>"
    }
  },
  "model_list": [
    {
      "model_name": "azure-gpt4o",
      "model": "azure/gpt-4o-2",
      "api_key": "<key>",
      "api_base": "https://your-resource.openai.azure.com"
    }
  ]
}
```

Azure is also used for Whisper STT and TTS deployments. The API keys for voice scripts are stored in `~/.picoclaw_keys`:

```bash
AZURE_OPENAI_API_KEY="<key>"
AZURE_OPENAI_BASE_URL="https://your-resource.openai.azure.com"
AZURE_WHISPER_DEPLOYMENT="whisper-1"
```

---

## Ollama Cloud (Free)

[Ollama Cloud](https://ollama.com) provides free access to a variety of open-source models via an OpenAI-compatible API. Used as the first fallback.

### Setup

1. Create an account at [ollama.com](https://ollama.com).
2. Generate an API key from account settings.

### Configuration

In `.env`:

```bash
OLLAMA_API_KEY=<32-char-hex>.<26-char-secret>
OLLAMA_BASE_URL=https://ollama.com/v1
OLLAMA_MODEL=<model-name>
```

In `config.json`:

```json
{
  "providers": {
    "openai": {
      "base_url": "https://ollama.com/v1",
      "api_key": "<key>"
    }
  },
  "model_list": [
    {
      "model_name": "deepseek-v3.2",
      "model": "openai/deepseek-v3.2",
      "api_key": "<key>",
      "api_base": "https://ollama.com/v1"
    }
  ]
}
```

### Available Ollama Cloud Models

| Model | Size | Type |
| ----- | ---- | ---- |
| `gpt-oss:120b` | 120B | General |
| `deepseek-v3.2` | -- | General |
| `qwen3.5:397b` | 397B | General |
| `kimi-k2:1t` | 1T | General |
| `mistral-large-3:675b` | 675B | General |
| `glm-5` | -- | General |
| `qwen3-coder:480b` | 480B | Coding |
| `cogito-2.1:671b` | 671B | Reasoning |

---

## Groq (Free, Fast)

[Groq](https://console.groq.com) provides extremely fast inference on their LPU hardware with a free tier.

### Setup

1. Create an account at [console.groq.com](https://console.groq.com).
2. Generate an API key from the API Keys section.

### Configuration

In `.env`:

```bash
GROQ_API_KEY=gsk_<alphanumeric>
```

In `config.json`:

```json
{
  "providers": {
    "groq": {
      "base_url": "https://api.groq.com/openai/v1",
      "api_key": "gsk_..."
    }
  }
}
```

Groq is used for both LLM inference and Whisper STT (voice transcription fallback).

---

## Antigravity / Google Gemini (OAuth)

The `antigravity/` provider uses Google OAuth instead of a static API key. It serves as the last-resort LLM fallback because it requires periodic re-authentication.

### One-Time Setup

1. Run `~/bin/auth-antigravity.sh start` on the device -- it prints a Google OAuth URL.
2. Open the URL in any browser and sign in with your Google account.
3. The browser redirects to `localhost:51121` (connection refused -- this is expected).
4. Copy the full redirect URL from the browser address bar.
5. Run `~/bin/auth-antigravity.sh paste "<redirect-URL>"` on the device.

### Token Management

```bash
~/bin/auth-antigravity.sh status    # Check token validity
~/bin/auth-antigravity.sh refresh   # Logout + re-auth (expired token)
./picoclaw auth status              # PicoClaw's native auth status
```

**Important**: `picoclaw auth login` resets `agents.defaults.model_name` to the just-authenticated provider. The `auth-antigravity.sh` script automatically restores the correct fallback order after authentication.

### Available Antigravity Models

| Model | Description |
| ----- | ----------- |
| `gemini-flash` | Gemini 3 Flash |
| `gemini-flash-agent` | Gemini 3 Flash Agent |
| `gemini-pro-low` | Gemini 3 Pro (Low) |
| `gemini-pro-high` | Gemini 3 Pro (High) |
| `gemini-3.1-pro` | Gemini 3.1 Pro (High) |
| `gemini-2.5-pro` | Gemini 2.5 Pro |
| `gemini-thinking` | Gemini 3.1 Flash Thinking |
| `gemini-image` | Gemini 3.1 Flash Image |
| `claude-opus` | Claude Opus 4.6 (Thinking) |
| `claude-sonnet` | Claude Sonnet 4.6 (Thinking) |
| `gpt-oss-ag` | GPT-OSS 120B via Antigravity |

---

## Fallback Chain Configuration

PicoClaw supports automatic model fallbacks. When the primary model fails, it cascades through configured fallbacks:

```
Azure GPT-4o --> Ollama Cloud --> Groq --> Antigravity (always last, needs auth)
```

Set in `config.json`:

```json
{
  "agents": {
    "defaults": {
      "model_name": "azure-gpt4o",
      "model_fallbacks": ["deepseek-v3.2", "groq-llama", "gemini-flash"]
    }
  }
}
```

---

## Switching Models

### From the Workstation

```bash
python scripts/change_model.py --list    # List available models
python scripts/change_model.py <MODEL>   # Switch model
make model M=<MODEL>                     # Same via Makefile
```

### From Telegram Chat

The LLM can switch its own model when the user asks. A device script handles all 25 models:

```bash
~/bin/switch-model.sh list               # Show all models
~/bin/switch-model.sh set deepseek       # Switch (aliases work)
~/bin/switch-model.sh current            # Show active model
~/bin/switch-model.sh recommend coding   # Suggest best for task
~/bin/switch-model.sh reset              # Restore default preset
```

The script uses hot-reload -- no gateway restart needed.

### Model Recommendations

| Task | Recommended Model |
| ---- | ----------------- |
| General use | `azure-gpt4o` (default) |
| Coding | `qwen3-coder:480b` |
| Reasoning | `cogito-2.1:671b` |
| Fast responses | `groq-llama` |
| Creative writing | `mistral-large-3:675b` |
| Image understanding | `gemini-image` |

---

## Next Steps

With providers configured, proceed to [04 - Telegram Integration](04-telegram-integration.md) to set up messaging.
