#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# pdf-tool.sh -- PDF analysis and manipulation toolkit
# =============================================================================
# Unified wrapper for PDF operations: extract text, extract images, OCR,
# convert, compress, split, merge, info.
#
# Usage:
#   ~/bin/pdf-tool.sh text <file.pdf>              # Extract all text
#   ~/bin/pdf-tool.sh text <file.pdf> <page>       # Extract specific page
#   ~/bin/pdf-tool.sh ocr <file.pdf>               # OCR image-based PDF
#   ~/bin/pdf-tool.sh info <file.pdf>              # Page count, metadata
#   ~/bin/pdf-tool.sh to-images <file.pdf>         # Extract pages as PNG
#   ~/bin/pdf-tool.sh compress <in.pdf> <out.pdf>  # Compress PDF
#   ~/bin/pdf-tool.sh split <file.pdf>             # Split into single pages
#   ~/bin/pdf-tool.sh merge <out.pdf> <a.pdf>...   # Merge multiple PDFs
# =============================================================================

set -eu
CMD="${1:-help}"

case "$CMD" in
    text)
        PDF="${2:?Usage: pdf-tool.sh text <file.pdf> [page]}"
        PAGE="${3:-}"
        if [ -n "$PAGE" ]; then
            pdftotext -layout -f "$PAGE" -l "$PAGE" "$PDF" -
        else
            pdftotext -layout "$PDF" -
        fi
        ;;
    ocr)
        PDF="${2:?Usage: pdf-tool.sh ocr <file.pdf>}"
        TMP=$(mktemp -d)
        pdftoppm -r 200 -png "$PDF" "$TMP/page" 2>/dev/null
        for img in "$TMP"/page-*.png; do
            tesseract "$img" - -l eng+spa 2>/dev/null
            echo ""
        done
        rm -rf "$TMP"
        ;;
    info)
        PDF="${2:?Usage: pdf-tool.sh info <file.pdf>}"
        pdfinfo "$PDF"
        ;;
    to-images)
        PDF="${2:?Usage: pdf-tool.sh to-images <file.pdf> [out-prefix]}"
        PREFIX="${3:-$(basename "$PDF" .pdf)}"
        pdftoppm -r 150 -png "$PDF" "$PREFIX"
        ls "${PREFIX}"*.png
        ;;
    compress)
        IN="${2:?Usage: pdf-tool.sh compress <in.pdf> <out.pdf>}"
        OUT="${3:?}"
        gs -sDEVICE=pdfwrite -dCompatibilityLevel=1.4 -dPDFSETTINGS=/ebook \
           -dNOPAUSE -dQUIET -dBATCH -sOutputFile="$OUT" "$IN"
        echo "Compressed: $(du -h "$IN" | cut -f1) -> $(du -h "$OUT" | cut -f1)"
        ;;
    split)
        PDF="${2:?Usage: pdf-tool.sh split <file.pdf>}"
        PREFIX="$(basename "$PDF" .pdf)"
        PAGES=$(pdfinfo "$PDF" | awk '/^Pages:/{print $2}')
        for i in $(seq 1 "$PAGES"); do
            pdftoppm -f "$i" -l "$i" "$PDF" "${PREFIX}_page${i}" 2>/dev/null || true
        done
        echo "Split into $PAGES pages"
        ;;
    merge)
        OUT="${2:?Usage: pdf-tool.sh merge <out.pdf> <in1.pdf> <in2.pdf> ...}"
        shift 2
        gs -dBATCH -dNOPAUSE -q -sDEVICE=pdfwrite -sOutputFile="$OUT" "$@"
        echo "Merged $# PDFs -> $OUT"
        ;;
    help|*)
        head -19 "$0" | tail -17 | sed 's/^# //;s/^#//'
        ;;
esac
