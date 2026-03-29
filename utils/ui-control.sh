#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# ui-control.sh — Full Android UI automation for PicoClaw
# =============================================================================
# Control the device screen, apps, and UI elements via ADB shell.
# Works with screen on or off. No root needed.
#
# Usage:
#   ~/bin/ui-control.sh status            # Full device state (screen, lock, app)
#   ~/bin/ui-control.sh wake              # Wake screen (does NOT unlock)
#   ~/bin/ui-control.sh unlock <PIN>      # Wake + enter PIN to unlock
#   ~/bin/ui-control.sh sleep             # Turn screen off
#   ~/bin/ui-control.sh screen            # Check if screen is on/off
#   ~/bin/ui-control.sh locked            # Check if lock screen is showing
#   ~/bin/ui-control.sh screenshot [path] # Take screenshot
#   ~/bin/ui-control.sh screenrecord N    # Record screen for N seconds
#   ~/bin/ui-control.sh open <package>    # Open any app by package name
#   ~/bin/ui-control.sh close <package>   # Force-close an app
#   ~/bin/ui-control.sh current           # Show currently focused app
#   ~/bin/ui-control.sh tap X Y           # Tap at coordinates
#   ~/bin/ui-control.sh swipe X1 Y1 X2 Y2 [ms]  # Swipe gesture
#   ~/bin/ui-control.sh type "text"       # Type text into focused field
#   ~/bin/ui-control.sh key KEYCODE       # Press a key (HOME, BACK, etc.)
#   ~/bin/ui-control.sh uidump            # Dump UI hierarchy (XML)
#   ~/bin/ui-control.sh find "text"       # Find UI element by text
#   ~/bin/ui-control.sh apps              # List running apps
#   ~/bin/ui-control.sh installed         # List all installed apps
#   ~/bin/ui-control.sh url "https://..." # Open URL in browser
#   ~/bin/ui-control.sh brightness N      # Set brightness (0-255)
#   ~/bin/ui-control.sh volume N          # Set media volume
#   ~/bin/ui-control.sh wifi on/off       # Toggle WiFi
#   ~/bin/ui-control.sh airplane on/off   # Toggle airplane mode
#   ~/bin/ui-control.sh rotation on/off   # Toggle auto-rotation
# =============================================================================

ADB="$HOME/bin/adb-shell.sh"
ENSURE_UNLOCK="$HOME/bin/ensure-unlocked.sh"

# Auto-unlock for commands that need the screen
auto_unlock_cmds="open close tap taptext longpress swipe scroll type cleartext paste copy selectall uidump find tapxy notify quicksettings screenshot url call filemanager"
for _cmd in $auto_unlock_cmds; do
    if [ "$1" = "$_cmd" ]; then
        $ENSURE_UNLOCK >/dev/null 2>&1
        break
    fi
done

