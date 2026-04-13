#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# code-run.sh -- Polyglot sandboxed code execution
# =============================================================================
# Run snippets in 15+ languages with timeouts and output capture. Handles
# compilation for Go/Rust/Zig/Java/Kotlin transparently.
#
# Usage:
#   ~/bin/code-run.sh <lang> "<code>"               # Inline code
#   ~/bin/code-run.sh <lang>-file <file>            # Run a file
#   ~/bin/code-run.sh list                          # List installed languages
#
# Supported:
#   py  / python    -- Python 3
#   node / js       -- Node.js
#   deno            -- Deno (TypeScript-ready, secure by default)
#   bash            -- Bash
#   go              -- Go (compiled + run)
#   rust            -- Rust (rustc + run)
#   php             -- PHP 8
#   ruby / rb       -- Ruby
#   perl / pl       -- Perl
#   lua             -- Lua 5.4
#   java            -- Java (single-file, Java 11+)
#   kotlin / kt     -- Kotlin (JVM)
#   swift           -- Swift
#   elixir / ex     -- Elixir
#   zig             -- Zig
#   sql             -- SQLite query
#   awk             -- AWK one-liner
#   sed             -- sed expression (data on stdin via STDIN env)
#   eval            -- Safe Python expression evaluator
#
# Environment:
#   TIMEOUT         -- seconds (default 30)
#   WORKDIR         -- working dir (default $PREFIX/tmp)
# =============================================================================

set -u
TIMEOUT="${TIMEOUT:-30}"
WORKDIR="${WORKDIR:-$PREFIX/tmp}"
mkdir -p "$WORKDIR"
CMD="${1:-help}"
CODE="${2:-}"

_run() {
    timeout "$TIMEOUT" "$@" 2>&1 | head -5000
}

_compile_run() {
    local ext="$1" compile="$2" run="$3"
    local src="$WORKDIR/snippet_$$${ext}"
    local bin="$WORKDIR/snippet_$$_bin"
    echo "$CODE" > "$src"
    if eval "$compile" > /tmp/compile.log 2>&1; then
        eval "$run" 2>&1 | head -5000
    else
        echo "=== compile error ==="
        cat /tmp/compile.log
    fi
    rm -f "$src" "$bin" /tmp/compile.log 2>/dev/null
}

case "$CMD" in
    # --- Interpreted ---
    py|python)
        cd "$WORKDIR" && echo "$CODE" | _run python3 -
        ;;
    py-file|python-file)
        cd "$WORKDIR" && _run python3 "$CODE"
        ;;
    node|js)
        cd "$WORKDIR" && echo "$CODE" | _run node
        ;;
    deno)
        cd "$WORKDIR" && echo "$CODE" | _run deno run --allow-read --allow-net -
        ;;
    bash|sh)
        cd "$WORKDIR" && echo "$CODE" | _run bash
        ;;
    php)
        cd "$WORKDIR" && echo "<?php $CODE" | _run php
        ;;
    ruby|rb)
        cd "$WORKDIR" && echo "$CODE" | _run ruby
        ;;
    perl|pl)
        cd "$WORKDIR" && echo "$CODE" | _run perl
        ;;
    lua)
        cd "$WORKDIR" && echo "$CODE" | _run lua5.4
        ;;
    elixir|ex)
        cd "$WORKDIR" && echo "$CODE" | _run elixir
        ;;

    # --- Compiled ---
    go)
        SRC="$WORKDIR/main_$$.go"
        # Wrap in main if user provided bare code
        if ! echo "$CODE" | grep -q "func main"; then
            echo -e "package main\n\nimport (\n\t\"fmt\"\n)\n\nfunc main() {\n$CODE\n}" > "$SRC"
        else
            echo "$CODE" > "$SRC"
        fi
        _run go run "$SRC"
        rm -f "$SRC"
        ;;
    rust)
        SRC="$WORKDIR/main_$$.rs"
        BIN="$WORKDIR/main_$$"
        if ! echo "$CODE" | grep -q "fn main"; then
            echo -e "fn main() {\n$CODE\n}" > "$SRC"
        else
            echo "$CODE" > "$SRC"
        fi
        if rustc -O "$SRC" -o "$BIN" 2>&1; then _run "$BIN"; fi
        rm -f "$SRC" "$BIN"
        ;;
    zig)
        SRC="$WORKDIR/main_$$.zig"
        echo "$CODE" > "$SRC"
        _run zig run "$SRC"
        rm -f "$SRC"
        ;;
    java)
        # Requires class name matching file name in Java 11+; use single-file mode
        SRC="$WORKDIR/Main_$$.java"
        # Wrap bare code in Main class
        if ! echo "$CODE" | grep -q "class "; then
            echo -e "public class Main_$$ { public static void main(String[] args) {\n$CODE\n} }" > "$SRC"
        else
            echo "$CODE" > "$SRC"
        fi
        _run java "$SRC"
        rm -f "$SRC"
        ;;
    kotlin|kt)
        SRC="$WORKDIR/main_$$.kts"
        echo "$CODE" > "$SRC"
        _run kotlinc -script "$SRC"
        rm -f "$SRC"
        ;;
    swift)
        SRC="$WORKDIR/main_$$.swift"
        echo "$CODE" > "$SRC"
        _run swift "$SRC"
        rm -f "$SRC"
        ;;

    # --- Data / shell-embedded ---
    sql)
        DB="${3:-:memory:}"
        echo "$CODE" | _run sqlite3 "$DB"
        ;;
    awk)
        echo "${STDIN:-}" | _run awk "$CODE"
        ;;
    sed)
        echo "${STDIN:-}" | _run sed -E "$CODE"
        ;;
    eval)
        python3 -c "
import math, json, datetime, re, statistics
safe = {'__builtins__': {}, 'math': math, 'json': json, 'datetime': datetime,
        're': re, 'statistics': statistics, 'abs': abs, 'len': len, 'min': min,
        'max': max, 'sum': sum, 'round': round, 'int': int, 'float': float,
        'str': str, 'list': list, 'dict': dict, 'tuple': tuple, 'set': set,
        'range': range, 'sorted': sorted, 'reversed': reversed, 'enumerate': enumerate,
        'zip': zip, 'map': map, 'filter': filter, 'any': any, 'all': all}
try:
    result = eval('''$CODE''', safe, {})
    print(result)
except Exception as e:
    print(f'Error: {e}')
"
        ;;

    # --- Introspection ---
    list)
        echo "Installed language runtimes:"
        for tool in python3 node deno bash php ruby perl lua5.4 go rustc zig java kotlinc swift elixir sqlite3 awk sed; do
            if command -v "$tool" >/dev/null 2>&1; then
                v=$("$tool" --version 2>&1 | head -1 || "$tool" -V 2>&1 | head -1)
                printf "  [V] %-10s %s\n" "$tool" "$v"
            else
                printf "  [ ] %-10s (not installed)\n" "$tool"
            fi
        done
        ;;
    help|*)
        head -40 "$0" | tail -38 | sed 's/^# //;s/^#//'
        ;;
esac
