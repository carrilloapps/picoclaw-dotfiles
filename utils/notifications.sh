#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# notifications.sh — Read device notifications via ADB shell
# =============================================================================
# Alternative to termux-notification-list that works without the
# notification listener permission (which requires manual toggle in Settings).
#
# Uses ADB shell (uid=2000) to read notifications from dumpsys.
#
# Usage:
#   ~/bin/notifications.sh              # JSON list of all notifications
#   ~/bin/notifications.sh --unread     # Only unread (seen=false)
#   ~/bin/notifications.sh --count      # Count only
#   ~/bin/notifications.sh --summary    # One-line per notification
# =============================================================================

ADB="adb -s localhost:5555"

# Get raw notification dump
RAW=$($ADB shell "dumpsys notification --noredact" 2>/dev/null)

if [ -z "$RAW" ]; then
    echo '{"error": "ADB not connected. Run: adb connect localhost:5555"}'
    exit 1
fi

case "${1:-}" in
    --count)
        echo "$RAW" | grep -c "NotificationRecord("
        ;;
    --unread)
        # Parse unread notifications into a readable format
        echo "$RAW" | python3 -c "
import sys, json, re

text = sys.stdin.read()
records = re.split(r'    NotificationRecord\(', text)
notifications = []

for rec in records[1:]:
    seen_match = re.search(r'seen=(true|false)', rec)
    if seen_match and seen_match.group(1) == 'true':
        continue
    pkg_match = re.search(r'pkg=(\S+)', rec)
    title_match = re.search(r'android\.title=String \((.+?)\)', rec)
    text_match = re.search(r'android\.text=String \((.+?)\)', rec)
    subtext_match = re.search(r'android\.subText=String \((.+?)\)', rec)
    when_match = re.search(r'when=(\d+)/', rec)

    if pkg_match:
        notifications.append({
            'package': pkg_match.group(1),
            'title': title_match.group(1) if title_match else None,
            'text': text_match.group(1) if text_match else None,
            'subtext': subtext_match.group(1) if subtext_match else None,
            'seen': False,
            'when': int(when_match.group(1)) if when_match else None,
        })

json.dump(notifications, sys.stdout, indent=2, ensure_ascii=False)
print()
"
        ;;
    --summary)
        echo "$RAW" | python3 -c "
import sys, re

text = sys.stdin.read()
records = re.split(r'    NotificationRecord\(', text)

for rec in records[1:]:
    pkg_match = re.search(r'pkg=(\S+)', rec)
    title_match = re.search(r'android\.title=String \((.+?)\)', rec)
    text_match = re.search(r'android\.text=String \((.+?)\)', rec)
    seen_match = re.search(r'seen=(true|false)', rec)

    pkg = pkg_match.group(1).split('.')[-1] if pkg_match else '?'
    title = title_match.group(1) if title_match else '(no title)'
    text = text_match.group(1)[:60] if text_match else ''
    seen = 'read' if seen_match and seen_match.group(1) == 'true' else 'NEW'

    print(f'[{seen:4s}] {pkg:25s} {title}: {text}')
"
        ;;
    *)
        # Default: JSON list of all notifications
        echo "$RAW" | python3 -c "
import sys, json, re

text = sys.stdin.read()
records = re.split(r'    NotificationRecord\(', text)
notifications = []

for rec in records[1:]:
    pkg_match = re.search(r'pkg=(\S+)', rec)
    title_match = re.search(r'android\.title=String \((.+?)\)', rec)
    text_match = re.search(r'android\.text=String \((.+?)\)', rec)
    subtext_match = re.search(r'android\.subText=String \((.+?)\)', rec)
    seen_match = re.search(r'seen=(true|false)', rec)
    when_match = re.search(r'when=(\d+)/', rec)
    key_match = re.search(r'key=(\S+)', rec)

    if pkg_match:
        notifications.append({
            'package': pkg_match.group(1),
            'title': title_match.group(1) if title_match else None,
            'text': text_match.group(1) if text_match else None,
            'subtext': subtext_match.group(1) if subtext_match else None,
            'seen': seen_match.group(1) == 'true' if seen_match else None,
            'when': int(when_match.group(1)) if when_match else None,
            'key': key_match.group(1) if key_match else None,
        })

json.dump(notifications, sys.stdout, indent=2, ensure_ascii=False)
print()
"
        ;;
esac
