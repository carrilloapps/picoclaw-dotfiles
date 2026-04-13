#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# wakeup.sh -- Schedule one-shot agent wake-ups (reminders, delayed tasks)
# =============================================================================
# Complements cron (recurring) with one-time timed agent prompts. Uses Termux's
# termux-job-scheduler for OS-level reliability, or falls back to at/sleep.
#
# Usage:
#   ~/bin/wakeup.sh in 5m "Check the weather"                # Fire in 5 minutes
#   ~/bin/wakeup.sh in 2h30m "Send the daily report"
#   ~/bin/wakeup.sh at "14:30" "Meeting starts soon"         # Today at 14:30
#   ~/bin/wakeup.sh at "tomorrow 09:00" "Morning briefing"
#   ~/bin/wakeup.sh list                                     # List pending wake-ups
#   ~/bin/wakeup.sh cancel <id>                              # Cancel one
# =============================================================================

set -eu
WAKEUP_DIR="${HOME}/.picoclaw/wakeups"
mkdir -p "$WAKEUP_DIR"

parse_duration() {
    # Converts "5m", "2h30m", "1d" to seconds
    local s="$1" total=0
    while [[ "$s" =~ ([0-9]+)([smhd]) ]]; do
        local n="${BASH_REMATCH[1]}" u="${BASH_REMATCH[2]}"
        case "$u" in
            s) total=$((total + n)) ;;
            m) total=$((total + n * 60)) ;;
            h) total=$((total + n * 3600)) ;;
            d) total=$((total + n * 86400)) ;;
        esac
        s="${s#${BASH_REMATCH[0]}}"
    done
    echo "$total"
}

case "${1:-help}" in
    in)
        DUR="${2:?}"; MSG="${3:?}"
        SEC=$(parse_duration "$DUR")
        [ "$SEC" -lt 10 ] && { echo "Minimum 10 seconds"; exit 1; }
        ID="wake_$(date +%s)_$$"
        FIRE_AT=$(date -d "+$SEC seconds" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -v "+${SEC}S" '+%Y-%m-%d %H:%M:%S')

        # Write a job script
        cat > "$WAKEUP_DIR/$ID.sh" << EOF
#!/data/data/com.termux/files/usr/bin/bash
export SSL_CERT_FILE=/data/data/com.termux/files/usr/etc/tls/cert.pem
echo "$MSG" | $HOME/picoclaw.bin agent -s "cli:wakeup-$ID" 2>&1 >> $HOME/.picoclaw/wakeups.log
termux-notification --title "PicoClaw Wakeup" --content "$MSG" 2>/dev/null || true
rm -f "$WAKEUP_DIR/$ID.sh" "$WAKEUP_DIR/$ID.meta"
EOF
        chmod +x "$WAKEUP_DIR/$ID.sh"
        echo "fire_at=$FIRE_AT" > "$WAKEUP_DIR/$ID.meta"
        echo "message=$MSG" >> "$WAKEUP_DIR/$ID.meta"

        # Fire it via background sleep (simple but works)
        ( sleep "$SEC" && "$WAKEUP_DIR/$ID.sh" ) >/dev/null 2>&1 &
        disown
        echo "Scheduled: $ID will fire at $FIRE_AT"
        ;;
    at)
        WHEN="${2:?}"; MSG="${3:?}"
        SEC_FROM_NOW=$(( $(date -d "$WHEN" +%s) - $(date +%s) ))
        [ "$SEC_FROM_NOW" -lt 0 ] && { echo "Time is in the past"; exit 1; }
        "$0" in "${SEC_FROM_NOW}s" "$MSG"
        ;;
    list)
        if ls "$WAKEUP_DIR"/*.meta >/dev/null 2>&1; then
            for f in "$WAKEUP_DIR"/*.meta; do
                ID=$(basename "$f" .meta)
                echo "[$ID]"
                cat "$f" | sed 's/^/  /'
            done
        else
            echo "No scheduled wake-ups."
        fi
        ;;
    cancel)
        ID="${2:?}"
        rm -f "$WAKEUP_DIR/$ID.sh" "$WAKEUP_DIR/$ID.meta"
        echo "Canceled: $ID"
        ;;
    help|*)
        head -12 "$0" | tail -10 | sed 's/^# //;s/^#//'
        ;;
esac
