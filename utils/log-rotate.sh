#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# log-rotate.sh -- Comprehensive log management for PicoClaw
# =============================================================================
# Keeps ALL log-like files under reasonable size limits. Runs hourly via cron.
# Tail-rotates files that exceed the size cap (keeps last N lines).
# No compression, no numbered backups — just fast in-place truncation.
#
# Defaults (override via env):
#   MAX_LOG_SIZE       = 2097152 (2 MB per file)
#   KEEP_LOG_LINES     = 5000
#   MAX_JSONL_SIZE     = 5242880 (5 MB for JSONL data/audit files)
#   KEEP_JSONL_LINES   = 10000
#   NPM_CACHE_MAX_MB   = 100
#   PIP_CACHE_MAX_MB   = 100
#
# Discovery: uses find to locate EVERY log-like file under $HOME and $PREFIX/tmp.
# Handles: .log, .out, .err, .jsonl (data), .txt (custom handler logs), panic dumps.
#
# Usage:
#   ~/bin/log-rotate.sh                 # Rotate everything (default)
#   ~/bin/log-rotate.sh --stats         # Show current sizes
#   ~/bin/log-rotate.sh --discover      # List every log-like file found
#   ~/bin/log-rotate.sh --file <path>   # Rotate one specific file
#   ~/bin/log-rotate.sh --aggressive    # Truncate more aggressively (1000 lines)
#   ~/bin/log-rotate.sh --clean-caches  # Purge npm/pip/apt caches
# =============================================================================

set -eu
MAX_SIZE="${MAX_LOG_SIZE:-2097152}"
KEEP_LINES="${KEEP_LOG_LINES:-5000}"
MAX_JSONL="${MAX_JSONL_SIZE:-5242880}"
KEEP_JSONL="${KEEP_JSONL_LINES:-10000}"
NPM_MAX_MB="${NPM_CACHE_MAX_MB:-100}"
PIP_MAX_MB="${PIP_CACHE_MAX_MB:-100}"

_size() { stat -c%s "$1" 2>/dev/null || echo 0; }
_human() { numfmt --to=iec --suffix=B "$1" 2>/dev/null || echo "${1}B"; }

# Discover every log-like file
discover_logs() {
    # Known locations + glob discovery
    (
        # Home root logs
        find "$HOME" -maxdepth 1 -type f \( -name '*.log' -o -name '*.out' -o -name '*.err' \) 2>/dev/null
        find "$HOME" -maxdepth 2 -type f -name '*.txt' -size +1M 2>/dev/null
        # .picoclaw tree
        find "$HOME/.picoclaw" -type f \( -name '*.log' -o -name '*.jsonl' \) 2>/dev/null
        # tmp dirs
        find "$PREFIX/tmp" -maxdepth 2 -type f \( -name '*.log' -o -name '*.out' \) -mtime +1 2>/dev/null
        # Termux boot logs
        find "$HOME/.termux" -type f -name '*.log' 2>/dev/null
        # npm / pip internal logs
        find "$HOME/.npm/_logs" -type f -name '*.log' 2>/dev/null
        find "$HOME/.cache" -type f -name '*.log' 2>/dev/null
        # Watchdog / service logs at top-level
        for f in watchdog.log cloudflare.log webhook-server.log webhook-audit.log \
                 failover.log memory-ingest.log custom-log.txt; do
            [ -f "$HOME/$f" ] && echo "$HOME/$f"
        done
        # Per-route logs under webhooks/
        find "$HOME/.picoclaw/webhooks" -type f \( -name '*.log' -o -name 'data.jsonl' \) 2>/dev/null
    ) | sort -u
}

# Classify file: returns "data" (big, many lines) or "log" (smaller, fewer lines)
classify() {
    local f="$1"
    case "$f" in
        *.jsonl|*/data.jsonl) echo "data" ;;
        *) echo "log" ;;
    esac
}

rotate_one() {
    local file="$1"
    [ -f "$file" ] || return 0
    local size klass keep maxsz
    size=$(_size "$file")
    klass=$(classify "$file")
    if [ "$klass" = "data" ]; then
        keep="$KEEP_JSONL"; maxsz="$MAX_JSONL"
    else
        keep="$KEEP_LINES"; maxsz="$MAX_SIZE"
    fi
    if [ "$size" -gt "$maxsz" ]; then
        local tmp="${file}.rot.$$"
        tail -n "$keep" "$file" > "$tmp" 2>/dev/null || return 0
        # Keep permissions
        chmod --reference="$file" "$tmp" 2>/dev/null || true
        mv "$tmp" "$file"
        local newsize=$(_size "$file")
        echo "rotated $(basename "$file"): $(_human "$size") -> $(_human "$newsize") ($klass)"
    fi
}

clean_npm_cache() {
    local size_kb=$(du -sk "$HOME/.npm" 2>/dev/null | cut -f1 || echo 0)
    local size_mb=$((size_kb / 1024))
    if [ "$size_mb" -gt "$NPM_MAX_MB" ]; then
        npm cache clean --force >/dev/null 2>&1 || true
        echo "cleaned npm cache (${size_mb}MB -> purged)"
    fi
}

