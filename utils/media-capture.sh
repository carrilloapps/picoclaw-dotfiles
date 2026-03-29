#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# media-capture.sh — Capture photos, audio, video, screenshots from PicoClaw
# =============================================================================
# Unified media capture script. Saves files to ~/media/ with timestamps.
#
# Usage:
#   ~/bin/media-capture.sh photo [front|back]
#   ~/bin/media-capture.sh audio [seconds]
#   ~/bin/media-capture.sh screenshot
#   ~/bin/media-capture.sh screenrecord [seconds]
#   ~/bin/media-capture.sh sensors [sensor_name]
# =============================================================================

MEDIA_DIR="$HOME/media"
mkdir -p "$MEDIA_DIR"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

case "$1" in
    photo)
        CAM="${2:-back}"
        CAM_ID=$( [ "$CAM" = "front" ] && echo 1 || echo 0 )
        OUT="$MEDIA_DIR/photo_${TIMESTAMP}.jpg"
        termux-camera-photo -c "$CAM_ID" "$OUT" 2>&1
        echo "$OUT"
        ;;
    audio)
        DURATION="${2:-10}"
        OUT="$MEDIA_DIR/audio_${TIMESTAMP}.m4a"
        termux-microphone-record -l "$DURATION" -f "$OUT" 2>&1
        sleep $((DURATION + 1))
        echo "$OUT"
        ;;
    screenshot)
        OUT="$MEDIA_DIR/screenshot_${TIMESTAMP}.png"
        # ADB shell writes to /sdcard/ (shared storage, writable by shell uid)
        ~/bin/adb-shell.sh "screencap -p /sdcard/picoclaw_ss.png" 2>&1
        # Pull via adb cat (Termux can't read /sdcard/ directly via cp)
        ~/bin/adb-shell.sh "cat /sdcard/picoclaw_ss.png" > "$OUT" 2>/dev/null
        ~/bin/adb-shell.sh "rm /sdcard/picoclaw_ss.png" 2>/dev/null
        if [ -f "$OUT" ] && [ -s "$OUT" ]; then
            echo "$OUT"
        else
            echo "ERROR: Screenshot failed"
        fi
        ;;
    screenrecord)
        DURATION="${2:-5}"
        OUT="$MEDIA_DIR/screenrecord_${TIMESTAMP}.mp4"
        # Screen must be ON for recording
        ~/bin/ensure-unlocked.sh >/dev/null 2>&1
        # Try native screenrecord first
        ~/bin/adb-shell.sh "screenrecord --time-limit $DURATION /sdcard/picoclaw_rec.mp4" 2>/dev/null
        sleep 2
        ~/bin/adb-shell.sh "cat /sdcard/picoclaw_rec.mp4" > "$OUT" 2>/dev/null
        ~/bin/adb-shell.sh "rm /sdcard/picoclaw_rec.mp4" 2>/dev/null
        # If native failed (Android 16 bug), use screenshot-to-video fallback
        if [ ! -f "$OUT" ] || [ ! -s "$OUT" ]; then
            FRAMES=$((DURATION * 2))
            TMPDIR="$MEDIA_DIR/.frames_$$"
            mkdir -p "$TMPDIR"
            for i in $(seq 1 $FRAMES); do
                ~/bin/adb-shell.sh "screencap -p /sdcard/f.png" 2>/dev/null
                ~/bin/adb-shell.sh "cat /sdcard/f.png" > "$TMPDIR/frame_$(printf '%03d' $i).png" 2>/dev/null
                sleep 0.5
            done
            ~/bin/adb-shell.sh "rm /sdcard/f.png" 2>/dev/null
            ffmpeg -y -framerate 2 -i "$TMPDIR/frame_%03d.png" -c:v libx264 -pix_fmt yuv420p "$OUT" 2>/dev/null
            rm -rf "$TMPDIR"
        fi
        if [ -f "$OUT" ] && [ -s "$OUT" ]; then
            echo "$OUT"
        else
            echo "ERROR: Screen recording failed"
        fi
        ;;
    sensors)
        SENSOR="${2:-all}"
        if [ "$SENSOR" = "all" ]; then
            termux-sensor -l 2>&1
        else
            termux-sensor -s "$SENSOR" -n 1 2>&1
        fi
        ;;
    *)
        echo "Usage: media-capture.sh <photo|audio|screenshot|screenrecord|sensors> [options]"
        echo ""
        echo "  photo [front|back]      Take a photo (default: back camera)"
        echo "  audio [seconds]         Record audio (default: 10s)"
        echo "  screenshot              Take a screenshot via ADB"
        echo "  screenrecord [seconds]  Record screen via ADB (default: 10s)"
        echo "  sensors [name|all]      Read sensors (default: list all)"
        exit 1
        ;;
esac
