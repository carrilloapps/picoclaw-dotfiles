#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# switch-model.sh — Switch LLM model from Telegram (all providers, all models)
# =============================================================================
# Works with ALL models including Antigravity OAuth models.
# Directly edits config.json and triggers gateway hot-reload.
#
# Usage:
#   ~/bin/switch-model.sh list              # Show all available models
#   ~/bin/switch-model.sh set <name>        # Switch to a model
#   ~/bin/switch-model.sh current           # Show current model
#   ~/bin/switch-model.sh recommend <task>  # Suggest best model for task
# =============================================================================

export SSL_CERT_FILE=/data/data/com.termux/files/usr/etc/tls/cert.pem
export PATH="$HOME/bin:/data/data/com.termux/files/usr/bin:$PATH"

CONFIG="$HOME/.picoclaw/config.json"

case "$1" in
    list)
        echo "=== Available Models ==="
        echo ""
        echo "AZURE (enterprise credits):"
        echo "  azure-gpt4o          GPT-4o (adaptive thinking) [DEFAULT]"
        echo ""
        echo "OLLAMA CLOUD (free):"
        echo "  gpt-oss:120b         GPT-OSS 120B"
        echo "  deepseek-v3.2        DeepSeek V3.2"
        echo "  qwen3.5:397b         Qwen 3.5 397B"
        echo "  kimi-k2:1t           Kimi K2 1T"
        echo "  mistral-large-3:675b Mistral Large 3 675B"
        echo "  glm-5                GLM-5"
        echo "  qwen3-coder:480b     Qwen3 Coder 480B (coding)"
        echo "  cogito-2.1:671b      Cogito 2.1 671B (reasoning)"
        echo ""
        echo "GROQ (fast, free):"
        echo "  groq-llama           Llama 3.3 70B"
        echo "  groq-kimi-k2         Kimi K2 Instruct"
        echo "  groq-compound        Compound AI (agentic)"
        echo "  groq-qwen3-32b      Qwen3 32B"
        echo ""
        echo "ANTIGRAVITY (Google OAuth):"
        echo "  gemini-flash         Gemini 3 Flash"
        echo "  gemini-flash-agent   Gemini 3 Flash Agent"
        echo "  gemini-pro-low       Gemini 3 Pro (Low)"
        echo "  gemini-pro-high      Gemini 3 Pro (High)"
        echo "  gemini-3.1-pro       Gemini 3.1 Pro (High)"
        echo "  gemini-2.5-pro       Gemini 2.5 Pro"
        echo "  gemini-thinking      Gemini 3.1 Flash Thinking"
        echo "  gemini-image         Gemini 3.1 Flash Image"
        echo "  claude-opus          Claude Opus 4.6 (Thinking)"
        echo "  claude-sonnet        Claude Sonnet 4.6 (Thinking)"
        echo "  gpt-oss-ag           GPT-OSS 120B via Antigravity"
        echo ""
        echo "Total: 25 models"
        echo "Switch: ~/bin/switch-model.sh set <name>"
        ;;

    current)
        CURRENT=$(python3 -c "import json; print(json.load(open('$CONFIG'))['agents']['defaults']['model_name'])" 2>/dev/null)
        echo "Current model: $CURRENT"
        ;;

    set)
        NAME="$2"
        if [ -z "$NAME" ]; then
            echo "Usage: switch-model.sh set <model_name>"
            echo "Run 'switch-model.sh list' to see available models."
            exit 1
        fi

        # Map aliases to actual model IDs
        case "$NAME" in
            # Azure
            azure-gpt4o|azure|gpt4o)           MODEL_NAME="azure-gpt4o" ;;
            # Ollama
            gpt-oss:120b|gpt-oss|gptoss)       MODEL_NAME="gpt-oss:120b" ;;
            deepseek-v3.2|deepseek|ds)          MODEL_NAME="deepseek-v3.2" ;;
            qwen3.5:397b|qwen3.5|qwen)         MODEL_NAME="qwen3.5:397b" ;;
            kimi-k2:1t|kimi|kimi-k2)            MODEL_NAME="kimi-k2:1t" ;;
            mistral-large-3:675b|mistral)       MODEL_NAME="mistral-large-3:675b" ;;
            glm-5|glm)                          MODEL_NAME="glm-5" ;;
            qwen3-coder:480b|qwen-coder|coder)  MODEL_NAME="qwen3-coder:480b" ;;
            cogito-2.1:671b|cogito|reasoning)   MODEL_NAME="cogito-2.1:671b" ;;
            # Groq
            groq-llama|groq|llama)              MODEL_NAME="groq-llama" ;;
            groq-kimi-k2|groq-kimi)             MODEL_NAME="groq-kimi-k2" ;;
            groq-compound|compound)             MODEL_NAME="groq-compound" ;;
            groq-qwen3-32b|groq-qwen)           MODEL_NAME="groq-qwen3-32b" ;;
            # Antigravity
            gemini-flash|gemini)                MODEL_NAME="gemini-flash" ;;
            gemini-flash-agent)                 MODEL_NAME="gemini-flash-agent" ;;
            gemini-pro-low)                     MODEL_NAME="gemini-pro-low" ;;
            gemini-pro-high|gemini-pro)         MODEL_NAME="gemini-pro-high" ;;
            gemini-3.1-pro)                     MODEL_NAME="gemini-3.1-pro" ;;
            gemini-2.5-pro)                     MODEL_NAME="gemini-2.5-pro" ;;
            gemini-thinking)                    MODEL_NAME="gemini-thinking" ;;
            gemini-image)                       MODEL_NAME="gemini-image" ;;
            claude-opus|opus)                   MODEL_NAME="claude-opus" ;;
            claude-sonnet|sonnet)               MODEL_NAME="claude-sonnet" ;;
            gpt-oss-ag)                         MODEL_NAME="gpt-oss-ag" ;;
            *)                                  MODEL_NAME="$NAME" ;;
        esac

        # Map model names to provider/model paths
        declare -A MODEL_MAP
        MODEL_MAP[azure-gpt4o]="azure/gpt-4o-2"
        MODEL_MAP[gpt-oss:120b]="openai/gpt-oss:120b"
        MODEL_MAP[deepseek-v3.2]="openai/deepseek-v3.2"
        MODEL_MAP[qwen3.5:397b]="openai/qwen3.5:397b"
        MODEL_MAP[kimi-k2:1t]="openai/kimi-k2:1t"
        MODEL_MAP[mistral-large-3:675b]="openai/mistral-large-3:675b"
        MODEL_MAP[glm-5]="openai/glm-5"
        MODEL_MAP[qwen3-coder:480b]="openai/qwen3-coder:480b"
        MODEL_MAP[cogito-2.1:671b]="openai/cogito-2.1:671b"
        MODEL_MAP[groq-llama]="groq/llama-3.3-70b-versatile"
        MODEL_MAP[groq-kimi-k2]="groq/moonshotai/kimi-k2-instruct"
        MODEL_MAP[groq-compound]="groq/groq/compound"
        MODEL_MAP[groq-qwen3-32b]="groq/qwen/qwen3-32b"
        MODEL_MAP[gemini-flash]="antigravity/gemini-3-flash"
        MODEL_MAP[gemini-flash-agent]="antigravity/gemini-3-flash-agent"
        MODEL_MAP[gemini-pro-low]="antigravity/gemini-3-pro-low"
        MODEL_MAP[gemini-pro-high]="antigravity/gemini-3-pro-high"
        MODEL_MAP[gemini-3.1-pro]="antigravity/gemini-3.1-pro-high"
        MODEL_MAP[gemini-2.5-pro]="antigravity/gemini-2.5-pro"
        MODEL_MAP[gemini-thinking]="antigravity/gemini-2.5-flash-thinking"
        MODEL_MAP[gemini-image]="antigravity/gemini-3.1-flash-image"
        MODEL_MAP[claude-opus]="antigravity/claude-opus-4-6-thinking"
        MODEL_MAP[claude-sonnet]="antigravity/claude-sonnet-4-6"
        MODEL_MAP[gpt-oss-ag]="antigravity/gpt-oss-120b-medium"

        MODEL_ID="${MODEL_MAP[$MODEL_NAME]}"

        if [ -z "$MODEL_ID" ]; then
            echo "Unknown model: $NAME"
            echo "Run 'switch-model.sh list' for available models."
            exit 1
        fi

        # Check if model exists in model_list, add if not
        python3 -c "
