#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# remote-device.sh — Control ANY device connected via USB OTG or network
# =============================================================================
# Supports: Android (ADB), iPhone (USB tethering), Raspberry Pi / Linux (SSH),
#           USB flash drives, USB Ethernet adapters, and more.
#
# Usage:
#   ~/bin/remote-device.sh scan                      # Detect all connected devices
#   ~/bin/remote-device.sh android <cmd> [serial]    # ADB commands for Android
#   ~/bin/remote-device.sh ssh <host> <cmd>          # SSH commands for Linux/RPi
#   ~/bin/remote-device.sh usb                       # List raw USB devices
#   ~/bin/remote-device.sh storage                   # List USB storage mounts
#   ~/bin/remote-device.sh network                   # List USB network interfaces
# =============================================================================

export PATH="$HOME/bin:/data/data/com.termux/files/usr/bin:$PATH"
MEDIA="$HOME/media"
mkdir -p "$MEDIA"

SELF_ADB="emulator-5554 localhost:5555"

# =========================================================================
# Detection
# =========================================================================
detect_android() {
    adb devices 2>/dev/null | grep -E "device$" | awk '{print $1}' | while read serial; do
        IS_SELF=false
        for s in $SELF_ADB; do [ "$serial" = "$s" ] && IS_SELF=true; done
        if [ "$IS_SELF" = "false" ]; then
            MODEL=$(adb -s "$serial" shell getprop ro.product.model 2>/dev/null | tr -d '\r')
            BRAND=$(adb -s "$serial" shell getprop ro.product.brand 2>/dev/null | tr -d '\r')
            VER=$(adb -s "$serial" shell getprop ro.build.version.release 2>/dev/null | tr -d '\r')
            echo "android|$serial|$BRAND $MODEL|Android $VER"
        fi
    done
}

detect_usb_storage() {
    # USB flash drives mount under /storage/ or show as new block devices
    ~/bin/adb-shell.sh "ls /dev/block/sd[b-z]* 2>/dev/null" | while read dev; do
        SIZE=$(~/bin/adb-shell.sh "blockdev --getsize64 $dev 2>/dev/null" | awk '{printf "%.0fGB", $1/1073741824}')
        echo "storage|$dev|USB Storage|$SIZE"
    done
}

detect_usb_network() {
    # iPhone (cdc_ncm), USB Ethernet (cdc_ether, r8152, asix)
    # These create network interfaces like usb0, eth0, ncm0
    ~/bin/adb-shell.sh "ip link show 2>/dev/null" | grep -E "usb[0-9]|eth[0-9]|ncm[0-9]|rndis[0-9]" | while read line; do
        IFACE=$(echo "$line" | grep -oP '\d+: \K[^:@]+')
        STATE=$(echo "$line" | grep -oP 'state \K\w+')
        if [ -n "$IFACE" ]; then
            IP=$(~/bin/adb-shell.sh "ip addr show $IFACE 2>/dev/null" | grep -oP 'inet \K[0-9.]+' | head -1)
            echo "network|$IFACE|USB Network ($STATE)|IP: ${IP:-no IP}"
        fi
    done
}

detect_usb_raw() {
    # Raw USB devices via Termux API
    termux-usb -l 2>/dev/null | tr -d '[]" ' | tr ',' '\n' | while read dev; do
        [ -n "$dev" ] && echo "usb-raw|$dev|USB Device|via termux-usb"
    done
}

