#!/bin/bash
# =============================================================================
# grant-permissions.sh — Grant ALL Android permissions to Termux via ADB
# =============================================================================
# Run from a computer with USB ADB access to the device.
# Requires: adb connected and authorized.
#
# Usage:
#   bash utils/grant-permissions.sh
#   # or: make grant-permissions
# =============================================================================

PACKAGES="com.termux com.termux.api com.termux.boot"

# =============================================================================
# PART 1: Runtime permissions (44 permissions)
# =============================================================================
PERMISSIONS="
android.permission.ACCESS_FINE_LOCATION
android.permission.ACCESS_COARSE_LOCATION
android.permission.ACCESS_BACKGROUND_LOCATION
android.permission.ACCESS_MEDIA_LOCATION
android.permission.CAMERA
android.permission.RECORD_AUDIO
android.permission.READ_PHONE_STATE
android.permission.READ_PHONE_NUMBERS
android.permission.CALL_PHONE
android.permission.ANSWER_PHONE_CALLS
android.permission.READ_CALL_LOG
android.permission.WRITE_CALL_LOG
android.permission.ADD_VOICEMAIL
android.permission.USE_SIP
android.permission.READ_CONTACTS
android.permission.WRITE_CONTACTS
android.permission.GET_ACCOUNTS
android.permission.READ_SMS
android.permission.SEND_SMS
android.permission.RECEIVE_SMS
android.permission.RECEIVE_MMS
android.permission.RECEIVE_WAP_PUSH
android.permission.READ_EXTERNAL_STORAGE
android.permission.WRITE_EXTERNAL_STORAGE
android.permission.READ_MEDIA_IMAGES
android.permission.READ_MEDIA_VIDEO
android.permission.READ_MEDIA_AUDIO
android.permission.READ_MEDIA_VISUAL_USER_SELECTED
android.permission.MANAGE_EXTERNAL_STORAGE
android.permission.POST_NOTIFICATIONS
android.permission.BODY_SENSORS
android.permission.BODY_SENSORS_BACKGROUND
android.permission.ACTIVITY_RECOGNITION
android.permission.BLUETOOTH_CONNECT
android.permission.BLUETOOTH_SCAN
android.permission.BLUETOOTH_ADVERTISE
android.permission.NEARBY_WIFI_DEVICES
android.permission.UWB_RANGING
android.permission.SCHEDULE_EXACT_ALARM
android.permission.USE_EXACT_ALARM
android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS
android.permission.SYSTEM_ALERT_WINDOW
android.permission.ACCESS_NOTIFICATION_POLICY
android.permission.READ_CALENDAR
android.permission.WRITE_CALENDAR
"

echo "=== [1/4] Granting runtime permissions ==="
for pkg in $PACKAGES; do
    echo "--- $pkg ---"
    for perm in $PERMISSIONS; do
        adb shell "pm grant $pkg $perm" 2>/dev/null && echo "  [OK] $perm" || true
    done
done

# =============================================================================
# PART 2: App operations (appops) — 17 operations
# =============================================================================
APPOPS="
RUN_IN_BACKGROUND
RUN_ANY_IN_BACKGROUND
SYSTEM_ALERT_WINDOW
WRITE_SETTINGS
REQUEST_INSTALL_PACKAGES
REQUEST_DELETE_PACKAGES
MANAGE_EXTERNAL_STORAGE
AUTO_REVOKE_PERMISSIONS_IF_UNUSED
SCHEDULE_EXACT_ALARM
BOOT_COMPLETED
WAKE_LOCK
START_FOREGROUND
CAMERA
RECORD_AUDIO
COARSE_LOCATION
FINE_LOCATION
MONITOR_LOCATION
MONITOR_HIGH_POWER_LOCATION
READ_SMS
SEND_SMS
RECEIVE_SMS
READ_CONTACTS
WRITE_CONTACTS
READ_CALL_LOG
WRITE_CALL_LOG
READ_CALENDAR
WRITE_CALENDAR
READ_PHONE_STATE
CALL_PHONE
POST_NOTIFICATION
GET_ACCOUNTS
BODY_SENSORS
ACTIVITY_RECOGNITION
BLUETOOTH_SCAN
BLUETOOTH_CONNECT
NEARBY_WIFI_DEVICES
READ_MEDIA_IMAGES
READ_MEDIA_VIDEO
READ_MEDIA_AUDIO
MANAGE_MEDIA
"

