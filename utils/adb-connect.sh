#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# adb-connect.sh — Smart ADB self-bridge with auto-detection
# =============================================================================
# Connects the device to itself via ADB TCP loopback. Handles dynamic ports
# and multiple connection methods. Called by boot script and watchdog.
#
# Connection strategy (tries in order):
#   1. localhost:5555 (standard TCP port, set by 'adb tcpip 5555')
#   2. Detect port from getprop service.adb.tcp.port
#   3. Scan common ADB ports (5555-5559)
#
# Usage:
#   ~/bin/adb-connect.sh          # Connect and print result
#   ~/bin/adb-connect.sh --check  # Just check if connected (exit 0/1)
#   ~/bin/adb-connect.sh --port   # Print the connected port
# =============================================================================

ADB_TARGET=""
CONNECTED=false

# Check if already connected
is_connected() {
    local target="${1:-localhost:5555}"
    adb -s "$target" shell echo ok >/dev/null 2>&1
}

# Try to connect to a specific address
try_connect() {
    local target="$1"
    adb connect "$target" >/dev/null 2>&1
    sleep 1
    if is_connected "$target"; then
        ADB_TARGET="$target"
        CONNECTED=true
        return 0
    fi
    return 1
}

# Ensure ADB server is running
adb start-server >/dev/null 2>&1

# --- Check mode ---
if [ "$1" = "--check" ]; then
    is_connected "localhost:5555" && exit 0
    # Try other known targets
    for dev in $(adb devices 2>/dev/null | grep -oP '\S+:\d+(?=\s+device)'); do
        is_connected "$dev" && exit 0
    done
    exit 1
fi

if [ "$1" = "--port" ]; then
    for dev in $(adb devices 2>/dev/null | grep -oP '\S+:\d+(?=\s+device)'); do
        echo "$dev"
        exit 0
    done
    echo ""
    exit 1
fi

# --- Connection attempts ---

# Strategy 1: Check if already connected (any device)
for dev in $(adb devices 2>/dev/null | grep -oP '\S+:\d+(?=\s+device)'); do
    ADB_TARGET="$dev"
    CONNECTED=true
    break
done

# Strategy 2: Try localhost:5555
if [ "$CONNECTED" = false ]; then
    try_connect "localhost:5555"
fi

# Strategy 3: Detect port from system property
if [ "$CONNECTED" = false ]; then
    PORT=$(getprop service.adb.tcp.port 2>/dev/null)
    if [ -n "$PORT" ] && [ "$PORT" != "0" ] && [ "$PORT" != "5555" ]; then
        try_connect "localhost:$PORT"
    fi
fi

# Strategy 4: Scan common ADB ports
if [ "$CONNECTED" = false ]; then
    for PORT in 5555 5556 5557 5558 5559; do
        try_connect "localhost:$PORT" && break
    done
fi

# --- Report result ---
if [ "$CONNECTED" = true ]; then
    echo "connected:$ADB_TARGET"
    exit 0
else
    echo "failed"
    exit 1
fi
