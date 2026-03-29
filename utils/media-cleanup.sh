#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# media-cleanup.sh — Clean temporary media files older than 1 hour
# =============================================================================
# Runs every hour via cron. Deletes ALL temporary files (screenshots,
# recordings, audio, TTS, voice notes, etc.) older than 60 minutes.
#
# Directories cleaned:
#   ~/media/                          — screenshots, recordings, TTS audio
#   /usr/tmp/picoclaw_media/          — voice messages from Telegram
#   /sdcard/picoclaw_*.png|mp4        — ADB screencap/screenrecord temp files
#
# Files in the workspace are PERMANENT and never deleted by this script.
# To save a temp file permanently, move it to the workspace first.
#
# Usage:
#   ~/bin/media-cleanup.sh            # Run cleanup now
#   ~/bin/media-cleanup.sh status     # Show what would be deleted
#   ~/bin/media-cleanup.sh save <file> [name]  # Move file to permanent workspace
# =============================================================================

export PATH="$HOME/bin:/data/data/com.termux/files/usr/bin:$PATH"

MEDIA_DIR="$HOME/media"
TMP_MEDIA="/data/data/com.termux/files/usr/tmp/picoclaw_media"
WORKSPACE="$HOME/.picoclaw/workspace/files"
MAX_AGE=60  # minutes

case "$1" in
    status)
        echo "=== Temporary files older than ${MAX_AGE}min ==="
        echo ""
        echo "~/media/:"
        find "$MEDIA_DIR" -type f -mmin +$MAX_AGE 2>/dev/null | while read f; do
            SIZE=$(ls -lh "$f" 2>/dev/null | awk '{print $5}')
            AGE=$(( ($(date +%s) - $(stat -c %Y "$f" 2>/dev/null || echo 0)) / 60 ))
            echo "  ${f##*/} (${SIZE}, ${AGE}min old)"
        done
        COUNT1=$(find "$MEDIA_DIR" -type f -mmin +$MAX_AGE 2>/dev/null | wc -l)

        echo ""
        echo "picoclaw_media/:"
        find "$TMP_MEDIA" -type f -mmin +$MAX_AGE 2>/dev/null | while read f; do
            SIZE=$(ls -lh "$f" 2>/dev/null | awk '{print $5}')
            AGE=$(( ($(date +%s) - $(stat -c %Y "$f" 2>/dev/null || echo 0)) / 60 ))
            echo "  ${f##*/} (${SIZE}, ${AGE}min old)"
        done
        COUNT2=$(find "$TMP_MEDIA" -type f -mmin +$MAX_AGE 2>/dev/null | wc -l)

        echo ""
        echo "/sdcard/ temp:"
        ~/bin/adb-shell.sh "ls -la /sdcard/picoclaw_*.png /sdcard/picoclaw_*.mp4 2>/dev/null" | grep -v "No such" | while read line; do
            echo "  $line"
        done
        COUNT3=$(~/bin/adb-shell.sh "ls /sdcard/picoclaw_* 2>/dev/null" | wc -l)

        TOTAL=$((COUNT1 + COUNT2 + COUNT3))
        echo ""
        echo "Total: $TOTAL files to clean"
        ;;

    save)
        FILE="$2"
        NAME="$3"

        if [ -z "$FILE" ]; then
            echo "Usage: media-cleanup.sh save <filepath> [name]"
            echo "Moves a temp file to permanent workspace storage."
            exit 1
        fi

        if [ ! -f "$FILE" ]; then
            echo "File not found: $FILE"
            exit 1
        fi

        mkdir -p "$WORKSPACE"

        if [ -n "$NAME" ]; then
            DEST="$WORKSPACE/$NAME"
        else
            DEST="$WORKSPACE/$(basename "$FILE")"
        fi

        cp "$FILE" "$DEST"
        echo "Saved permanently: $DEST"
        echo "This file will NOT be deleted by cleanup."
        ;;

    *)
        # Default: run cleanup
        DELETED=0

        # Clean ~/media/ (screenshots, recordings, TTS)
        COUNT=$(find "$MEDIA_DIR" -type f -mmin +$MAX_AGE 2>/dev/null | wc -l)
        if [ "$COUNT" -gt 0 ]; then
            find "$MEDIA_DIR" -type f -mmin +$MAX_AGE -delete 2>/dev/null
            DELETED=$((DELETED + COUNT))
        fi

        # Clean picoclaw_media/ (voice messages from Telegram)
        COUNT=$(find "$TMP_MEDIA" -type f -mmin +$MAX_AGE 2>/dev/null | wc -l)
        if [ "$COUNT" -gt 0 ]; then
            find "$TMP_MEDIA" -type f -mmin +$MAX_AGE -delete 2>/dev/null
            DELETED=$((DELETED + COUNT))
        fi

        # Clean /sdcard/ temp files (ADB screencap/screenrecord)
        ~/bin/adb-shell.sh "rm -f /sdcard/picoclaw_*.png /sdcard/picoclaw_*.mp4 /sdcard/picoclaw_*.ogg" 2>/dev/null

        # Clean empty frame directories
        find "$MEDIA_DIR" -type d -empty -delete 2>/dev/null

        if [ "$DELETED" -gt 0 ]; then
            echo "Cleaned: $DELETED files"
        fi
        ;;
esac
