#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# channels-tool.sh -- Live channel configuration (Telegram, WhatsApp, etc.)
# =============================================================================
# Add/remove/update channel settings from chat without restarting or editing
# files manually. Every change is snapshotted and written to config.json +
# security.yml, then the gateway is reloaded.
#
# Usage examples:
#   Telegram:
#     channels-tool.sh telegram add-user 123456789
#     channels-tool.sh telegram remove-user 123456789
#     channels-tool.sh telegram list-users
#     channels-tool.sh telegram set-token <BOT_TOKEN>
#     channels-tool.sh telegram set-owner <USER_ID>
#     channels-tool.sh telegram enable / disable
#
#   WhatsApp (native, Baileys-based — requires pairing):
#     channels-tool.sh whatsapp enable
#     channels-tool.sh whatsapp set-number <E164_NUMBER>
#     channels-tool.sh whatsapp add-allow <NUMBER>
#
#   Discord:
#     channels-tool.sh discord set-token <BOT_TOKEN>
#     channels-tool.sh discord add-guild <GUILD_ID>
#
#   Slack, Matrix, Signal, Feishu, Line, QQ, DingTalk, WeChat:
#     channels-tool.sh slack set-token <token>
#     channels-tool.sh matrix set-homeserver <url>
#
#   General:
#     channels-tool.sh list                      # Show all channels + states
#     channels-tool.sh enable <channel>
#     channels-tool.sh disable <channel>
#     channels-tool.sh status <channel>
#     channels-tool.sh reload                    # Reload gateway config
# =============================================================================

set -eu
CONFIG="$HOME/.picoclaw/config.json"
SECURITY="$HOME/.picoclaw/.security.yml"
SNAPSHOTS="$HOME/.picoclaw/snapshots"
mkdir -p "$SNAPSHOTS"

CHANNEL="${1:-help}"
ACTION="${2:-}"

snapshot_config() {
    cp "$CONFIG" "$SNAPSHOTS/config-pre-$(date +%Y%m%d-%H%M%S).json"
}

set_json() {
    # Update config.json at jq path
    local path="$1" value="$2"
    snapshot_config
    local tmp=$(mktemp)
    jq "$path = $value" "$CONFIG" > "$tmp" && mv "$tmp" "$CONFIG"
    chmod 600 "$CONFIG"
}

reload_gateway() {
    curl -sf -X POST http://127.0.0.1:18790/reload >/dev/null 2>&1 && \
        echo "Gateway reloaded" || {
            tmux kill-session -t picoclaw 2>/dev/null
            sleep 2
            tmux new-session -d -s picoclaw "SSL_CERT_FILE=/data/data/com.termux/files/usr/etc/tls/cert.pem $HOME/picoclaw.bin gateway > $HOME/.picoclaw/gateway.log 2>&1"
            sleep 5
            echo "Gateway restarted"
        }
}

set_security_yaml() {
    # Update a top-level channel field in security.yml
    local channel="$1" field="$2" value="$3"
    python3 - "$SECURITY" "$channel" "$field" "$value" <<'PYEOF'
import sys, yaml
path, ch, field, val = sys.argv[1:]
try:
    d = yaml.safe_load(open(path)) or {}
except Exception:
    d = {}
d.setdefault('channels', {}).setdefault(ch, {})[field] = val
with open(path, 'w') as f:
    yaml.safe_dump(d, f, default_flow_style=False)
print(f'security.yml: channels.{ch}.{field} = "***"')
PYEOF
    chmod 600 "$SECURITY"
}

case "$CHANNEL" in
    # =========================================================================
    # TELEGRAM
    # =========================================================================
    telegram)
        case "$ACTION" in
            add-user)
                USER_ID="${3:?Usage: channels-tool.sh telegram add-user <id>}"
                snapshot_config
                python3 -c "
import json
with open('$CONFIG') as f: c = json.load(f)
allow = c['channels'].setdefault('telegram', {}).setdefault('allow_from', [])
uid = int('$USER_ID')
if uid in allow:
    print(f'User $USER_ID already authorized (no change)')
else:
    allow.append(uid)
    c['channels']['telegram']['allow_from'] = allow
    with open('$CONFIG', 'w') as f: json.dump(c, f, indent=2)
    print(f'Added user $USER_ID to telegram.allow_from')