# =========================================================================
# Commands
# =========================================================================
case "$1" in
    scan|list|ls)
        echo "=== Connected Devices ==="
        echo ""

        # Self
        echo "PicoClaw Host:"
        for s in $SELF_ADB; do
            adb -s "$s" shell echo ok 2>/dev/null | grep -q ok && echo "  [$s] ADB self-bridge ✓" || true
        done

        # Android devices
        ANDROIDS=$(detect_android)
        if [ -n "$ANDROIDS" ]; then
            echo ""
            echo "Android Devices (ADB):"
            echo "$ANDROIDS" | while IFS='|' read type serial name info; do
                echo "  [$serial] $name — $info"
            done
        fi

        # USB storage
        STORAGE=$(detect_usb_storage)
        if [ -n "$STORAGE" ]; then
            echo ""
            echo "USB Storage:"
            echo "$STORAGE" | while IFS='|' read type dev name info; do
                echo "  [$dev] $name — $info"
            done
        fi

        # USB network (iPhone, Ethernet)
        NETWORK=$(detect_usb_network)
        if [ -n "$NETWORK" ]; then
            echo ""
            echo "USB Network (iPhone / Ethernet):"
            echo "$NETWORK" | while IFS='|' read type iface name info; do
                echo "  [$iface] $name — $info"
            done
        fi

        # Raw USB
        RAW=$(detect_usb_raw)
        if [ -n "$RAW" ]; then
            echo ""
            echo "Raw USB Devices:"
            echo "$RAW" | while IFS='|' read type dev name info; do
                echo "  [$dev] $info"
            done
        fi

        # Nothing external?
        if [ -z "$ANDROIDS" ] && [ -z "$STORAGE" ] && [ -z "$NETWORK" ] && [ -z "$RAW" ]; then
            echo ""
            echo "No external devices detected."
            echo ""
            echo "Supported connections:"
            echo "  • Android phone → USB cable + OTG adapter (ADB)"
            echo "  • iPhone → Lightning/USB-C cable + OTG (USB tethering → SSH)"
            echo "  • Raspberry Pi → USB cable (USB gadget mode → SSH)"
            echo "  • USB flash drive → OTG adapter (storage mount)"
            echo "  • USB Ethernet → OTG adapter (network interface)"
            echo "  • USB hub → multiple devices at once"
        fi
        ;;

    # ----- ANDROID (ADB) -----
    android|adb)
        shift
        SUBCMD="$1"; shift
        SERIAL="${1:-auto}"
        if [ "$SERIAL" = "auto" ]; then
            SERIAL=$(detect_android | head -1 | cut -d'|' -f2)
            [ -z "$SERIAL" ] && echo "No Android device connected" && exit 1
        fi
        shift 2>/dev/null

        case "$SUBCMD" in
            info)
                echo "=== $SERIAL ==="
                for p in ro.product.brand ro.product.model ro.build.version.release ro.product.cpu.abi; do
                    echo "  $p: $(adb -s "$SERIAL" shell getprop "$p" 2>/dev/null | tr -d '\r')"
                done
                echo "Battery:"
                adb -s "$SERIAL" shell dumpsys battery 2>/dev/null | grep -E "level|status" | head -3
                ;;
            shell)      adb -s "$SERIAL" shell "$@" ;;
            screenshot)
                TS=$(date +%Y%m%d_%H%M%S)
                OUT="$MEDIA/remote_ss_${TS}.png"
                adb -s "$SERIAL" shell screencap -p /sdcard/tmp_ss.png
                adb -s "$SERIAL" pull /sdcard/tmp_ss.png "$OUT" 2>/dev/null
                adb -s "$SERIAL" shell rm /sdcard/tmp_ss.png
                echo "$OUT" ;;
            tap)        adb -s "$SERIAL" shell input tap "$@" ;;
            type)       adb -s "$SERIAL" shell input text "$(echo "$@" | sed 's/ /%s/g')" ;;
            key)        adb -s "$SERIAL" shell input keyevent "KEYCODE_$@" ;;
            open)       adb -s "$SERIAL" shell monkey -p "$@" -c android.intent.category.LAUNCHER 1 2>/dev/null ;;
            apps)       adb -s "$SERIAL" shell pm list packages -3 | sed 's/package://' | sort ;;
            install)    adb -s "$SERIAL" install "$@" ;;
            push)       adb -s "$SERIAL" push "$@" ;;
            pull)       adb -s "$SERIAL" pull "$@" ;;
            wake)       adb -s "$SERIAL" shell input keyevent KEYCODE_WAKEUP ;;
            reboot)     echo "Rebooting $SERIAL..."; adb -s "$SERIAL" reboot ;;
            *)          echo "Usage: remote-device.sh android <info|shell|screenshot|tap|type|key|open|apps|install|push|pull|wake|reboot> [serial] [args]" ;;
        esac
        ;;

    # ----- SSH (Linux, Raspberry Pi, iPhone via tethering) -----
    ssh)
        shift
        HOST="$1"; shift
        if [ -z "$HOST" ]; then
            echo "Usage: remote-device.sh ssh <user@host> <command>"
            echo ""
            echo "Examples:"
            echo "  remote-device.sh ssh pi@raspberrypi.local 'uname -a'"
            echo "  remote-device.sh ssh pi@10.0.0.1 'ls /home/pi/'"
            echo "  remote-device.sh ssh root@172.20.10.2 'cat /etc/hostname'"
            echo ""
            echo "For iPhone: enable Personal Hotspot → USB, then:"
            echo "  remote-device.sh ssh root@172.20.10.1 'uname -a'"
            echo "  (requires jailbreak + OpenSSH on iPhone)"
            exit 1
        fi
        ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$HOST" "$@"
        ;;

    # ----- USB RAW (via Termux API) -----
    usb)
        echo "=== Raw USB Devices ==="
        DEVS=$(termux-usb -l 2>/dev/null)
        if [ "$DEVS" = "[]" ] || [ -z "$DEVS" ]; then
            echo "No USB devices detected via Termux API."
            echo "Connect a device via OTG and grant USB permission when prompted."
        else
            echo "$DEVS"
            echo ""
            echo "To interact with a USB device:"
            echo "  termux-usb -r -e 'cat' <device-path>"
        fi
        ;;

    # ----- USB STORAGE -----
    storage)
        echo "=== USB Storage ==="
        MOUNTS=$(~/bin/adb-shell.sh "mount 2>/dev/null" | grep -E "/dev/block/sd[b-z]|/mnt/media_rw")
        if [ -n "$MOUNTS" ]; then
            echo "$MOUNTS"
        else
            echo "No USB storage mounted."
            echo "Connect a USB flash drive via OTG adapter."
            echo "It should auto-mount under /mnt/media_rw/ or /storage/"
        fi
        ;;

    # ----- USB NETWORK (iPhone tethering, USB Ethernet) -----
    network|net)
        echo "=== USB Network Interfaces ==="
        IFACES=$(detect_usb_network)
        if [ -n "$IFACES" ]; then
            echo "$IFACES" | while IFS='|' read type iface name info; do
                echo "  $iface: $name — $info"
            done
            echo ""
            echo "To use iPhone tethering:"
            echo "  1. iPhone → Settings → Personal Hotspot → Allow Others"
            echo "  2. Connect iPhone to this phone via USB + OTG"
            echo "  3. The interface gets an IP automatically"
            echo "  4. Internet flows through the iPhone's connection"
        else
            echo "No USB network interfaces detected."
            echo ""
            echo "Supported:"
            echo "  • iPhone USB tethering (cdc_ncm/cdc_ether)"
            echo "  • USB Ethernet adapter (r8152/asix/ax88179)"
            echo "  • Raspberry Pi USB gadget mode (rndis)"
        fi
        ;;

    *)
        echo "Usage: remote-device.sh <scan|android|ssh|usb|storage|network>"
        echo ""
        echo "Detection:"
        echo "  scan                          Detect ALL connected devices"
        echo ""
        echo "Android (via ADB + USB OTG):"
        echo "  android info [serial]         Device specs + battery"
        echo "  android shell [serial] cmd    Run command"
        echo "  android screenshot [serial]   Take screenshot"
        echo "  android tap [serial] X Y      Tap screen"
        echo "  android type [serial] text    Type text"
        echo "  android open [serial] pkg     Open app"
        echo "  android apps [serial]         List apps"
        echo "  android push/pull [serial]    Transfer files"
        echo ""
        echo "Linux / Raspberry Pi (via SSH):"
        echo "  ssh user@host command         Run command via SSH"
        echo ""
        echo "USB Devices:"
        echo "  usb                           List raw USB devices"
        echo "  storage                       List USB flash drives"
        echo "  network                       List USB network (iPhone/Ethernet)"
        ;;
esac
