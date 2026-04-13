#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# system-tool.sh -- Self-administration: backup, restore, upgrade, pkg mgmt
# =============================================================================
# The agent can use this to fully manage the PicoClaw instance: create backups,
# restore from backup, upgrade the PicoClaw binary, install/remove Termux
# packages, clean up, check disk usage — all from chat or CLI.
#
# Usage:
#   Backups:
#     system-tool.sh backup [name]           # Create backup (auto-named if none)
#     system-tool.sh backups                  # List all backups
#     system-tool.sh restore <name>           # Restore a backup (auto-snapshots first)
#     system-tool.sh export [file]            # Export to tar.gz (shareable)
#     system-tool.sh import <file.tar.gz>     # Import an exported backup
#     system-tool.sh cleanup-backups [days]   # Delete backups older than N days
#
#   Upgrades / Downgrades:
#     system-tool.sh upgrade picoclaw         # Latest PicoClaw binary from GitHub
#     system-tool.sh upgrade picoclaw <ver>   # Specific version (e.g. v0.2.6)
#     system-tool.sh upgrade scripts          # Pull latest utils/ from GitHub
#     system-tool.sh upgrade self             # Upgrade this dotfiles repo
#     system-tool.sh downgrade picoclaw <ver> # Downgrade to specific version
#     system-tool.sh version                  # Show current versions
#
#   Packages (Termux apt):
#     system-tool.sh pkg install <pkg>...    # Install package(s)
#     system-tool.sh pkg remove <pkg>...     # Remove package(s)
#     system-tool.sh pkg update              # Refresh package lists
#     system-tool.sh pkg upgrade             # Upgrade all installed
#     system-tool.sh pkg search <query>
#     system-tool.sh pkg installed           # List installed
#     system-tool.sh pkg show <pkg>
#     system-tool.sh pip install <pkg>
#     system-tool.sh npm install <pkg>
#
#   Services:
#     system-tool.sh services                 # Show all service status
#     system-tool.sh start <service>          # gateway, webhook, cloudflared
#     system-tool.sh stop <service>
#     system-tool.sh restart <service>
#
#   Maintenance:
#     system-tool.sh cleanup                  # Clean caches, tmp, old logs
#     system-tool.sh disk                     # Disk usage report
#     system-tool.sh health                   # Full system health check
#     system-tool.sh self-check               # Verify every script works
# =============================================================================

set -eu
HOME_DIR="$HOME"
BACKUPS="$HOME_DIR/.picoclaw/backups"
SNAPSHOTS="$HOME_DIR/.picoclaw/snapshots"
EXPORTS="$HOME_DIR/.picoclaw/exports"
mkdir -p "$BACKUPS" "$SNAPSHOTS" "$EXPORTS"

CMD="${1:-help}"
SUBCMD="${2:-}"

