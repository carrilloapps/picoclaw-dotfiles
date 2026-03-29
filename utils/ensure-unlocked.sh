#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# ensure-unlocked.sh — Ensure device is awake, unlocked, and ready
# =============================================================================
# Call this BEFORE any UI operation. It handles all states automatically:
#   - Screen off → wakes it
#   - Lock screen showing → enters PIN to unlock
#   - Already unlocked → does nothing (fast path)
#
# The PIN is read from DEVICE_PIN env var or the hardcoded fallback.
# If the PIN is wrong, it reports failure and the user must provide
# the correct one.
#
# Usage:
#   ~/bin/ensure-unlocked.sh           # Auto-unlock with stored PIN
#   ~/bin/ensure-unlocked.sh 123456    # Override PIN
#
# Exit codes:
#   0 = device is unlocked and ready
#   1 = failed to unlock (wrong PIN or other error)
# =============================================================================

ADB="$HOME/bin/adb-shell.sh"
# Read PIN from argument, env var, or device secret file
PIN="${1:-${DEVICE_PIN}}"
if [ -z "$PIN" ] && [ -f "$HOME/.device_pin" ]; then
    PIN=$(cat "$HOME/.device_pin" 2>/dev/null)
fi
if [ -z "$PIN" ]; then
    echo "UNLOCK_FAILED"
    echo "No PIN available. Set DEVICE_PIN env var, pass as argument,"
    echo "or create ~/.device_pin with the PIN."
    exit 1
fi

# Check current state
WAKE=$($ADB "dumpsys power | grep mWakefulness | head -1" 2>/dev/null | grep -oP '=\K\w+')
LOCKED=$($ADB "dumpsys window policy | grep mIsShowing | head -1" 2>/dev/null | grep -oP '=\K\w+')

# Fast path: already awake and unlocked
if [ "$WAKE" = "Awake" ] && [ "$LOCKED" = "false" ]; then
    echo "READY"
    exit 0
fi

# Wake screen if sleeping
if [ "$WAKE" != "Awake" ]; then
    $ADB "input keyevent KEYCODE_WAKEUP" 2>/dev/null
    sleep 1
fi

# Re-check lock state
LOCKED=$($ADB "dumpsys window policy | grep mIsShowing | head -1" 2>/dev/null | grep -oP '=\K\w+')

# If not locked, we're done
if [ "$LOCKED" = "false" ]; then
    echo "READY"
    exit 0
fi

# Unlock: swipe up → enter PIN → press Enter
$ADB "input swipe 540 1800 540 800 300" 2>/dev/null
sleep 1
$ADB "input text $PIN" 2>/dev/null
sleep 0.5
$ADB "input keyevent KEYCODE_ENTER" 2>/dev/null
sleep 1

# Verify unlock
LOCKED=$($ADB "dumpsys window policy | grep mIsShowing | head -1" 2>/dev/null | grep -oP '=\K\w+')

if [ "$LOCKED" = "false" ]; then
    echo "UNLOCKED"
    exit 0
else
    echo "UNLOCK_FAILED"
    echo "Wrong PIN or lock screen still showing."
    echo "Current PIN tried: $PIN"
    echo "Ask user for correct PIN or run: ~/bin/ensure-unlocked.sh <correct_pin>"
    exit 1
fi
