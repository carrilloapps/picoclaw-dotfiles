#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# image-tool.sh -- Image analysis and manipulation toolkit
# =============================================================================
# Unified wrapper: OCR, resize, convert, info, crop, rotate, annotate,
# combine, thumbnail, histogram, metadata.
#
# Usage:
#   ~/bin/image-tool.sh ocr <image>                    # Extract text (multi-lang)
#   ~/bin/image-tool.sh info <image>                   # Dimensions, format, metadata
#   ~/bin/image-tool.sh resize <in> <out> <WxH>        # Resize (e.g. 800x600)
#   ~/bin/image-tool.sh convert <in> <out>             # Convert format by extension
#   ~/bin/image-tool.sh thumbnail <in> <out> [size]    # Thumbnail (default 200x200)
#   ~/bin/image-tool.sh crop <in> <out> <WxH+X+Y>      # Crop region
#   ~/bin/image-tool.sh rotate <in> <out> <degrees>    # Rotate
#   ~/bin/image-tool.sh annotate <in> <out> <text>     # Add text overlay
#   ~/bin/image-tool.sh combine <out> <img1> <img2>... # Horizontal combine
#   ~/bin/image-tool.sh meta <image>                   # EXIF metadata
#   ~/bin/image-tool.sh compress <in> <out> [quality]  # Reduce file size (default 85)
# =============================================================================

set -eu
CMD="${1:-help}"

case "$CMD" in
    ocr)
        IMG="${2:?Usage: image-tool.sh ocr <image> [lang]}"
        LANG="${3:-eng+spa}"
        tesseract "$IMG" - -l "$LANG" 2>/dev/null
        ;;
    info)
        IMG="${2:?Usage: image-tool.sh info <image>}"
        identify -format "Format: %m\nDimensions: %wx%h\nDepth: %z-bit\nColors: %c\nSize: %B bytes\n" "$IMG"
        ;;
    resize)
        IN="${2:?Usage: image-tool.sh resize <in> <out> <WxH>}"
        OUT="${3:?}"
        SIZE="${4:?}"
        convert "$IN" -resize "$SIZE" "$OUT"
        echo "Resized: $OUT ($(identify -format '%wx%h' "$OUT"))"
        ;;
    convert)
        IN="${2:?Usage: image-tool.sh convert <in> <out>}"
        OUT="${3:?}"
        convert "$IN" "$OUT"
        echo "Converted: $IN -> $OUT"
        ;;
    thumbnail)
        IN="${2:?Usage: image-tool.sh thumbnail <in> <out> [size]}"
        OUT="${3:?}"
        SIZE="${4:-200x200}"
        convert "$IN" -thumbnail "${SIZE}^" -gravity center -extent "$SIZE" "$OUT"
        ;;
    crop)
        IN="${2:?Usage: image-tool.sh crop <in> <out> <WxH+X+Y>}"
        OUT="${3:?}"
        REGION="${4:?}"
        convert "$IN" -crop "$REGION" "$OUT"
        ;;
    rotate)
        IN="${2:?Usage: image-tool.sh rotate <in> <out> <degrees>}"
        OUT="${3:?}"
        DEG="${4:?}"
        convert "$IN" -rotate "$DEG" "$OUT"
        ;;
    annotate)
        IN="${2:?Usage: image-tool.sh annotate <in> <out> <text>}"
        OUT="${3:?}"
        TEXT="${4:?}"
        convert "$IN" -gravity south -fill white -undercolor '#00000080' -pointsize 24 -annotate +0+20 " $TEXT " "$OUT"
        ;;
    combine)
        OUT="${2:?Usage: image-tool.sh combine <out> <img1> <img2>...}"
        shift 2
        convert "$@" +append "$OUT"
        ;;
    meta)
        IMG="${2:?Usage: image-tool.sh meta <image>}"
        identify -verbose "$IMG" | grep -iE "^\s+(Exif:|Make|Model|DateTime|GPS|ISO|FNumber|FocalLength|ImageDescription|Software|Copyright|Orientation)" | head -30
        ;;
    compress)
        IN="${2:?Usage: image-tool.sh compress <in> <out> [quality]}"
        OUT="${3:?}"
        Q="${4:-85}"
        convert "$IN" -quality "$Q" -strip "$OUT"
        SIZEIN=$(stat -c%s "$IN" 2>/dev/null || wc -c < "$IN")
        SIZEOUT=$(stat -c%s "$OUT" 2>/dev/null || wc -c < "$OUT")
        echo "Compressed: ${SIZEIN} -> ${SIZEOUT} bytes ($(( 100 - (SIZEOUT * 100 / SIZEIN) ))% reduction)"
        ;;
    help|*)
        head -21 "$0" | tail -19 | sed 's/^# //;s/^#//'
        ;;
esac
