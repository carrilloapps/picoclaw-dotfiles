#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# media-tool.sh -- Audio/video download, conversion, and processing
# =============================================================================
# Wraps yt-dlp + ffmpeg for full media pipeline: download from any site,
# extract audio, trim, convert, resize video, subtitle generation.
#
# Usage:
#   ~/bin/media-tool.sh download <url>                 # Download best video
#   ~/bin/media-tool.sh audio <url>                    # Extract audio (MP3)
#   ~/bin/media-tool.sh audio-ogg <url>                # Audio as OGG Opus
#   ~/bin/media-tool.sh info <url>                     # Video metadata (title, duration, formats)
#   ~/bin/media-tool.sh subtitles <url> [lang]         # Download subtitles
#   ~/bin/media-tool.sh trim <in> <out> <start> <end>  # Trim (HH:MM:SS or seconds)
#   ~/bin/media-tool.sh resize <in> <out> <HEIGHT>     # Resize video (e.g. 720)
#   ~/bin/media-tool.sh to-gif <in> <out.gif> [duration]
#   ~/bin/media-tool.sh extract-audio <in> <out.mp3>
#   ~/bin/media-tool.sh concat <out> <in1> <in2> ...
#   ~/bin/media-tool.sh merge-audio-video <video> <audio> <out>
#   ~/bin/media-tool.sh thumbnail <in> <out.jpg> [time]
#   ~/bin/media-tool.sh metadata <file>
# =============================================================================

set -eu
CMD="${1:-help}"
MEDIA_DIR="${HOME}/media"
mkdir -p "$MEDIA_DIR"

case "$CMD" in
    download)
        URL="${2:?}"
        cd "$MEDIA_DIR"
        yt-dlp -f "bv*+ba/b" --no-playlist -o "%(title).50s.%(ext)s" "$URL" 2>&1 | tail -3
        ;;
    audio)
        URL="${2:?}"
        cd "$MEDIA_DIR"
        yt-dlp -x --audio-format mp3 --audio-quality 0 --no-playlist -o "%(title).50s.%(ext)s" "$URL" 2>&1 | tail -3
        ;;
    audio-ogg)
        URL="${2:?}"
        cd "$MEDIA_DIR"
        yt-dlp -x --audio-format opus --no-playlist -o "%(title).50s.%(ext)s" "$URL" 2>&1 | tail -3
        ;;
    info)
        URL="${2:?}"
        yt-dlp --dump-single-json --no-playlist "$URL" 2>/dev/null | jq '{title, duration, uploader, description: (.description // "" | .[0:300]), view_count, formats: [.formats[] | {format_id, ext, resolution, vcodec, acodec, filesize}]}'
        ;;
    subtitles)
        URL="${2:?}"
        LANG="${3:-en}"
        cd "$MEDIA_DIR"
        yt-dlp --write-auto-sub --sub-lang "$LANG" --skip-download --convert-subs srt -o "%(title).50s" "$URL" 2>&1 | tail -3
        ;;
    trim)
        IN="${2:?}"; OUT="${3:?}"; START="${4:?}"; END="${5:?}"
        ffmpeg -y -i "$IN" -ss "$START" -to "$END" -c copy "$OUT" 2>&1 | tail -3
        ;;
    resize)
        IN="${2:?}"; OUT="${3:?}"; HEIGHT="${4:?}"
        ffmpeg -y -i "$IN" -vf "scale=-2:${HEIGHT}" -c:a copy "$OUT" 2>&1 | tail -3
        ;;
    to-gif)
        IN="${2:?}"; OUT="${3:?}"; DUR="${4:-10}"
        ffmpeg -y -t "$DUR" -i "$IN" -vf "fps=15,scale=480:-2:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse" "$OUT" 2>&1 | tail -3
        ;;
    extract-audio)
        IN="${2:?}"; OUT="${3:?}"
        ffmpeg -y -i "$IN" -q:a 0 -map a "$OUT" 2>&1 | tail -3
        ;;
    concat)
        OUT="${2:?}"
        shift 2
        TMP=$(mktemp)
        for f in "$@"; do echo "file '$(realpath "$f")'" >> "$TMP"; done
        ffmpeg -y -f concat -safe 0 -i "$TMP" -c copy "$OUT" 2>&1 | tail -3
        rm "$TMP"
        ;;
    merge-audio-video)
        V="${2:?}"; A="${3:?}"; OUT="${4:?}"
        ffmpeg -y -i "$V" -i "$A" -c:v copy -c:a aac -shortest "$OUT" 2>&1 | tail -3
        ;;
    thumbnail)
        IN="${2:?}"; OUT="${3:?}"; TIME="${4:-00:00:05}"
        ffmpeg -y -ss "$TIME" -i "$IN" -frames:v 1 -q:v 2 "$OUT" 2>&1 | tail -3
        ;;
    metadata)
        IN="${2:?}"
        ffprobe -v error -show_format -show_streams -of json "$IN" | jq '{format: {filename, format_name, duration, size, bit_rate, tags: .format.tags}, streams: [.streams[] | {codec_type, codec_name, width, height, sample_rate, channels}]}'
        ;;
    help|*)
        head -22 "$0" | tail -20 | sed 's/^# //;s/^#//'
        ;;
esac
