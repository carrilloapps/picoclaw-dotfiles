#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# adb-shell.sh — Execute commands with ADB shell privileges from Termux
# =============================================================================
# PicoClaw runs as Termux user which can't access /proc/net/arp,
# dumpsys, pm, etc. This script bridges to ADB shell (uid=2000) which has
# elevated privileges without needing root.
#
# Prerequisites:
#   - ADB over TCP enabled: run 'adb tcpip 5555' from a connected PC
#   - android-tools installed in Termux: pkg install android-tools
#   - ADB authorized: accept the dialog on the phone screen
#
# Usage:
#   ~/bin/adb-shell.sh "cat /proc/net/arp"
#   ~/bin/adb-shell.sh "dumpsys battery"
#   ~/bin/adb-shell.sh "pm list packages"
#
# What ADB shell can do that Termux can't:
#   - Read /proc/net/arp (MAC addresses of devices on network)
#   - Run dumpsys (battery, wifi, network, activity, etc.)
#   - List/manage packages (pm list/install/uninstall)
#   - Access input subsystem (simulate taps, swipes, key events)
#   - Read logcat
#   - Access settings (settings get/put)
# =============================================================================

ADB_TARGET="localhost:5555"

# Ensure ADB server is running and connected
adb start-server >/dev/null 2>&1
adb connect "$ADB_TARGET" >/dev/null 2>&1

# Execute the command
if [ -z "$1" ]; then
    echo "Usage: adb-shell.sh \"<command>\""
    exit 1
fi

adb -s "$ADB_TARGET" shell "$@"
