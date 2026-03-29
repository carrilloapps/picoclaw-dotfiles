#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# adb-enable.sh — Re-enable ADB TCP and self-connect
# =============================================================================
# Run this if adb-shell.sh stops working (e.g., after reboot when
# Termux:Boot didn't trigger, or after ADB daemon restart).
#
# How it works:
#   - Sets ADB to listen on TCP port 5555
#   - Restarts adbd daemon
#   - Connects to localhost (loopback — network-independent)
#
# Usage:
#   ~/bin/adb-enable.sh
# =============================================================================

echo "[*] Enabling ADB over TCP..."
setprop service.adb.tcp.port 5555 2>/dev/null
stop adbd 2>/dev/null
start adbd 2>/dev/null
sleep 3
adb start-server 2>/dev/null
adb connect localhost:5555 2>/dev/null
sleep 2
adb devices
echo "[*] Done. Test with: ~/bin/adb-shell.sh \"id\""
