#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# document-tool.sh -- Universal document conversion via pandoc
# =============================================================================
# Convert between markdown, PDF, DOCX, HTML, EPUB, RTF, ODT, LaTeX, etc.
# Supports 40+ formats via pandoc.
#
# Usage:
#   ~/bin/document-tool.sh convert <in> <out>      # Auto-detect formats by extension
#   ~/bin/document-tool.sh md2pdf <in.md> <out.pdf>
#   ~/bin/document-tool.sh docx2md <in.docx> <out.md>
#   ~/bin/document-tool.sh html2pdf <in.html> <out.pdf>
#   ~/bin/document-tool.sh md2docx <in.md> <out.docx>
#   ~/bin/document-tool.sh md2html <in.md> <out.html>
#   ~/bin/document-tool.sh to-epub <in> <out.epub>
#   ~/bin/document-tool.sh wordcount <file>         # Count words
#   ~/bin/document-tool.sh toc <file.md>            # Generate table of contents
# =============================================================================

set -eu
CMD="${1:-help}"

case "$CMD" in
    convert)
        IN="${2:?Usage: document-tool.sh convert <in> <out>}"
        OUT="${3:?}"
        pandoc "$IN" -o "$OUT"
        echo "Converted: $IN -> $OUT"
        ;;
    md2pdf|html2pdf)
        IN="${2:?}"; OUT="${3:?}"
        # Pandoc needs a LaTeX engine for PDF; use wkhtmltopdf fallback via HTML
        pandoc "$IN" -o "$OUT" --pdf-engine=xelatex 2>/dev/null || \
        pandoc "$IN" -o "$OUT" 2>&1 | tail -3
        ;;
    docx2md)
        pandoc "${2:?}" -f docx -t gfm -o "${3:?}"
        ;;
    md2docx)
        pandoc "${2:?}" -f gfm -t docx -o "${3:?}"
        ;;
    md2html)
        pandoc "${2:?}" -f gfm -t html5 -s --metadata title="$(basename "${2}" .md)" -o "${3:?}"
        ;;
    to-epub)
        pandoc "${2:?}" -o "${3:?}" --metadata title="$(basename "${2}")"
        ;;
    wordcount)
        F="${2:?}"
        case "$F" in
            *.md|*.txt) wc -w "$F" | awk '{print $1, "words"}' ;;
            *) pandoc "$F" -t plain 2>/dev/null | wc -w | awk '{print $1, "words"}' ;;
        esac
        ;;
    toc)
        F="${2:?}"
        pandoc "$F" --toc --standalone -t markdown 2>/dev/null | awk '/^- / || /^  +- /' | head -50
        ;;
    help|*)
        head -16 "$0" | tail -14 | sed 's/^# //;s/^#//'
        ;;
esac