# =============================================================================
# Backups
# =============================================================================
do_backup() {
    local name="${1:-backup-$(date +%Y%m%d-%H%M%S)}"
    local dir="$BACKUPS/$name"
    mkdir -p "$dir"
    [ -f "$HOME_DIR/.picoclaw/config.json" ] && cp "$HOME_DIR/.picoclaw/config.json" "$dir/"
    [ -f "$HOME_DIR/.picoclaw/.security.yml" ] && cp "$HOME_DIR/.picoclaw/.security.yml" "$dir/"
    [ -f "$HOME_DIR/.picoclaw/workspace/AGENT.md" ] && cp "$HOME_DIR/.picoclaw/workspace/AGENT.md" "$dir/"
    [ -f "$HOME_DIR/.picoclaw/workspace/knowledge/rag.db" ] && cp "$HOME_DIR/.picoclaw/workspace/knowledge/rag.db" "$dir/"
    [ -f "$HOME_DIR/.picoclaw_keys" ] && cp "$HOME_DIR/.picoclaw_keys" "$dir/"
    [ -f "$HOME_DIR/.cloudflared/token" ] && cp "$HOME_DIR/.cloudflared/token" "$dir/cloudflared.token"
    crontab -l > "$dir/crontab.txt" 2>/dev/null || true
    # Snapshot metadata
    cat > "$dir/meta.json" <<JSON
{
  "name": "$name",
  "created": "$(date -Iseconds)",
  "picoclaw_version": "$($HOME_DIR/picoclaw.bin version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)",
  "scripts_count": $(ls $HOME_DIR/bin/*.sh $HOME_DIR/bin/*.py 2>/dev/null | wc -l),
  "rag_chunks": $(sqlite3 "$HOME_DIR/.picoclaw/workspace/knowledge/rag.db" "SELECT COUNT(*) FROM docs" 2>/dev/null || echo 0),
  "agent_md_lines": $(wc -l < "$HOME_DIR/.picoclaw/workspace/AGENT.md" 2>/dev/null || echo 0)
}
JSON
    chmod 700 "$dir"
    find "$dir" -type f -exec chmod 600 {} \;
    echo "Backup created: $dir"
    du -sh "$dir"
}

do_restore() {
    local name="${1:?}"
    local dir="$BACKUPS/$name"
    [ -d "$dir" ] || { echo "Backup not found: $name"; exit 1; }
    # Snapshot current state first
    do_backup "pre-restore-$(date +%Y%m%d-%H%M%S)" > /dev/null
    echo "Restoring $name..."
    [ -f "$dir/config.json" ] && cp "$dir/config.json" "$HOME_DIR/.picoclaw/config.json" && chmod 600 "$HOME_DIR/.picoclaw/config.json"
    [ -f "$dir/.security.yml" ] && cp "$dir/.security.yml" "$HOME_DIR/.picoclaw/.security.yml" && chmod 600 "$HOME_DIR/.picoclaw/.security.yml"
    [ -f "$dir/AGENT.md" ] && cp "$dir/AGENT.md" "$HOME_DIR/.picoclaw/workspace/AGENT.md"
    [ -f "$dir/rag.db" ] && cp "$dir/rag.db" "$HOME_DIR/.picoclaw/workspace/knowledge/rag.db"
    [ -f "$dir/.picoclaw_keys" ] && cp "$dir/.picoclaw_keys" "$HOME_DIR/.picoclaw_keys" && chmod 600 "$HOME_DIR/.picoclaw_keys"
    [ -f "$dir/cloudflared.token" ] && cp "$dir/cloudflared.token" "$HOME_DIR/.cloudflared/token" && chmod 600 "$HOME_DIR/.cloudflared/token"
    [ -f "$dir/crontab.txt" ] && crontab "$dir/crontab.txt"
    echo "Restored. Restart gateway: ~/bin/system-tool.sh restart gateway"
}

# =============================================================================
# Main dispatch
# =============================================================================
case "$CMD" in
    # ---- Backups ----
    backup)
        do_backup "$SUBCMD"
        ;;
    backups)
        for d in "$BACKUPS"/*/; do
            [ -d "$d" ] || continue
            name=$(basename "$d")
            size=$(du -sh "$d" 2>/dev/null | cut -f1)
            when=$(jq -r .created "$d/meta.json" 2>/dev/null || stat -c %y "$d" | cut -d. -f1)
            echo "$name  $size  $when"
        done
        ;;
    restore)
        do_restore "$SUBCMD"
        ;;
    export)
        NAME="${2:-export-$(date +%Y%m%d-%H%M%S)}"
        OUT="$EXPORTS/$NAME.tar.gz"
        do_backup "$NAME" > /dev/null
        tar czf "$OUT" -C "$BACKUPS" "$NAME"
        chmod 600 "$OUT"
        echo "Exported: $OUT ($(du -sh "$OUT" | cut -f1))"
        ;;
    import)
        FILE="${2:?Usage: system-tool.sh import <file.tar.gz>}"
        [ -f "$FILE" ] || { echo "File not found: $FILE"; exit 1; }
        tar xzf "$FILE" -C "$BACKUPS"
        echo "Imported. List backups: ~/bin/system-tool.sh backups"
        ;;
    cleanup-backups)
        DAYS="${2:-30}"
        find "$BACKUPS" -maxdepth 1 -type d -mtime "+$DAYS" -exec rm -rf {} \; 2>/dev/null || true
        echo "Removed backups older than $DAYS days"
        ;;

    # ---- Upgrades ----
    upgrade)
        case "$SUBCMD" in
            picoclaw)
                VER="${3:-latest}"
                URL="https://github.com/sipeed/picoclaw/releases"
                [ "$VER" = "latest" ] && URL="$URL/latest/download" || URL="$URL/download/$VER"
                echo "Upgrading PicoClaw binary ($VER)..."
                do_backup "pre-upgrade-$(date +%Y%m%d-%H%M%S)" > /dev/null
                cd "$HOME_DIR"
                curl -sLO "$URL/picoclaw_Linux_arm64.tar.gz"
                tar xzf picoclaw_Linux_arm64.tar.gz
                # Preserve wrapper
                if [ -f "$HOME_DIR/picoclaw" ] && file "$HOME_DIR/picoclaw" 2>/dev/null | grep -q ELF; then
                    mv -f "$HOME_DIR/picoclaw" "$HOME_DIR/picoclaw.bin"
                else
                    # Already wrapper; don't touch it. Rename the new extracted binary
                    :
                fi
                chmod +x "$HOME_DIR/picoclaw.bin"
                rm -f picoclaw_Linux_arm64.tar.gz
                "$HOME_DIR/picoclaw" version 2>&1 | head -3
                echo "Restart gateway: ~/bin/system-tool.sh restart gateway"
                ;;
            scripts)
                # Pull latest utils/ from GitHub
                echo "Upgrading scripts from GitHub..."
                do_backup "pre-script-upgrade-$(date +%Y%m%d-%H%M%S)" > /dev/null
                BASE="https://raw.githubusercontent.com/carrilloapps/picoclaw-dotfiles/main/utils"
                for script in $(curl -sL https://api.github.com/repos/carrilloapps/picoclaw-dotfiles/contents/utils | jq -r '.[] | select(.type=="file") | .name'); do
                    case "$script" in
                        *.sh|*.py)
                            curl -sL "$BASE/$script" -o "$HOME_DIR/bin/$script.new" && \
                            mv "$HOME_DIR/bin/$script.new" "$HOME_DIR/bin/$script" && \
                            chmod 700 "$HOME_DIR/bin/$script" && \
                            echo "  ~/bin/$script"
                            ;;
                    esac
                done
                echo "Scripts upgraded."
                ;;
            self|dotfiles)
                DOTFILES="${DOTFILES_DIR:-$HOME_DIR/picoclaw-dotfiles}"
                if [ -d "$DOTFILES/.git" ]; then
                    cd "$DOTFILES" && git pull
                    echo "Run: cd $DOTFILES && bash utils/install.sh"
                else
                    git clone https://github.com/carrilloapps/picoclaw-dotfiles.git "$DOTFILES"
                    echo "Cloned. Run: cd $DOTFILES && bash utils/install.sh"
                fi
                ;;
            *)
                echo "upgrade targets: picoclaw [ver] | scripts | self"
                ;;
        esac
        ;;
    downgrade)
        TGT="${SUBCMD:?}"; VER="${3:?Usage: downgrade picoclaw <version>}"
        [ "$TGT" = "picoclaw" ] && exec "$0" upgrade picoclaw "$VER" || echo "Unknown downgrade target: $TGT"
        ;;
    version)
        echo "PicoClaw:    $("$HOME_DIR/picoclaw" version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
        echo "Node:        $(node -v 2>/dev/null)"
        echo "Python:      $(python3 --version 2>&1 | awk '{print $2}')"
        echo "Go:          $(go version 2>&1 | awk '{print $3}')"
        echo "cloudflared: $("$HOME_DIR/bin/cloudflared" --version 2>&1 | head -1)"
        echo "chromium:    $(chromium-browser --version 2>&1 | head -1 || echo 'not installed')"
        ;;

    # ---- Packages ----
    pkg)
        OP="${SUBCMD:?}"; shift 2
        case "$OP" in
            install|add) pkg install -y "$@" ;;
            remove|rm) pkg uninstall -y "$@" ;;
            update) pkg update 2>&1 | tail -5 ;;
            upgrade) pkg upgrade -y 2>&1 | tail -5 ;;
            search) pkg search "$@" ;;
            installed|list) dpkg -l 2>/dev/null | tail -n +6 | awk '{print $2, $3}' ;;
            show|info) pkg show "$@" ;;
            *) echo "pkg ops: install | remove | update | upgrade | search | installed | show"; exit 1 ;;
        esac
        ;;
    pip)
        shift; pip install "$@"
        ;;
    npm)
        shift; npm install -g "$@"
        ;;

    # ---- Services ----
    services)
        for svc in sshd crond tmux; do
            if pgrep -x "$svc" >/dev/null 2>&1; then
                printf "  [OK] %-15s\n" "$svc"
            else
                printf "  [--] %-15s\n" "$svc"
            fi
        done
        # cloudflared (may be via proot)
        if pgrep -f "cloudflared tunnel" >/dev/null 2>&1; then
            printf "  [OK] %-15s\n" "cloudflared"
        else
            printf "  [--] %-15s\n" "cloudflared"
        fi
        # Special: gateway in tmux
        if pgrep -f "picoclaw.bin gateway" >/dev/null 2>&1; then
            echo "  [OK] picoclaw-gateway"
        else
            echo "  [--] picoclaw-gateway"
        fi
        # Webhook server
        if pgrep -f "webhook-server" >/dev/null 2>&1; then
            echo "  [OK] webhook-server"
        else
            echo "  [--] webhook-server"
        fi
        ;;
    start)
        SVC="${SUBCMD:?}"
        case "$SVC" in
            gateway) tmux new-session -d -s picoclaw "SSL_CERT_FILE=/data/data/com.termux/files/usr/etc/tls/cert.pem $HOME_DIR/picoclaw.bin gateway > $HOME_DIR/.picoclaw/gateway.log 2>&1" ;;
            webhook)
                # Launch via webhook-start.sh so .picoclaw_keys is sourced
                # (WEBHOOK_TOKEN, WEBHOOK_HMAC_SECRET, GITHUB_WEBHOOK_SECRET, CF_ACCESS_*).
                # Fall back to direct launch if the wrapper isn't present.
                if [ -x "$HOME_DIR/bin/webhook-start.sh" ]; then
                    tmux new-session -d -s webhook "$HOME_DIR/bin/webhook-start.sh > $HOME_DIR/webhook-server.log 2>&1"
                else
                    tmux new-session -d -s webhook "python3 $HOME_DIR/bin/webhook-server.py > $HOME_DIR/webhook-server.log 2>&1"
                fi
                ;;
            cloudflared|cf) "$HOME_DIR/bin/cloudflare-tool.sh" daemon ;;
            sshd) sshd ;;
            crond) crond ;;
            *) echo "Unknown service: $SVC"; exit 1 ;;
        esac
        echo "Started: $SVC"
        ;;
    stop)
        SVC="${SUBCMD:?}"
        case "$SVC" in
            gateway) tmux kill-session -t picoclaw 2>/dev/null; pkill -f "picoclaw.bin gateway" 2>/dev/null ;;
            webhook) tmux kill-session -t webhook 2>/dev/null; pkill -f webhook-server 2>/dev/null ;;
            cloudflared|cf) "$HOME_DIR/bin/cloudflare-tool.sh" stop ;;
            sshd) pkill sshd ;;
            crond) pkill crond ;;
            *) echo "Unknown service: $SVC"; exit 1 ;;
        esac
        echo "Stopped: $SVC"
        ;;
    restart)
        SVC="${SUBCMD:?}"
        "$0" stop "$SVC" 2>/dev/null || true
        sleep 2
        "$0" start "$SVC"
        ;;

    # ---- Maintenance ----
    cleanup)
        SAVED=0
        # Media cleanup
        if [ -x "$HOME_DIR/bin/media-cleanup.sh" ]; then
            "$HOME_DIR/bin/media-cleanup.sh"
        fi
        # Old log rotation
        find "$HOME_DIR" -maxdepth 2 -name "*.log" -size +10M -exec truncate -s 1M {} \; 2>/dev/null
        # Package cache
        pkg clean 2>&1 | tail -2
        # pip cache
        pip cache purge 2>&1 | tail -1
        # npm cache
        npm cache clean --force 2>&1 | tail -1
        # Old pyc
        find "$HOME_DIR" -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
        echo "Cleanup complete"
        ;;
    disk)
        df -h "$HOME_DIR" 2>/dev/null | tail -1
        echo ""
        echo "Top directories:"
        du -sh "$HOME_DIR"/.picoclaw/* "$HOME_DIR/media" "$HOME_DIR/bin" 2>/dev/null | sort -h | tail -10
        ;;
    health)
        "$0" version
        echo ""
        "$0" services
        echo ""
        "$0" disk
        echo ""
        echo "Memory (RAG):"
        [ -x "$HOME_DIR/bin/memory-ingest.sh" ] && "$HOME_DIR/bin/memory-ingest.sh" stats
        echo ""
        echo "Backups:"
        "$0" backups | head -5
        ;;
    self-check)
        echo "=== Script health check ==="
        fail=0
        for f in "$HOME_DIR"/bin/*.sh; do
            if ! bash -n "$f" 2>/dev/null; then
                echo "  [!!] $(basename "$f") syntax error"
                fail=$((fail+1))
            fi
        done
        for f in "$HOME_DIR"/bin/*.py; do
            if ! python3 -m py_compile "$f" 2>/dev/null; then
                echo "  [!!] $(basename "$f") syntax error"
                fail=$((fail+1))
            fi
        done
        echo "$fail failures"
        ;;

    help|*)
        head -52 "$0" | tail -50 | sed 's/^# //;s/^#//'
        ;;
esac