import json, sys
cfg = '$CONFIG'
name = '$MODEL_NAME'
model_id = '$MODEL_ID'
with open(cfg) as f:
    c = json.load(f)
# Check if model exists
existing = [m for m in c['model_list'] if m['model_name'] == name]
if not existing:
    # Add the model
    entry = {'model_name': name, 'model': model_id, 'request_timeout': 60}
    # Add api_key/api_base for non-antigravity models
    provider = model_id.split('/')[0]
    if provider == 'openai':
        p = c.get('providers', {}).get('openai', {})
        entry['api_key'] = p.get('api_key', '')
        entry['api_base'] = p.get('base_url', 'https://ollama.com/v1')
    elif provider == 'groq':
        p = c.get('providers', {}).get('groq', {})
        entry['api_key'] = p.get('api_key', '')
        entry['api_base'] = p.get('base_url', 'https://api.groq.com/openai/v1')
    elif provider == 'azure':
        p = c.get('providers', {}).get('azure', {})
        entry['api_key'] = p.get('api_key', '')
        entry['api_base'] = p.get('base_url', '')
    c['model_list'].append(entry)
# Set as default
old = c['agents']['defaults']['model_name']
c['agents']['defaults']['model_name'] = name
with open(cfg, 'w') as f:
    json.dump(c, f, indent=2, ensure_ascii=False)