"
                reload_gateway
                ;;
            remove-user)
                USER_ID="${3:?}"
                python3 -c "
import json
with open('$CONFIG') as f: c = json.load(f)
allow = c['channels'].get('telegram', {}).get('allow_from', [])
uid = int('$USER_ID')
before = len(allow)
allow = [x for x in allow if x != uid]   # strip ALL occurrences
c['channels']['telegram']['allow_from'] = allow
with open('$CONFIG', 'w') as f: json.dump(c, f, indent=2)
removed = before - len(allow)
print(f'Removed user $USER_ID ({removed} occurrence(s))' if removed else f'User $USER_ID was not in allow_from')
"
                reload_gateway
                ;;
            dedupe-users)
                # Collapse duplicates in allow_from, preserve first-seen order
                snapshot_config
                python3 -c "
import json
with open('$CONFIG') as f: c = json.load(f)
allow = c['channels'].get('telegram', {}).get('allow_from', [])
seen, deduped = set(), []
for uid in allow:
    if uid not in seen:
        seen.add(uid); deduped.append(uid)
removed = len(allow) - len(deduped)
c['channels']['telegram']['allow_from'] = deduped
with open('$CONFIG', 'w') as f: json.dump(c, f, indent=2)
print(f'Deduplicated {removed} duplicate entries; final list: {deduped}')
"
                reload_gateway
                ;;
            list-users)
                jq '.channels.telegram.allow_from // []' "$CONFIG"
                ;;
            set-token)
                TOKEN="${3:?}"
                set_security_yaml telegram token "$TOKEN"
                reload_gateway
                ;;
            set-owner)
                USER_ID="${3:?}"
                set_json '.channels.telegram.allow_from' "[$USER_ID]"
                python3 -c "
import json
with open('$CONFIG') as f: c = json.load(f)
c['channels']['telegram']['allow_from'] = [int('$USER_ID')]
with open('$CONFIG', 'w') as f: json.dump(c, f, indent=2)
print(f'Set telegram owner = $USER_ID')
"
                reload_gateway
                ;;
            enable)
                python3 -c "
import json
with open('$CONFIG') as f: c = json.load(f)
c['channels'].setdefault('telegram', {})['enabled'] = True
with open('$CONFIG', 'w') as f: json.dump(c, f, indent=2)
print('Telegram enabled')
"
                reload_gateway
                ;;
            disable)
                python3 -c "
import json
with open('$CONFIG') as f: c = json.load(f)
c['channels']['telegram']['enabled'] = False
with open('$CONFIG', 'w') as f: json.dump(c, f, indent=2)
print('Telegram disabled')
"
                reload_gateway
                ;;
            status)
                jq '.channels.telegram' "$CONFIG"
                ;;
            *)
                echo "Telegram actions: add-user <id> | remove-user <id> | dedupe-users | list-users | set-token <t> | set-owner <id> | enable | disable | status"
                ;;
        esac
        ;;

    # =========================================================================
    # WHATSAPP
    # =========================================================================
    whatsapp)
        case "$ACTION" in
            enable)
                python3 -c "
import json
with open('$CONFIG') as f: c = json.load(f)
c['channels'].setdefault('whatsapp', {})['enabled'] = True
with open('$CONFIG', 'w') as f: json.dump(c, f, indent=2)
print('WhatsApp enabled (native mode). Pair via: picoclaw whatsapp pair')
"
                reload_gateway
                ;;
            disable)
                python3 -c "
import json
with open('$CONFIG') as f: c = json.load(f)
c['channels']['whatsapp']['enabled'] = False
with open('$CONFIG', 'w') as f: json.dump(c, f, indent=2)
print('WhatsApp disabled')
"
                reload_gateway
                ;;
            set-number)
                NUM="${3:?}"
                python3 -c "
import json
with open('$CONFIG') as f: c = json.load(f)
c['channels'].setdefault('whatsapp', {})['phone_number'] = '$NUM'
with open('$CONFIG', 'w') as f: json.dump(c, f, indent=2)
print(f'WhatsApp phone_number = $NUM')
"
                reload_gateway
                ;;
            add-allow)
                NUM="${3:?}"
                python3 -c "
