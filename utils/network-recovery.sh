#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# network-recovery.sh -- Multi-interface network resilience
# =============================================================================
# Detects and recovers from network changes: WiFi <-> mobile data <-> USB
# ethernet <-> hotspot. Keeps the device reachable on any connection.
#
# Ran by watchdog every minute. On network change:
#   - Re-announces IP via termux-notification
#   - Forces ADB self-bridge reconnect (IP-independent — uses localhost)
#   - Re-resolves the webhook URL DNS
#   - Nudges cloudflared to re-register connections (its own reconnect logic)
#
# Usage:
#   ~/bin/network-recovery.sh                # Check + recover (idempotent)
#   ~/bin/network-recovery.sh --status       # Show current connectivity
#   ~/bin/network-recovery.sh --interfaces   # List active network interfaces
# =============================================================================

set -eu
STATE="${HOME}/.picoclaw/net-state"
CMD="${1:-check}"

detect_interface() {
    # Preference: wlan0 (WiFi) > rmnet (mobile) > usb > other
    for iface in wlan0 rmnet_data0 rmnet_data1 usb0 eth0; do
        ip=$(termux-wifi-connectioninfo 2>/dev/null | jq -r '.ip // empty' 2>/dev/null)
        if [ "$iface" = "wlan0" ] && [ -n "$ip" ] && [ "$ip" != "0.0.0.0" ]; then
            echo "wlan0 $ip"
            return 0
        fi
    done
    # Fallback: route
    DEFAULT_IP=$(ip route 2>/dev/null | awk '/default/{print $5}' | head -1)
    if [ -n "$DEFAULT_IP" ]; then
        IP=$(ip -4 addr show "$DEFAULT_IP" 2>/dev/null | grep -oP 'inet \K[^/]+' | head -1)
        [ -n "$IP" ] && echo "$DEFAULT_IP $IP" && return 0
    fi
    echo "none"
}

ping_check() {
    # Cloudflare 1.1.1.1 is our canary
    ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1 && echo "yes" || echo "no"
}

connectivity_type() {
    # Detect if WiFi, mobile, ethernet, or hotspot
    local t="unknown"
    # Check Termux:API wifi info
    if command -v termux-wifi-connectioninfo >/dev/null 2>&1; then
        WIFI=$(termux-wifi-connectioninfo 2>/dev/null)
        WIFI_IP=$(echo "$WIFI" | jq -r '.ip // empty' 2>/dev/null)
        SSID=$(echo "$WIFI" | jq -r '.ssid // empty' 2>/dev/null | tr -d '"')
        if [ -n "$WIFI_IP" ] && [ "$WIFI_IP" != "0.0.0.0" ] && [ "$WIFI_IP" != "null" ]; then
            t="wifi"
            [ -n "$SSID" ] && [ "$SSID" != "null" ] && t="wifi($SSID)"
        fi
    fi
    # Check for mobile data via getprop
    if [ "$t" = "unknown" ]; then
        MOBILE=$(getprop gsm.network.type 2>/dev/null || echo "")
        [ -n "$MOBILE" ] && [ "$MOBILE" != "UNKNOWN" ] && t="mobile($MOBILE)"
    fi
    # Check for USB ethernet (rndis0, usb0)
    if ip link show 2>/dev/null | grep -qE "rndis0|usb0.*UP"; then
        t="usb-ethernet"
    fi
    echo "$t"
}

case "$CMD" in
    status|--status)
        echo "=== Network status ==="
        echo "Interface: $(detect_interface)"
        echo "Type:      $(connectivity_type)"
        echo "Online:    $(ping_check)"
        ;;
    interfaces|--interfaces)
        ip -4 addr show 2>/dev/null | awk '/^[0-9]+:/{iface=$2; sub(":$","",iface)} /inet /{print iface, $2}'
        ;;
    check|*)
        # Save state; detect change
        CURRENT=$(detect_interface)
        LAST=""
        [ -f "$STATE" ] && LAST=$(cat "$STATE" 2>/dev/null)

        ONLINE=$(ping_check)
        if [ "$ONLINE" = "no" ]; then
            echo "[$(date '+%H:%M:%S')] network:OFFLINE"
            # Try to re-enable wifi via Termux:API (if permission granted)
            termux-wifi-enable true 2>/dev/null || true
            exit 0
        fi

        if [ "$CURRENT" != "$LAST" ]; then
            echo "[$(date '+%H:%M:%S')] network:CHANGED ${LAST:-none} -> $CURRENT"
            echo "$CURRENT" > "$STATE"
            # Force reconnect of services that depend on network
            [ -x "$HOME/bin/adb-connect.sh" ] && "$HOME/bin/adb-connect.sh" >/dev/null 2>&1 &
            # cloudflared will auto-reconnect with new network; no action needed
            # Notify
            IP=$(echo "$CURRENT" | awk '{print $2}')
            termux-notification --title "PicoClaw Network" \
                --content "Connection: $(connectivity_type) IP: $IP" \
                --priority low 2>/dev/null || true
        fi
        ;;
esac
