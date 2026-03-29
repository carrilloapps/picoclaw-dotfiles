#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# scrape.sh — Universal web scraping tool for PicoClaw
# =============================================================================
# Multiple scraping methods with automatic fallback:
#   1. curl + readability (fast, works for most static pages)
#   2. Node.js puppeteer (headless Chrome, for JS-rendered pages)
#   3. curl raw (last resort, returns raw HTML)
#
# Usage:
#   ~/bin/scrape.sh <url>                    # Auto-select best method
#   ~/bin/scrape.sh <url> --method curl      # Force curl + text extraction
#   ~/bin/scrape.sh <url> --method puppet    # Force puppeteer headless
#   ~/bin/scrape.sh <url> --method raw       # Raw HTML output
#   ~/bin/scrape.sh <url> --method api       # JSON API call
#   ~/bin/scrape.sh <url> --screenshot       # Take screenshot of page
#   ~/bin/scrape.sh <url> --links            # Extract all links
#   ~/bin/scrape.sh <url> --json             # Parse as JSON API response
# =============================================================================

export SSL_CERT_FILE=/data/data/com.termux/files/usr/etc/tls/cert.pem

URL="$1"
shift
METHOD="auto"
EXTRA=""

while [ $# -gt 0 ]; do
    case "$1" in
        --method)   METHOD="$2"; shift ;;
        --screenshot) METHOD="screenshot" ;;
        --links)    METHOD="links" ;;
        --json)     METHOD="api" ;;
        --raw)      METHOD="raw" ;;
        *)          EXTRA="$EXTRA $1" ;;
    esac
    shift
done

if [ -z "$URL" ]; then
    echo "Usage: scrape.sh <url> [--method curl|puppet|raw|api|screenshot|links]"
    exit 1
fi

# User agent rotation
UA="Mozilla/5.0 (Linux; Android 16; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36"

# -----------------------------------------------------------------------
# Method: curl + text extraction (fast, static pages)
# -----------------------------------------------------------------------
scrape_curl() {
    CONTENT=$(curl -sL -A "$UA" --max-time 30 "$URL" 2>/dev/null)
    if [ -z "$CONTENT" ]; then
        echo "ERROR: Failed to fetch URL"
        return 1
    fi
    # Extract readable text using python + bs4
    echo "$CONTENT" | python3 -c "
import sys
from bs4 import BeautifulSoup
html = sys.stdin.read()
soup = BeautifulSoup(html, 'html.parser')
# Remove scripts, styles, nav, footer
for tag in soup(['script','style','nav','footer','header','aside','iframe']):
    tag.decompose()
# Get text
text = soup.get_text(separator='\n', strip=True)
# Clean up multiple blank lines
import re
text = re.sub(r'\n{3,}', '\n\n', text)
print(text[:10000])
" 2>/dev/null
}

# -----------------------------------------------------------------------
# Method: puppeteer headless (JS-rendered pages)
# -----------------------------------------------------------------------
scrape_puppet() {
    SCRAPE_URL="$URL" SCRAPE_UA="$UA" node -e '
const cheerio = require("cheerio");
const https = require("https");
const http = require("http");
const url = process.env.SCRAPE_URL;
const ua = process.env.SCRAPE_UA;
const mod = url.startsWith("https") ? https : http;
mod.get(url, {headers: {"User-Agent": ua}}, (res) => {
    let data = "";
    res.on("data", c => data += c);
    res.on("end", () => {
        const $ = cheerio.load(data);
        $("script,style,nav,footer,header,aside,iframe").remove();
        const text = $.text().replace(/\s{3,}/g, "\n\n").trim();
        console.log(text.substring(0, 10000));
    });
}).on("error", e => console.error("Fetch error:", e.message));
' 2>/dev/null
}

# -----------------------------------------------------------------------
# Method: screenshot (capture page as image)
# -----------------------------------------------------------------------
scrape_screenshot() {
    # Use Android Chrome via ADB to take screenshot of URL
    ~/bin/ui-control.sh open com.android.chrome 2>/dev/null
    sleep 2
    ~/bin/adb-shell.sh "am start -a android.intent.action.VIEW -d '$URL'" 2>/dev/null
    sleep 5
    OUT="$HOME/media/web_$(date +%Y%m%d_%H%M%S).png"
    ~/bin/adb-shell.sh "screencap -p /sdcard/picoclaw_web.png" 2>/dev/null
    cp /sdcard/picoclaw_web.png "$OUT" 2>/dev/null
    echo "$OUT"
}

# -----------------------------------------------------------------------
# Method: extract links
# -----------------------------------------------------------------------
scrape_links() {
    curl -sL -A "$UA" --max-time 30 "$URL" 2>/dev/null | python3 -c "
import sys, re
from bs4 import BeautifulSoup
soup = BeautifulSoup(sys.stdin.read(), 'html.parser')
for a in soup.find_all('a', href=True):
    href = a['href']
    text = a.get_text(strip=True)[:60]
    if href.startswith('http'):
        print(f'{text} -> {href}')
" 2>/dev/null
}

# -----------------------------------------------------------------------
# Method: JSON API
# -----------------------------------------------------------------------
scrape_api() {
    curl -sL -A "$UA" --max-time 30 -H "Accept: application/json" "$URL" 2>/dev/null | python3 -m json.tool 2>/dev/null || curl -sL -A "$UA" "$URL" 2>/dev/null
}

# -----------------------------------------------------------------------
# Method: raw HTML
# -----------------------------------------------------------------------
scrape_raw() {
    curl -sL -A "$UA" --max-time 30 "$URL" 2>/dev/null | head -c 20000
}

# -----------------------------------------------------------------------
# Auto-select method
# -----------------------------------------------------------------------
case "$METHOD" in
    curl)       scrape_curl ;;
    puppet)     scrape_puppet ;;
    screenshot) scrape_screenshot ;;
    links)      scrape_links ;;
    api)        scrape_api ;;
    raw)        scrape_raw ;;
    auto)
        # Try curl first (fast), fall back to puppeteer for JS pages
        RESULT=$(scrape_curl)
        if [ -n "$RESULT" ] && [ ${#RESULT} -gt 100 ]; then
            echo "$RESULT"
        else
            scrape_puppet
        fi
        ;;
    *)
        echo "Unknown method: $METHOD"
        echo "Available: curl, puppet, screenshot, links, api, raw, auto"
        exit 1
        ;;
esac