case "$1" in
    status)
        # Full device state report
        WAKE=$($ADB "dumpsys power | grep mWakefulness | head -1" | sed 's/.*=//')
        LOCKED=$($ADB "dumpsys window policy | grep 'mIsShowing' | head -1" | sed 's/.*=//')
        SCREEN=$($ADB "dumpsys window policy | grep 'screenState' | head -1" | sed 's/.*=//')
        CURRENT=$($ADB "dumpsys activity activities | grep mResumedActivity" | sed 's/.*u0 //;s/ .*//')
        BATTERY=$($ADB "dumpsys battery | grep level" | sed 's/.*: //')
        echo "screen: $SCREEN"
        echo "wakefulness: $WAKE"
        echo "locked: $LOCKED"
        echo "current_app: $CURRENT"
        echo "battery: ${BATTERY}%"
        if [ "$LOCKED" = "true" ]; then
            echo ""
            echo "DEVICE IS LOCKED. To unlock, ask user for PIN or run:"
            echo "  ~/bin/ui-control.sh unlock <PIN>"
        fi
        ;;
    wake)
        $ADB "input keyevent KEYCODE_WAKEUP"
        sleep 1
        # Check if locked
        LOCKED=$($ADB "dumpsys window policy | grep 'mIsShowing' | head -1" | sed 's/.*=//')
        if [ "$LOCKED" = "true" ]; then
            echo "Screen ON but LOCKED. Need PIN to unlock."
            echo "Ask the user for the PIN, then run: ~/bin/ui-control.sh unlock <PIN>"
        else
            echo "Screen ON and UNLOCKED"
        fi
        ;;
    unlock)
        PIN="$2"
        if [ -z "$PIN" ]; then
            echo "Usage: ui-control.sh unlock <PIN>"
            echo "Ask the user for their device PIN/password."
            exit 1
        fi
        # Wake screen
        $ADB "input keyevent KEYCODE_WAKEUP"
        sleep 1
        # Swipe up to show PIN entry
        $ADB "input swipe 540 1800 540 800 300"
        sleep 1
        # Enter PIN digits
        $ADB "input text $PIN"
        sleep 0.5
        # Press Enter to confirm
        $ADB "input keyevent KEYCODE_ENTER"
        sleep 1
        # Verify
        LOCKED=$($ADB "dumpsys window policy | grep 'mIsShowing' | head -1" | sed 's/.*=//')
        if [ "$LOCKED" = "true" ]; then
            echo "UNLOCK FAILED — wrong PIN or lock screen still showing"
        else
            echo "UNLOCKED successfully"
        fi
        ;;
    locked)
        LOCKED=$($ADB "dumpsys window policy | grep 'mIsShowing' | head -1" | sed 's/.*=//')
        if [ "$LOCKED" = "true" ]; then
            echo "YES — device is locked. Ask user for PIN."
        else
            echo "NO — device is unlocked"
        fi
        ;;
    sleep)
        $ADB "input keyevent KEYCODE_SLEEP"
        echo "Screen off"
        ;;
    screen)
        WAKE=$($ADB "dumpsys power | grep mWakefulness | head -1" | sed 's/.*=//')
        echo "Wakefulness: $WAKE"
        ;;
    screenshot)
        OUT="${2:-$HOME/media/screenshot_$(date +%Y%m%d_%H%M%S).png}"
        mkdir -p "$(dirname "$OUT")"
        $ADB "screencap -p /sdcard/picoclaw_ss.png"
        $ADB "cat /sdcard/picoclaw_ss.png" > "$OUT" 2>/dev/null
        $ADB "rm /sdcard/picoclaw_ss.png" 2>/dev/null
        echo "$OUT"
        ;;
    screenrecord)
        SECS="${2:-10}"
        OUT="$HOME/media/recording_$(date +%Y%m%d_%H%M%S).mp4"
        mkdir -p "$HOME/media"
        $ADB "screenrecord --time-limit $SECS /sdcard/picoclaw_rec.mp4"
        sleep 2
        $ADB "cat /sdcard/picoclaw_rec.mp4" > "$OUT" 2>/dev/null
        $ADB "rm /sdcard/picoclaw_rec.mp4" 2>/dev/null
        if [ -f "$OUT" ] && [ -s "$OUT" ]; then
            echo "$OUT"
        else
            echo "ERROR: Recording failed"
        fi
        ;;
    open)
        PKG="$2"
        if [ -z "$PKG" ]; then echo "Usage: ui-control.sh open <package>"; exit 1; fi
        # Try to find launch activity
        ACTIVITY=$($ADB "cmd package resolve-activity --brief $PKG" 2>/dev/null | tail -1)
        if [ -n "$ACTIVITY" ] && [ "$ACTIVITY" != "" ]; then
            $ADB "am start -n $ACTIVITY" 2>&1
        else
            $ADB "monkey -p $PKG -c android.intent.category.LAUNCHER 1" 2>&1
        fi
        ;;
    close)
        $ADB "am force-stop $2"
        echo "Closed $2"
        ;;
    current)
        $ADB "dumpsys activity activities | grep mResumedActivity"
        ;;
    tap)
        $ADB "input tap $2 $3"
        ;;
    swipe)
        MS="${6:-300}"
        $ADB "input swipe $2 $3 $4 $5 $MS"
        ;;
    type)
        # Replace spaces with %s for ADB input
        TEXT=$(echo "$2" | sed 's/ /%s/g')
        $ADB "input text '$TEXT'"
        ;;
    key)
        $ADB "input keyevent KEYCODE_$2"
        ;;
    uidump)
        $ADB "uiautomator dump /sdcard/ui.xml" >/dev/null 2>&1
        $ADB "cat /sdcard/ui.xml"
        ;;
    find)
        $ADB "uiautomator dump /sdcard/ui.xml" >/dev/null 2>&1
        $ADB "cat /sdcard/ui.xml" | grep -oP "text=\"[^\"]*$2[^\"]*\"[^/]*" | head -10
        ;;
    apps)
        $ADB "dumpsys activity recents | grep realActivity" | sed 's/.*realActivity=//;s/}.*//'
        ;;
    installed)
        $ADB "pm list packages -3" | sed 's/package://' | sort
        ;;
    url)
        $ADB "am start -a android.intent.action.VIEW -d '$2'"
        ;;
    brightness)
        $ADB "settings put system screen_brightness $2"
        echo "Brightness set to $2"
        ;;
    volume)
        $ADB "media volume --set $2 --stream 3"
        echo "Volume set to $2"
        ;;
    wifi)
        if [ "$2" = "on" ]; then
            $ADB "svc wifi enable"
        else
            $ADB "svc wifi disable"
        fi
        echo "WiFi $2"
        ;;
    airplane)
        if [ "$2" = "on" ]; then
            $ADB "settings put global airplane_mode_on 1"
            $ADB "am broadcast -a android.intent.action.AIRPLANE_MODE" >/dev/null
        else
            $ADB "settings put global airplane_mode_on 0"
            $ADB "am broadcast -a android.intent.action.AIRPLANE_MODE" >/dev/null
        fi
        echo "Airplane mode $2"
        ;;
    rotation)
        if [ "$2" = "on" ]; then
            $ADB "settings put system accelerometer_rotation 1"
        else
            $ADB "settings put system accelerometer_rotation 0"
        fi
        echo "Auto-rotation $2"
        ;;
    taptext)
        # Find UI element by text and tap its center
        TEXT="$2"
        if [ -z "$TEXT" ]; then echo "Usage: ui-control.sh taptext \"Button text\""; exit 1; fi
        $ADB "uiautomator dump /sdcard/ui.xml" >/dev/null 2>&1
        BOUNDS=$($ADB "cat /sdcard/ui.xml" | grep -oP "text=\"[^\"]*${TEXT}[^\"]*\"[^>]*bounds=\"\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]\"" | grep -oP "bounds=\"\[\K[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+" | head -1)
        if [ -z "$BOUNDS" ]; then
            echo "Element with text '$TEXT' not found on screen"
            exit 1
        fi
        X1=$(echo "$BOUNDS" | grep -oP "^\d+")
        Y1=$(echo "$BOUNDS" | grep -oP "^\d+,\K\d+")
        X2=$(echo "$BOUNDS" | grep -oP "\]\[\K\d+")
        Y2=$(echo "$BOUNDS" | grep -oP "\]\[\d+,\K\d+")
        CX=$(( (X1 + X2) / 2 ))
        CY=$(( (Y1 + Y2) / 2 ))
        $ADB "input tap $CX $CY"
        echo "Tapped '$TEXT' at ($CX, $CY)"
        ;;
    longpress)
        $ADB "input swipe $2 $3 $2 $3 1000"
        echo "Long press at ($2, $3)"
        ;;
    scroll)
        DIR="${2:-down}"
        case "$DIR" in
            up)   $ADB "input swipe 540 800 540 1600 300" ;;
            down) $ADB "input swipe 540 1600 540 800 300" ;;
            left) $ADB "input swipe 800 1200 200 1200 300" ;;
            right) $ADB "input swipe 200 1200 800 1200 300" ;;
        esac
        echo "Scrolled $DIR"
        ;;
    cleartext)
        # Select all + delete (clear any text field)
        $ADB "input keyevent KEYCODE_MOVE_HOME"
        $ADB "input keyevent --longpress KEYCODE_SHIFT_LEFT KEYCODE_MOVE_END"
        $ADB "input keyevent KEYCODE_DEL"
        echo "Text cleared"
        ;;
    paste)
        $ADB "input keyevent KEYCODE_PASTE"
        ;;
    copy)
        $ADB "input keyevent KEYCODE_COPY"
        ;;
    selectall)
        $ADB "input keyevent KEYCODE_MOVE_HOME"
        $ADB "input keyevent --longpress KEYCODE_SHIFT_LEFT KEYCODE_MOVE_END"
        ;;
    notify)
        # Pull down notification shade
        $ADB "cmd statusbar expand-notifications"
        ;;
    quicksettings)
        $ADB "cmd statusbar expand-settings"
        ;;
    closenotify)
        $ADB "cmd statusbar collapse"
        ;;
    dnd)
        if [ "$2" = "on" ]; then
            $ADB "cmd notification set_dnd on"
        else
            $ADB "cmd notification set_dnd off"
        fi
        echo "Do Not Disturb $2"
        ;;
    location)
        if [ "$2" = "on" ]; then
            $ADB "settings put secure location_mode 3"
        else
            $ADB "settings put secure location_mode 0"
        fi
        echo "Location services $2"
        ;;
    mobile)
        if [ "$2" = "on" ]; then
            $ADB "svc data enable"
        else
            $ADB "svc data disable"
        fi
        echo "Mobile data $2"
        ;;
    bluetooth)
        if [ "$2" = "on" ]; then
            $ADB "svc bluetooth enable"
        else
            $ADB "svc bluetooth disable"
        fi
        echo "Bluetooth $2"
        ;;
    nfc)
        if [ "$2" = "on" ]; then
            $ADB "svc nfc enable"
        else
            $ADB "svc nfc disable"
        fi
        echo "NFC $2"
        ;;
    hotspot)
        if [ "$2" = "on" ]; then
            $ADB "cmd wifi start-softap picoclaw_hotspot wpa2 picoclaw123"
        else
            $ADB "cmd wifi stop-softap"
        fi
        echo "WiFi hotspot $2"
        ;;
    intent)
        # Send any custom intent
        $ADB "am start $2 $3 $4 $5 $6 $7 $8"
        ;;
    broadcast)
        $ADB "am broadcast $2 $3 $4 $5"
        ;;
    getprop)
        $ADB "getprop $2"
        ;;
    setprop)
        $ADB "setprop $2 $3"
        ;;
    logcat)
        LINES="${2:-20}"
        $ADB "logcat -d -t $LINES"
        ;;
    processes)
        $ADB "ps -A -o PID,NAME,RSS" | sort -k3 -rn | head -20
        ;;
    kill)
        $ADB "am force-stop $2"
        echo "Killed $2"
        ;;
    uninstall)
        $ADB "pm uninstall $2"
        ;;
    install)
        $ADB "pm install $2"
        ;;
    cleardata)
        $ADB "pm clear $2"
        echo "Cleared data for $2"
        ;;
    filemanager)
        $ADB "am start -a android.intent.action.VIEW -t 'resource/folder' -d 'content://com.android.externalstorage.documents/root/primary'"
        ;;
    call)
        $ADB "am start -a android.intent.action.CALL -d 'tel:$2'"
        ;;
    *)
        echo "Usage: ui-control.sh <command> [args]"
        echo ""
        echo "Status:     status | locked"
        echo "Screen:     wake | unlock PIN | sleep | screen | screenshot | screenrecord N"
        echo "Apps:       open PKG | close PKG | current | apps | installed | kill PKG"
        echo "Input:      tap X Y | taptext TEXT | longpress X Y | swipe | scroll DIR | type TEXT"
        echo "Text:       cleartext | copy | paste | selectall"
        echo "Keys:       key NAME (HOME, BACK, ENTER, TAB, DEL, VOLUME_UP...)"
        echo "UI:         uidump | find TEXT | notify | quicksettings | closenotify"
        echo "Navigation: url URL | call NUMBER | filemanager | intent ARGS"
        echo "Toggles:    wifi | mobile | bluetooth | nfc | airplane | hotspot | location | dnd | rotation"
        echo "Display:    brightness N | volume N"
        echo "System:     logcat N | processes | getprop KEY | setprop KEY VAL"
        echo "Package:    install APK | uninstall PKG | cleardata PKG"
        echo "UI:         uidump | find TEXT | url URL"
        echo "Settings:   brightness N | volume N | wifi on/off | airplane on/off | rotation on/off"
        ;;
esac
