#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# transcribe.sh — Voice transcription with provider cascade
# =============================================================================
# Tries providers in order: Azure Whisper → Groq Whisper → Ollama (fallback)
# Returns transcribed text to stdout.
#
# Usage:
#   ~/bin/transcribe.sh <audio_file> [language]
#   ~/bin/transcribe.sh /path/to/voice.oga.ogg es
#   ~/bin/transcribe.sh /path/to/voice.oga.ogg en
#
# Provider cascade:
#   1. Azure OpenAI Whisper (enterprise credits, if deployment exists)
#   2. Groq Whisper large-v3 (free tier, fast)
#   3. Error message (both failed)
#
# Configuration (read from env vars or ~/.picoclaw_keys):
#   AZURE_OPENAI_API_KEY, AZURE_OPENAI_BASE_URL, AZURE_WHISPER_DEPLOYMENT
#   GROQ_KEY (fallback)
# =============================================================================

export SSL_CERT_FILE=/data/data/com.termux/files/usr/etc/tls/cert.pem

# Load keys from env or file
if [ -f "$HOME/.picoclaw_keys" ]; then
    . "$HOME/.picoclaw_keys"
fi

FILE="$1"
LANG="${2:-es}"

if [ -z "$FILE" ]; then
    echo "Usage: transcribe.sh <audio_file> [language]"
    exit 1
fi

if [ ! -f "$FILE" ]; then
    echo "File not found: $FILE"
    exit 1
fi

# -----------------------------------------------------------------------
# Provider 1: Azure OpenAI Whisper
# -----------------------------------------------------------------------
if [ -n "$AZURE_OPENAI_API_KEY" ] && [ -n "$AZURE_OPENAI_BASE_URL" ]; then
    AZURE_DEP="${AZURE_WHISPER_DEPLOYMENT:-whisper-1}"
    RESULT=$(curl -s -w "\n%{http_code}" \
        "${AZURE_OPENAI_BASE_URL}/openai/deployments/${AZURE_DEP}/audio/transcriptions?api-version=2024-06-01" \
        -H "api-key: $AZURE_OPENAI_API_KEY" \
        -F "file=@$FILE" \
        -F "response_format=text" \
        -F "language=$LANG" 2>/dev/null)

    STATUS=$(echo "$RESULT" | tail -1)
    BODY=$(echo "$RESULT" | sed '$d')

    if [ "$STATUS" = "200" ] && [ -n "$BODY" ]; then
        echo "$BODY"
        exit 0
    fi
fi

# -----------------------------------------------------------------------
# Provider 2: Groq Whisper (free tier)
# -----------------------------------------------------------------------
if [ -n "$GROQ_KEY" ]; then
    RESULT=$(curl -s -w "\n%{http_code}" \
        https://api.groq.com/openai/v1/audio/transcriptions \
        -H "Authorization: Bearer $GROQ_KEY" \
        -H "Content-Type: multipart/form-data" \
        -F "file=@$FILE" \
        -F "model=${VOICE_MODEL:-whisper-large-v3}" \
        -F "language=$LANG" \
        -F "response_format=text" 2>/dev/null)

    STATUS=$(echo "$RESULT" | tail -1)
    BODY=$(echo "$RESULT" | sed '$d')

    if [ "$STATUS" = "200" ] && [ -n "$BODY" ]; then
        echo "$BODY"
        exit 0
    fi
fi

# -----------------------------------------------------------------------
# All providers failed
# -----------------------------------------------------------------------
echo "ERROR: Transcription failed. No working STT provider available."
exit 1
