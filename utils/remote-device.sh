#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# remote-device.sh — Control USB-connected devices from PicoClaw
# =============================================================================
# When another phone/device is connected via USB OTG cable, PicoClaw can
# control it using ADB commands. This script manages the connection and
# provides shortcuts for common operations on the remote device.
#
# Requirements:
#   - USB OTG cable (USB-C to USB-A adapter)
#   - USB cable from target device to the OTG adapter
#   - USB Debugging enabled on the target device
#   - Accept the ADB authorization prompt on the target screen
#
# Usage:
#   ~/bin/remote-device.sh list                    # List connected devices
#   ~/bin/remote-device.sh shell <serial> "cmd"    # Run command on device
#   ~/bin/remote-device.sh screenshot <serial>     # Take screenshot
#   ~/bin/remote-device.sh install <serial> <apk>  # Install APK
#   ~/bin/remote-device.sh info <serial>           # Device info
#   ~/bin/remote-device.sh screen <serial>         # Screen on/off state
#   ~/bin/remote-device.sh tap <serial> X Y        # Tap on screen
#   ~/bin/remote-device.sh type <serial> "text"    # Type text
#   ~/bin/remote-device.sh apps <serial>           # List installed apps
#   ~/bin/remote-device.sh open <serial> <pkg>     # Open an app
#   ~/bin/remote-device.sh push <serial> <local> <remote>  # Push file
#   ~/bin/remote-device.sh pull <serial> <remote> <local>  # Pull file
# =============================================================================

export PATH="$HOME/bin:/data/data/com.termux/files/usr/bin:$PATH"

SELF_SERIALS="emulator-5554 localhost:5555"
MEDIA="$HOME/media"
mkdir -p "$MEDIA"

# Filter out self-bridge devices, return only external ones
get_external_devices() {
    adb devices 2>/dev/null | grep -E "device$" | awk '{print $1}' | while read serial; do
        IS_SELF=false
        for s in $SELF_SERIALS; do
            [ "$serial" = "$s" ] && IS_SELF=true
        done
        [ "$IS_SELF" = "false" ] && echo "$serial"
    done
}

# Get first external device if no serial specified
get_serial() {
    if [ -n "$1" ] && [ "$1" != "auto" ]; then
        echo "$1"
    else
        FIRST=$(get_external_devices | head -1)
        if [ -z "$FIRST" ]; then
            echo "ERROR: No external device connected" >&2
            echo "Connect a device via USB OTG cable and enable USB Debugging" >&2
            return 1
        fi
        echo "$FIRST"
    fi
}

