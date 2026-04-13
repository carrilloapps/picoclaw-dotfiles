#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# qr-tool.sh -- QR code and barcode toolkit
# =============================================================================
# Generate QR codes (PNG/SVG/terminal) and scan barcodes from images.
# Uses ImageMagick and zbarimg. Works when qrencode isn't available.
#
# Usage:
#   ~/bin/qr-tool.sh gen <text> <out.png>              # Generate QR code image
#   ~/bin/qr-tool.sh gen-terminal <text>               # ASCII QR in terminal
#   ~/bin/qr-tool.sh scan <image>                      # Read QR/barcode from image
# =============================================================================

set -eu
CMD="${1:-help}"

# Check if zbar is available
has_zbar() { command -v zbarimg >/dev/null 2>&1; }

# Use Python qrcode library as a fallback when qrencode isn't available
generate_qr() {
    local text="$1"
    local out="$2"
    python3 - <<PYEOF
import subprocess, sys
try:
    import qrcode
except ImportError:
    subprocess.check_call([sys.executable, '-m', 'pip', 'install', '--quiet', 'qrcode[pil]'])
    import qrcode
qrcode.make("""$text""").save("$out")
print("Generated: $out")
PYEOF
}

case "$CMD" in
    gen)
        TEXT="${2:?Usage: qr-tool.sh gen <text> <out.png>}"
        OUT="${3:?}"
        generate_qr "$TEXT" "$OUT"
        ;;
    gen-terminal)
        TEXT="${2:?Usage: qr-tool.sh gen-terminal <text>}"
        python3 -c "
import subprocess, sys
try: import qrcode
except ImportError:
    subprocess.check_call([sys.executable,'-m','pip','install','--quiet','qrcode'])
    import qrcode
qr = qrcode.QRCode()
qr.add_data('''$TEXT''')
qr.make()
qr.print_ascii(invert=True)
"
        ;;
    scan)
        IMG="${2:?Usage: qr-tool.sh scan <image>}"
        if has_zbar; then
            zbarimg --quiet --raw "$IMG"
        else
            echo "ERROR: zbarimg not installed. Install: pkg install zbar-tools"
            exit 1
        fi
        ;;
    help|*)
        head -11 "$0" | tail -9 | sed 's/^# //;s/^#//'
        ;;
esac
