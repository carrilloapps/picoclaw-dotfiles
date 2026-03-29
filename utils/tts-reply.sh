#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# tts-reply.sh — Text-to-speech with provider cascade
# =============================================================================
# Tries providers in order: Azure TTS → Edge TTS (free) → Error
# Generates OGG Opus file for Telegram voice notes.
#
# Usage:
#   ~/bin/tts-reply.sh "Hello world"
#   ~/bin/tts-reply.sh "Hola mundo" es-CO-GonzaloNeural
#   ~/bin/tts-reply.sh "Hello" en-US-GuyNeural
#
# Provider cascade:
#   1. Azure OpenAI TTS (enterprise credits, if deployment exists)
#   2. Microsoft Edge TTS (free, high quality neural voices)
#
# Default voice: es-VE-PaolaNeural (Venezuelan Spanish, female)
#
# Voice aliases:
#   paola / venezolana / default  → es-VE-PaolaNeural (female, VE)
#   sebastian / venezolano        → es-VE-SebastianNeural (male, VE)
#   salome / colombiana           → es-CO-SalomeNeural (female, CO)
#   gonzalo / colombiano          → es-CO-GonzaloNeural (male, CO)
#   jenny / english / en / inglesa→ en-US-JennyNeural (female, US)
#   guy / ingles                  → en-US-GuyNeural (male, US)
#   Or pass any full Edge TTS voice name directly
# =============================================================================

export SSL_CERT_FILE=/data/data/com.termux/files/usr/etc/tls/cert.pem

# Load keys
if [ -f "$HOME/.picoclaw_keys" ]; then
    . "$HOME/.picoclaw_keys"
fi

TEXT="$1"
# Voice selection: name/alias or full Edge TTS voice ID
VOICE_INPUT="${2:-default}"

# Voice aliases — user can say "paola", "sebastian", "jenny", etc.
case "$VOICE_INPUT" in
    default|paola|venezolana)        VOICE="es-VE-PaolaNeural" ;;
    sebastian|venezolano)            VOICE="es-VE-SebastianNeural" ;;
    salome|colombiana)               VOICE="es-CO-SalomeNeural" ;;
    gonzalo|colombiano)              VOICE="es-CO-GonzaloNeural" ;;
    jenny|english|en|inglesa)        VOICE="en-US-JennyNeural" ;;
    guy|ingles)                      VOICE="en-US-GuyNeural" ;;
    es)                              VOICE="es-VE-PaolaNeural" ;;
    *)                               VOICE="$VOICE_INPUT" ;;
esac
MEDIA_DIR="$HOME/media"
mkdir -p "$MEDIA_DIR"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
MP3="$MEDIA_DIR/tts_${TIMESTAMP}.mp3"
OGG="$MEDIA_DIR/tts_${TIMESTAMP}.ogg"

if [ -z "$TEXT" ]; then
    echo "Usage: tts-reply.sh \"text to speak\" [voice]"
    exit 1
fi

# -----------------------------------------------------------------------
# Provider 1: Azure OpenAI TTS
# -----------------------------------------------------------------------
AZURE_TTS_OK=false
if [ -n "$AZURE_OPENAI_API_KEY" ] && [ -n "$AZURE_OPENAI_BASE_URL" ]; then
    AZURE_TTS_DEP="${AZURE_TTS_DEPLOYMENT:-tts-1}"
    # Map Edge voice names to Azure voice names
    AZURE_VOICE="alloy"
    case "$VOICE" in
        *GonzaloNeural*|*male*|*Male*) AZURE_VOICE="echo" ;;
        *SalomeNeural*|*female*|*Female*) AZURE_VOICE="nova" ;;
        *GuyNeural*) AZURE_VOICE="onyx" ;;
    esac

    STATUS=$(curl -s -o "$MP3" -w "%{http_code}" \
        "${AZURE_OPENAI_BASE_URL}/openai/deployments/${AZURE_TTS_DEP}/audio/speech?api-version=2024-06-01" \
        -H "api-key: $AZURE_OPENAI_API_KEY" \
        -H "Content-Type: application/json" \
        -d "{\"model\": \"${AZURE_TTS_DEP}\", \"input\": \"${TEXT}\", \"voice\": \"${AZURE_VOICE}\"}" 2>/dev/null)

    if [ "$STATUS" = "200" ] && [ -s "$MP3" ]; then
        AZURE_TTS_OK=true
    else
        rm -f "$MP3"
    fi
fi

# -----------------------------------------------------------------------
# Provider 2: Microsoft Edge TTS (free)
# -----------------------------------------------------------------------
if [ "$AZURE_TTS_OK" = "false" ]; then
    edge-tts --voice "$VOICE" --text "$TEXT" --write-media "$MP3" 2>/dev/null
    if [ ! -f "$MP3" ] || [ ! -s "$MP3" ]; then
        echo "ERROR: TTS generation failed"
        exit 1
    fi
fi

# -----------------------------------------------------------------------
# Convert to OGG Opus (Telegram voice note format)
# -----------------------------------------------------------------------
ffmpeg -y -i "$MP3" -c:a libopus -b:a 64k -application voip "$OGG" 2>/dev/null
rm -f "$MP3"

if [ -f "$OGG" ] && [ -s "$OGG" ]; then
    echo "$OGG"
else
    echo "ERROR: Audio conversion failed"
    exit 1
fi