case "$1" in
    list|ls)
        echo "=== Connected Devices ==="
        echo ""
        echo "Self (PicoClaw host):"
        for s in $SELF_SERIALS; do
            adb -s "$s" shell echo ok 2>/dev/null | grep -q ok && echo "  $s (connected)" || true
        done
        echo ""
        EXT=$(get_external_devices)
        if [ -n "$EXT" ]; then
            echo "External (USB OTG):"
            echo "$EXT" | while read serial; do
                MODEL=$(adb -s "$serial" shell getprop ro.product.model 2>/dev/null)
                BRAND=$(adb -s "$serial" shell getprop ro.product.brand 2>/dev/null)
                ANDROID=$(adb -s "$serial" shell getprop ro.build.version.release 2>/dev/null)
                echo "  $serial — $BRAND $MODEL (Android $ANDROID)"
            done
        else
            echo "External: none connected"
            echo ""
            echo "To connect a device:"
            echo "  1. Plug USB OTG cable into this phone"
            echo "  2. Connect target device via USB cable to OTG adapter"
            echo "  3. Enable USB Debugging on target device"
            echo "  4. Accept ADB authorization prompt on target screen"
        fi
        ;;

    shell|sh)
        SERIAL=$(get_serial "$2") || exit 1
        shift 2
        adb -s "$SERIAL" shell "$@"
        ;;

    screenshot|ss)
        SERIAL=$(get_serial "$2") || exit 1
        TS=$(date +%Y%m%d_%H%M%S)
        REMOTE="/sdcard/picoclaw_remote_ss.png"
        LOCAL="$MEDIA/remote_screenshot_${TS}.png"
        adb -s "$SERIAL" shell screencap -p "$REMOTE"
        adb -s "$SERIAL" pull "$REMOTE" "$LOCAL" 2>/dev/null
        adb -s "$SERIAL" shell rm "$REMOTE" 2>/dev/null
        echo "$LOCAL"
        ;;

    info)
        SERIAL=$(get_serial "$2") || exit 1
        echo "=== Device: $SERIAL ==="
        for prop in ro.product.brand ro.product.model ro.product.device ro.build.version.release ro.build.version.sdk ro.product.cpu.abi; do
            VAL=$(adb -s "$SERIAL" shell getprop "$prop" 2>/dev/null)
            echo "  $prop: $VAL"
        done
        echo ""
        echo "Battery:"
        adb -s "$SERIAL" shell dumpsys battery 2>/dev/null | grep -E "level|status|temperature" | head -5
        echo ""
        echo "Screen:"
        adb -s "$SERIAL" shell dumpsys power 2>/dev/null | grep mWakefulness | head -1
        echo ""
        echo "Storage:"
        adb -s "$SERIAL" shell df -h /data 2>/dev/null | tail -1
        ;;

    screen)
        SERIAL=$(get_serial "$2") || exit 1
        WAKE=$(adb -s "$SERIAL" shell dumpsys power 2>/dev/null | grep mWakefulness | head -1)
        echo "$WAKE"
        ;;

    tap)
        SERIAL=$(get_serial "$2") || exit 1
        adb -s "$SERIAL" shell input tap "$3" "$4"
        echo "Tapped ($3, $4) on $SERIAL"
        ;;

    type)
        SERIAL=$(get_serial "$2") || exit 1
        TEXT=$(echo "$3" | sed 's/ /%s/g')
        adb -s "$SERIAL" shell input text "$TEXT"
        echo "Typed on $SERIAL"
        ;;

    key)
        SERIAL=$(get_serial "$2") || exit 1
        adb -s "$SERIAL" shell input keyevent "KEYCODE_$3"
        ;;

    apps)
        SERIAL=$(get_serial "$2") || exit 1
        adb -s "$SERIAL" shell pm list packages -3 | sed 's/package://' | sort
        ;;

    open)
        SERIAL=$(get_serial "$2") || exit 1
        adb -s "$SERIAL" shell monkey -p "$3" -c android.intent.category.LAUNCHER 1 2>/dev/null
        echo "Opened $3 on $SERIAL"
        ;;

    install)
        SERIAL=$(get_serial "$2") || exit 1
        adb -s "$SERIAL" install "$3"
        ;;

    push)
        SERIAL=$(get_serial "$2") || exit 1
        adb -s "$SERIAL" push "$3" "$4"
        ;;

    pull)
        SERIAL=$(get_serial "$2") || exit 1
        adb -s "$SERIAL" pull "$3" "$4"
        ;;

    wake)
        SERIAL=$(get_serial "$2") || exit 1
        adb -s "$SERIAL" shell input keyevent KEYCODE_WAKEUP
        echo "Screen woken on $SERIAL"
        ;;

    reboot)
        SERIAL=$(get_serial "$2") || exit 1
        echo "Rebooting $SERIAL..."
        adb -s "$SERIAL" reboot
        ;;

    *)
        echo "Usage: remote-device.sh <command> [serial] [args]"
        echo ""
        echo "Connection:"
        echo "  list                         List all connected devices"
        echo ""
        echo "Information:"
        echo "  info [serial]                Device specs, battery, storage"
        echo "  screen [serial]              Screen on/off state"
        echo "  apps [serial]                List installed apps"
        echo ""
        echo "Control:"
        echo "  shell [serial] \"cmd\"          Run ADB shell command"
        echo "  tap [serial] X Y             Tap screen coordinates"
        echo "  type [serial] \"text\"          Type text"
        echo "  key [serial] KEYNAME         Press key (HOME, BACK, etc.)"
        echo "  wake [serial]                Wake screen"
        echo "  open [serial] <package>      Open an app"
        echo "  screenshot [serial]          Take screenshot"
        echo ""
        echo "File Transfer:"
        echo "  push [serial] <local> <remote>  Push file to device"
        echo "  pull [serial] <remote> <local>  Pull file from device"
        echo "  install [serial] <apk>          Install APK"
        echo ""
        echo "System:"
        echo "  reboot [serial]              Reboot the device"
        echo ""
        echo "If [serial] is omitted, uses the first external device found."
        echo "Use 'list' to see available serial numbers."
        ;;
esac