import json
with open('$CONFIG') as f: c = json.load(f)
allow = c['channels'].setdefault('whatsapp', {}).setdefault('allow_from', [])
if '$NUM' not in allow: allow.append('$NUM')
with open('$CONFIG', 'w') as f: json.dump(c, f, indent=2)
print(f'WhatsApp allow_from += $NUM')
"
                reload_gateway
                ;;
            remove-allow)
                NUM="${3:?}"
                python3 -c "
import json
with open('$CONFIG') as f: c = json.load(f)
allow = c['channels']['whatsapp'].get('allow_from', [])
if '$NUM' in allow: allow.remove('$NUM')
with open('$CONFIG', 'w') as f: json.dump(c, f, indent=2)
print(f'WhatsApp allow_from -= $NUM')
"
                reload_gateway
                ;;
            status)
                jq '.channels.whatsapp' "$CONFIG"
                ;;
            *)
                echo "WhatsApp actions: enable | disable | set-number <e164> | add-allow <n> | remove-allow <n> | status"
                ;;
        esac
        ;;

    # =========================================================================
    # DISCORD, SLACK, MATRIX, FEISHU, LINE, QQ, DINGTALK, WECHAT, SIGNAL
    # Generic set-token / set-field / allow-from / enable / disable
    # =========================================================================
    discord|slack|matrix|feishu|line|qq|dingtalk|wecom|weixin|irc|signal|onebot)
        case "$ACTION" in
            enable|disable)
                ENABLED=$([ "$ACTION" = "enable" ] && echo true || echo false)
                python3 -c "
import json
with open('$CONFIG') as f: c = json.load(f)
c['channels'].setdefault('$CHANNEL', {})['enabled'] = $ENABLED
with open('$CONFIG', 'w') as f: json.dump(c, f, indent=2)
print(f'$CHANNEL: $ENABLED')
"
                reload_gateway
                ;;
            set-token|set-field)
                # set-field <field> <value>
                FIELD="${3:?}"; VAL="${4:-}"
                if [ "$ACTION" = "set-token" ]; then
                    set_security_yaml "$CHANNEL" token "$FIELD"
                else
                    python3 -c "
import json
with open('$CONFIG') as f: c = json.load(f)
c['channels'].setdefault('$CHANNEL', {})['$FIELD'] = '$VAL'
with open('$CONFIG', 'w') as f: json.dump(c, f, indent=2)
print(f'$CHANNEL.$FIELD = $VAL')
"
                fi
                reload_gateway
                ;;
            add-allow|remove-allow)
                VAL="${3:?}"
                OP=$([ "$ACTION" = "add-allow" ] && echo '+=' || echo '-=')
                python3 -c "
import json
with open('$CONFIG') as f: c = json.load(f)
allow = c['channels'].setdefault('$CHANNEL', {}).setdefault('allow_from', [])
val = '$VAL'
if '$ACTION' == 'add-allow' and val not in allow: allow.append(val)
if '$ACTION' == 'remove-allow' and val in allow: allow.remove(val)
with open('$CONFIG', 'w') as f: json.dump(c, f, indent=2)
print(f'$CHANNEL allow_from: {allow}')
"
                reload_gateway
                ;;
            status)
                jq ".channels.$CHANNEL" "$CONFIG"
                ;;
            *)
                echo "$CHANNEL actions: enable | disable | set-token <t> | set-field <k> <v> | add-allow <v> | remove-allow <v> | status"
                ;;
        esac
        ;;

    # =========================================================================
    # GENERIC CHANNEL OPERATIONS
    # =========================================================================
    list)
        echo "Available channels and their state:"
        jq -r '.channels | to_entries[] | "\(.key)\t\(.value.enabled // false)"' "$CONFIG" | column -t
        ;;
    enable|disable)
        CH="${2:?}"
        ENABLED=$([ "$CHANNEL" = "enable" ] && echo true || echo false)
        python3 -c "
import json
with open('$CONFIG') as f: c = json.load(f)
c['channels'].setdefault('$CH', {})['enabled'] = $ENABLED
with open('$CONFIG', 'w') as f: json.dump(c, f, indent=2)
print(f'$CH: $ENABLED')
"
        reload_gateway
        ;;
    status)
        CH="${2:?}"
        jq ".channels.$CH" "$CONFIG"
        ;;
    reload)
        reload_gateway
        ;;
    help|*)
        head -38 "$0" | tail -36 | sed 's/^# //;s/^#//'
        ;;
esac
