#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# detect-ip.sh — Auto-detect device IP address
# =============================================================================
# Tries multiple methods and returns the first valid IPv4 address.
# Works from Termux, cron, boot scripts, and ADB shell.
#
# Usage:
#   ~/bin/detect-ip.sh           # Print IP
#   IP=$(~/bin/detect-ip.sh)     # Capture in variable
# =============================================================================

get_ip() {
    local ip=""

    # Method 1: Termux:API (most reliable, works without ADB)
    if command -v termux-wifi-connectioninfo >/dev/null 2>&1; then
        ip=$(termux-wifi-connectioninfo 2>/dev/null | jq -r '.ip // empty' 2>/dev/null)
        if [ -n "$ip" ] && [ "$ip" != "null" ] && [ "$ip" != "0.0.0.0" ]; then
            echo "$ip"
            return 0
        fi
    fi

    # Method 2: ADB shell (works if self-bridge is connected)
    if command -v adb >/dev/null 2>&1; then
        ip=$(adb -s localhost:5555 shell "ip -4 addr show wlan0" 2>/dev/null | grep -oP 'inet \K[0-9.]+')
        if [ -n "$ip" ]; then
            echo "$ip"
            return 0
        fi
    fi

    # Method 3: ifconfig (needs net-tools)
    if command -v ifconfig >/dev/null 2>&1; then
        ip=$(ifconfig wlan0 2>/dev/null | grep -oP 'inet \K[0-9.]+')
        if [ -n "$ip" ]; then
            echo "$ip"
            return 0
        fi
    fi

    # Method 4: ip command
    ip=$(ip -4 addr show wlan0 2>/dev/null | grep -oP 'inet \K[0-9.]+')
    if [ -n "$ip" ]; then
        echo "$ip"
        return 0
    fi

    # Method 5: getprop (Android-specific)
    if command -v getprop >/dev/null 2>&1; then
        ip=$(getprop dhcp.wlan0.ipaddress 2>/dev/null)
        if [ -n "$ip" ] && [ "$ip" != "0.0.0.0" ]; then
            echo "$ip"
            return 0
        fi
    fi

    # Failed
    echo ""
    return 1
}

get_ip