print(f'Switched: {old} -> {name} ({model_id})')
" 2>/dev/null

        # Trigger hot-reload if gateway is running
        curl -s -X POST http://127.0.0.1:18790/reload >/dev/null 2>&1 && echo "Gateway reloaded." || echo "Note: restart gateway for changes to take effect."
        ;;

    recommend)
        TASK="${2:-general}"
        echo "Recommendation for: $TASK"
        echo ""
        case "$TASK" in
            cod*|program*|develop*)
                echo "  Best: qwen3-coder:480b (Qwen3 Coder, optimized for code)"
                echo "  Fast: groq-qwen3-32b (Qwen3 32B on Groq, fast)"
                echo "  Switch: ~/bin/switch-model.sh set qwen-coder" ;;
            reason*|math*|logic*|analys*)
                echo "  Best: cogito-2.1:671b (Cogito, reasoning specialist)"
                echo "  Alt:  claude-opus (Claude Opus 4.6 Thinking, via Antigravity)"
                echo "  Switch: ~/bin/switch-model.sh set cogito" ;;
            fast|quick|rapido|simple)
                echo "  Best: groq-llama (Llama 3.3 70B on Groq, very fast)"
                echo "  Alt:  groq-compound (Compound AI on Groq)"
                echo "  Switch: ~/bin/switch-model.sh set groq" ;;
            creat*|writing|text*)
                echo "  Best: mistral-large-3:675b (Mistral Large, creative)"
                echo "  Alt:  claude-sonnet (Claude Sonnet 4.6, via Antigravity)"
                echo "  Switch: ~/bin/switch-model.sh set mistral" ;;
            image*|vision*|visual*)
                echo "  Best: gemini-image (Gemini 3.1 Flash Image)"
                echo "  Switch: ~/bin/switch-model.sh set gemini-image" ;;
            *)
                echo "  Best: azure-gpt4o (GPT-4o, adaptive thinking)"
                echo "  Alt:  deepseek-v3.2 (DeepSeek, very capable)"
                echo "  Switch: ~/bin/switch-model.sh set azure" ;;
        esac
        ;;

    reset|default|preset)
        # Restore default preset
        PRESET="$HOME/.picoclaw/default_preset.json"
        if [ ! -f "$PRESET" ]; then
            echo "ERROR: No preset file found at $PRESET"
            exit 1
        fi
        python3 -c "
import json
cfg = '$CONFIG'
preset = '$PRESET'
with open(cfg) as f:
    c = json.load(f)
with open(preset) as f:
    p = json.load(f)
old = c['agents']['defaults']['model_name']
c['agents']['defaults']['model_name'] = p['model_name']
c['agents']['defaults']['model_fallbacks'] = p['model_fallbacks']
c['agents']['defaults']['max_tokens'] = p.get('max_tokens', 16384)
c['agents']['defaults']['max_tool_iterations'] = p.get('max_tool_iterations', 50)
c['agents']['defaults']['steering_mode'] = p.get('steering_mode', 'concurrent')
if 'subturn' in p:
    c['agents']['defaults']['subturn'] = p['subturn']
with open(cfg, 'w') as f:
    json.dump(c, f, indent=2, ensure_ascii=False)
print(f'Restored defaults: {p[\"model_name\"]}')
print(f'Fallbacks: {p[\"model_fallbacks\"]}')
" 2>/dev/null
        curl -s -X POST http://127.0.0.1:18790/reload >/dev/null 2>&1 && echo "Gateway reloaded." || true
        ;;

    *)
        echo "Usage: switch-model.sh <list|set NAME|current|recommend TASK|reset>"
        echo ""
        echo "  list              Show all 25 available models"
        echo "  set <name>        Switch to a model (aliases work: groq, deepseek, etc.)"
        echo "  current           Show current active model"
        echo "  recommend <task>  Suggest best model (coding/reasoning/fast/creative/image)"
        echo "  reset             Restore default preset (Azure + fallbacks)"
        ;;
esac