clean_pip_cache() {
    if command -v pip >/dev/null 2>&1; then
        local size_kb
        size_kb=$(du -sk "$HOME/.cache/pip" 2>/dev/null | cut -f1 || echo 0)
        local size_mb=$((size_kb / 1024))
        if [ "$size_mb" -gt "$PIP_MAX_MB" ]; then
            pip cache purge >/dev/null 2>&1 || true
            echo "cleaned pip cache (${size_mb}MB -> purged)"
        fi
    fi
}

clean_pkg_cache() {
    # apt cache: rotate if >50MB
    local apt_dir="$PREFIX/var/cache/apt"
    if [ -d "$apt_dir" ]; then
        local size_kb=$(du -sk "$apt_dir" 2>/dev/null | cut -f1 || echo 0)
        if [ "$size_kb" -gt 51200 ]; then
            apt-get clean >/dev/null 2>&1 || true
            echo "cleaned apt cache (${size_kb}KB -> purged)"
        fi
    fi
}

clean_old_media() {
    # Media dir: anything >2 days AND already processed
    find "$HOME/media" -type f -mtime +2 -delete 2>/dev/null && echo "cleaned media >2 days" || true
}

clean_tmp() {
    # Termux tmp files older than 1 day
    find "$PREFIX/tmp" -type f -mtime +1 -delete 2>/dev/null || true
    # /tmp-like dir
    find "$HOME/.picoclaw/logs" -type f -name '*.log.*' -mtime +7 -delete 2>/dev/null || true
}

clean_backups() {
    # Backups older than 30 days (keeps recent ones)
    find "$HOME/.picoclaw/backups" -maxdepth 1 -type d -mtime +30 -exec rm -rf {} + 2>/dev/null || true
    find "$HOME/.picoclaw/snapshots" -maxdepth 1 -type d -mtime +14 -exec rm -rf {} + 2>/dev/null || true
    # Snapshots of config (from agent-self)
    find "$HOME/.picoclaw/snapshots" -maxdepth 1 -type f -name "config-*" -mtime +7 -delete 2>/dev/null || true
}

CMD="${1:---rotate}"

case "$CMD" in
    --discover)
        discover_logs
        ;;
    --stats)
        total=0; count=0
        echo "Log/data files managed by log-rotate:"
        printf "  %-60s %12s %s\n" "FILE" "SIZE" "CLASS"
        echo "  $(printf '%*s' 90 '' | tr ' ' '-')"
        while IFS= read -r f; do
            [ -f "$f" ] || continue
            size=$(_size "$f"); klass=$(classify "$f")
            printf "  %-60s %12s %s\n" "${f/#$HOME/~}" "$(_human "$size")" "$klass"
            total=$((total + size)); count=$((count + 1))
        done < <(discover_logs)
        echo "  $(printf '%*s' 90 '' | tr ' ' '-')"
        echo "  Total: $count files, $(_human "$total")"
        echo ""
        # Caches
        echo "Caches:"
        [ -d "$HOME/.npm" ] && echo "  npm cache: $(du -sh "$HOME/.npm" 2>/dev/null | cut -f1)"
        [ -d "$HOME/.cache/pip" ] && echo "  pip cache: $(du -sh "$HOME/.cache/pip" 2>/dev/null | cut -f1)"
        [ -d "$PREFIX/var/cache/apt" ] && echo "  apt cache: $(du -sh "$PREFIX/var/cache/apt" 2>/dev/null | cut -f1)"
        [ -d "$HOME/.picoclaw/backups" ] && echo "  backups:   $(du -sh "$HOME/.picoclaw/backups" 2>/dev/null | cut -f1)"
        [ -d "$HOME/media" ] && echo "  media:     $(du -sh "$HOME/media" 2>/dev/null | cut -f1)"
        ;;
    --file)
        rotate_one "${2:?Usage: log-rotate.sh --file <path>}"
        ;;
    --aggressive)
        KEEP_LINES=1000; KEEP_JSONL=2000
        MAX_SIZE=524288; MAX_JSONL=1048576
        while IFS= read -r f; do rotate_one "$f"; done < <(discover_logs)
        clean_npm_cache; clean_pip_cache; clean_pkg_cache; clean_tmp; clean_backups
        echo "aggressive rotation complete"
        ;;
    --clean-caches)
        clean_npm_cache
        clean_pip_cache
        clean_pkg_cache
        clean_old_media
        clean_tmp
        clean_backups
        ;;
    --rotate|*)
        changed=0
        while IFS= read -r f; do
            msg=$(rotate_one "$f")
            if [ -n "$msg" ]; then
                echo "[$(date '+%H:%M:%S')] $msg"
                changed=$((changed + 1))
            fi
        done < <(discover_logs)
        # Periodically clean caches too
        HOUR=$(date +%H)
        if [ "$HOUR" = "03" ]; then
            clean_npm_cache
            clean_pip_cache
            clean_pkg_cache
            clean_tmp
            clean_backups
        fi
        [ "$changed" -gt 0 ] && echo "rotated $changed files" || true
        ;;
esac