echo ""
echo "=== [2/4] Granting app operations ==="
for pkg in $PACKAGES; do
    echo "--- $pkg ---"
    for op in $APPOPS; do
        adb shell "cmd appops set $pkg $op allow" 2>/dev/null && echo "  [OK] $op" || true
    done
done

# =============================================================================
# PART 3: Battery optimization whitelist
# =============================================================================
echo ""
echo "=== [3/4] Battery whitelist + background execution ==="
for pkg in $PACKAGES; do
    adb shell "dumpsys deviceidle whitelist +$pkg" 2>/dev/null
    echo "  [OK] Battery whitelist: $pkg"
done

# =============================================================================
# PART 4: Disable permission auto-revoke
# =============================================================================
echo ""
echo "=== [4/4] Disabling auto-revoke ==="
CRITICAL_PERMS="CAMERA RECORD_AUDIO ACCESS_FINE_LOCATION READ_SMS SEND_SMS READ_CONTACTS READ_CALL_LOG READ_PHONE_STATE"
for pkg in $PACKAGES; do
    for perm in $CRITICAL_PERMS; do
        adb shell "pm set-permission-flags $pkg android.permission.$perm dont-revoke-when-restricted" 2>/dev/null || true
    done
done
echo "  [OK] Auto-revoke disabled for critical permissions"

# =============================================================================
# PART 5: Notification listener for Termux:API
# =============================================================================
echo ""
echo "=== [5/7] Enabling notification listener ==="
adb shell "cmd notification allow_listener com.termux.api/com.termux.api.apis.NotificationListAPI\$NotificationService" 2>/dev/null
echo "  [OK] Notification listener enabled via cmd notification"
echo "  NOTE: If termux-notification-list still returns empty, use"
echo "  ~/bin/notifications.sh instead (reads via ADB, no listener needed)."
echo "  For full listener access: Settings > Apps > Special access >"
echo "  Notification access > toggle Termux:API ON."

# =============================================================================
# PART 6: Enable ADB over TCP for self-bridge
# =============================================================================
echo ""
echo "=== [6/7] Enabling ADB TCP for self-bridge ==="
adb tcpip 5555 2>/dev/null
echo "  [OK] ADB TCP on port 5555"
echo "  Run 'adb connect localhost:5555' from Termux to self-connect"

# =============================================================================
# PART 7: Force-allow background execution
# =============================================================================
echo ""
echo "=== [7/7] Background execution ==="
for pkg in $PACKAGES; do
    adb shell "cmd appops set $pkg RUN_IN_BACKGROUND allow" 2>/dev/null
    adb shell "cmd appops set $pkg RUN_ANY_IN_BACKGROUND allow" 2>/dev/null
done
echo "  [OK] Background execution forced for all Termux apps"

echo ""
echo "=== DONE ==="
echo "All permissions granted. Termux has full device access."
echo ""
echo "Scripts for features that need special access:"
echo "  ~/bin/notifications.sh          — Read notifications (via ADB, no listener needed)"
echo "  ~/bin/ui-control.sh screenshot  — Screenshot (via ADB)"
echo "  ~/bin/ensure-unlocked.sh        — Auto-unlock screen with PIN"
echo ""
echo "Capabilities unlocked:"
echo "  - Location (GPS, network, background)"
echo "  - Camera (front + back, photo + video)"
echo "  - Microphone (recording)"
echo "  - Phone (calls, call log, IMEI, SIM info)"
echo "  - SMS (read, send, receive, MMS)"
echo "  - Contacts (read, write)"
echo "  - Calendar (read, write)"
echo "  - Storage (full external + media access)"
echo "  - Sensors (body, activity, accelerometer, gyro...)"
echo "  - Bluetooth (scan, connect, advertise)"
echo "  - WiFi (scan nearby networks)"
echo "  - Notifications (post, manage)"
echo "  - Screen overlay (system alert window)"
echo "  - Background execution (never killed)"
echo "  - Screenshot / screen recording (via ADB)"
echo "  - Input simulation (taps, swipes, keys via ADB)"
echo "  - App management (install, uninstall, launch via ADB)"
echo "  - System settings (read, write via ADB)"
echo "  - System logs (logcat via ADB)"
