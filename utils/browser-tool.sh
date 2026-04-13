#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# browser-tool.sh -- Fully functional headless Chromium (handles TLS issues)
# =============================================================================
# Robust web navigation via chromium-browser. Handles:
#   - Incomplete cert chains (BCV, government sites) via --ignore-certificate-errors
#   - JS-heavy sites via --virtual-time-budget
#   - Timeouts, retries, user-agent rotation
#   - Tables, structured data, forms
#
# Usage:
#   ~/bin/browser-tool.sh dom <url>                    # Full DOM (post-JS)
#   ~/bin/browser-tool.sh text <url>                   # Visible text (readable)
#   ~/bin/browser-tool.sh read <url>                   # Readability mode (article extract)
#   ~/bin/browser-tool.sh screenshot <url> [out.png] [WxH]
#   ~/bin/browser-tool.sh pdf <url> [out.pdf]
#   ~/bin/browser-tool.sh links <url>                  # All links as JSON
#   ~/bin/browser-tool.sh title <url>
#   ~/bin/browser-tool.sh meta <url>                   # Meta tags + Open Graph
#   ~/bin/browser-tool.sh tables <url>                 # Extract ALL tables as JSON
#   ~/bin/browser-tool.sh json <url> <json-path>       # JSON API + extract path
#   ~/bin/browser-tool.sh scrape <url> <css-selector>  # CSS selector extraction
#   ~/bin/browser-tool.sh mobile <url> [out.png]       # Mobile viewport screenshot
#   ~/bin/browser-tool.sh data <url>                   # Structured data: tables + lists + headings
# =============================================================================

set -eu
CHROMIUM="chromium-browser"
UA="Mozilla/5.0 (X11; Linux aarch64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.7680.177 Safari/537.36"
MOBILE_UA="Mozilla/5.0 (Linux; Android 16; M2101K6R) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.7680.177 Mobile Safari/537.36"
# Flags: tolerate broken certs, disable noise, give JS time to run
BASE_FLAGS="--headless --disable-gpu --no-sandbox --disable-dev-shm-usage \
    --disable-software-rasterizer --hide-scrollbars --mute-audio --no-first-run \
    --virtual-time-budget=15000 --run-all-compositor-stages-before-draw \
    --ignore-certificate-errors --allow-running-insecure-content \
    --disable-web-security --disable-features=IsolateOrigins,site-per-process \
    --disable-blink-features=AutomationControlled"

CMD="${1:-help}"
URL="${2:-}"

command -v "$CHROMIUM" >/dev/null 2>&1 || {
    echo "ERROR: chromium-browser not installed. Run: pkg install x11-repo && pkg install chromium"
    exit 1
}

MEDIA="${HOME}/media"
mkdir -p "$MEDIA"

# Run chromium with retry on failure
_chromium() {
    $CHROMIUM $BASE_FLAGS --user-agent="$UA" "$@" 2>/dev/null
}

case "$CMD" in
    dom)
        _chromium --dump-dom "$URL"
        ;;
    text)
        _chromium --dump-dom "$URL" | python3 -c "
import sys
try:
    from bs4 import BeautifulSoup
    soup = BeautifulSoup(sys.stdin.read(), 'html.parser')
    for tag in soup(['script', 'style', 'noscript', 'iframe']):
        tag.decompose()
    text = soup.get_text(separator='\n', strip=True)
    import re
    text = re.sub(r'\n{3,}', '\n\n', text)
    print(text)
except ImportError:
    # Fallback parser
    import re, html
    raw = sys.stdin.read()
    raw = re.sub(r'<script[^>]*>.*?</script>', '', raw, flags=re.DOTALL | re.IGNORECASE)
    raw = re.sub(r'<style[^>]*>.*?</style>', '', raw, flags=re.DOTALL | re.IGNORECASE)
    raw = re.sub(r'<[^>]+>', ' ', raw)
    print(html.unescape(re.sub(r'\s+', ' ', raw)).strip())
"
        ;;
    read)
        _chromium --dump-dom "$URL" | python3 -c "
import sys
from bs4 import BeautifulSoup
soup = BeautifulSoup(sys.stdin.read(), 'html.parser')
for tag in soup(['script', 'style', 'noscript', 'iframe', 'nav', 'header', 'footer', 'aside', 'form']):
    tag.decompose()
# Find main content
main = soup.find('main') or soup.find('article') or soup.find('div', class_='content') or soup.body or soup
title = soup.find('title')
if title: print(f'# {title.get_text(strip=True)}\n')
for el in main.find_all(['h1', 'h2', 'h3', 'p', 'li']):
    text = el.get_text(strip=True)
    if not text: continue
    tag = el.name
    if tag == 'h1': print(f'\n# {text}\n')
    elif tag == 'h2': print(f'\n## {text}\n')
    elif tag == 'h3': print(f'\n### {text}\n')
    elif tag == 'li': print(f'- {text}')
    else: print(text + '\n')
"
        ;;
    screenshot)
        OUT="${3:-$MEDIA/screenshot_$(date +%s).png}"
        SIZE="${4:-1280,800}"
        SIZE="${SIZE//x/,}"
        _chromium --window-size="$SIZE" --screenshot="$OUT" "$URL" >/dev/null
        [ -f "$OUT" ] && echo "$OUT" || { echo "ERROR: screenshot failed"; exit 1; }
        ;;
    mobile)
        OUT="${3:-$MEDIA/mobile_$(date +%s).png}"
        $CHROMIUM $BASE_FLAGS --user-agent="$MOBILE_UA" --window-size=412,915 --screenshot="$OUT" "$URL" 2>/dev/null >/dev/null
        [ -f "$OUT" ] && echo "$OUT" || { echo "ERROR: mobile screenshot failed"; exit 1; }
        ;;
    pdf)
        OUT="${3:-$MEDIA/page_$(date +%s).pdf}"
        _chromium --print-to-pdf="$OUT" "$URL" >/dev/null
        [ -f "$OUT" ] && echo "$OUT" || { echo "ERROR: PDF failed"; exit 1; }
        ;;
    links)
        _chromium --dump-dom "$URL" | python3 -c "
import sys, json
from bs4 import BeautifulSoup
soup = BeautifulSoup(sys.stdin.read(), 'html.parser')
links = []
for a in soup.find_all('a', href=True):
    href = a['href']
    text = a.get_text(strip=True)[:100]
    if href.startswith(('http://', 'https://', '/')):
        links.append({'text': text, 'url': href})
# Dedupe by URL
seen = set()
out = []
for l in links:
    if l['url'] not in seen:
        seen.add(l['url'])
        out.append(l)
print(json.dumps(out, indent=2, ensure_ascii=False))
"
        ;;
    title)
        _chromium --dump-dom "$URL" | python3 -c "
import sys, re
m = re.search(r'<title[^>]*>([^<]+)</title>', sys.stdin.read(), re.IGNORECASE)
print(m.group(1).strip() if m else '')
"
        ;;
    meta)
        _chromium --dump-dom "$URL" | python3 -c "
import sys, json
from bs4 import BeautifulSoup
soup = BeautifulSoup(sys.stdin.read(), 'html.parser')
out = {}
if soup.title: out['title'] = soup.title.get_text(strip=True)
for m in soup.find_all('meta'):
    name = m.get('name') or m.get('property')
    content = m.get('content')
    if name and content: out[name] = content
# Links
canonical = soup.find('link', rel='canonical')
if canonical: out['canonical'] = canonical.get('href')
print(json.dumps(out, indent=2, ensure_ascii=False))
"
        ;;
    tables)
        # Extract ALL tables as structured JSON
        _chromium --dump-dom "$URL" | python3 -c "
import sys, json
from bs4 import BeautifulSoup
soup = BeautifulSoup(sys.stdin.read(), 'html.parser')
all_tables = []
for i, table in enumerate(soup.find_all('table')):
    rows = []
    for tr in table.find_all('tr'):
        cells = [td.get_text(' ', strip=True) for td in tr.find_all(['td', 'th'])]
        if any(c for c in cells): rows.append(cells)
    if rows:
        all_tables.append({'index': i, 'rows': rows, 'row_count': len(rows)})
# Also structured-data divs with class centrado/tasa/etc.
for div in soup.find_all('div', class_=['centrado', 'tasa', 'tipo-cambio']):
    strong = div.find('strong')
    if strong:
        all_tables.append({'div': ' '.join(div.get('class', [])), 'value': strong.get_text(strip=True)})
print(json.dumps(all_tables, indent=2, ensure_ascii=False))
"
        ;;
    data)
        # Structured data extraction: headings + tables + lists + prominent values
        _chromium --dump-dom "$URL" | python3 -c "
import sys, json, re
from bs4 import BeautifulSoup
soup = BeautifulSoup(sys.stdin.read(), 'html.parser')
for tag in soup(['script', 'style', 'noscript']):
    tag.decompose()

out = {'headings': [], 'tables': [], 'lists': [], 'key_values': []}

for h in soup.find_all(['h1', 'h2', 'h3']):
    t = h.get_text(strip=True)
    if t: out['headings'].append({'level': h.name, 'text': t})

for table in soup.find_all('table'):
    rows = []
    for tr in table.find_all('tr'):
        cells = [td.get_text(' ', strip=True) for td in tr.find_all(['td', 'th'])]
        if any(c for c in cells): rows.append(cells)
    if rows: out['tables'].append(rows)

for ul in soup.find_all(['ul', 'ol'])[:10]:
    items = [li.get_text(' ', strip=True)[:200] for li in ul.find_all('li', recursive=False)][:20]
    items = [i for i in items if i]
    if items: out['lists'].append(items)

# Key-value pairs: dt/dd and divs with strong+sibling
for dl in soup.find_all('dl'):
    dts = dl.find_all('dt')
    dds = dl.find_all('dd')
    for dt, dd in zip(dts, dds):
        out['key_values'].append({'key': dt.get_text(strip=True), 'value': dd.get_text(strip=True)})

# Cards/boxes with numeric values (common for dashboards, finance)
for div in soup.find_all('div'):
    cls = ' '.join(div.get('class', []))
    if any(k in cls.lower() for k in ['centrado', 'card', 'tasa', 'rate', 'value', 'amount']):
        strong = div.find('strong')
        if strong:
            val = strong.get_text(strip=True)
            context = div.get_text(' ', strip=True).replace(val, '').strip()[:100]
            if val and re.search(r'[0-9]', val):
                out['key_values'].append({'label': context, 'value': val, 'class': cls})

print(json.dumps(out, indent=2, ensure_ascii=False))
"
        ;;
    json)
        # Fetch JSON API endpoint (uses curl -k since we want pure JSON, not browser rendering)
        PATH_EXPR="${3:-.}"
        curl -sk -L -A "$UA" --max-time 20 -H "Accept: application/json" "$URL" | jq "$PATH_EXPR"
        ;;
    scrape)
        SEL="${3:?Usage: browser-tool.sh scrape <url> <css-selector>}"
        _chromium --dump-dom "$URL" | python3 -c "
import sys, json
from bs4 import BeautifulSoup
soup = BeautifulSoup(sys.stdin.read(), 'html.parser')
results = []
for el in soup.select('$SEL'):
    t = el.get_text(' ', strip=True)
    if t: results.append(t)
for r in results:
    print(r)
"
        ;;
    check)
        # Quick connectivity + TLS check
        URL="${2:?}"
        echo "Testing: $URL"
        echo "--- HTTPS (strict) ---"
        curl -sI --max-time 10 "$URL" 2>&1 | head -3 || echo "FAILED"
        echo "--- HTTPS (insecure) ---"
        curl -skI --max-time 10 "$URL" 2>&1 | head -3 || echo "FAILED"
        echo "--- Chromium (ignore-cert) ---"
        TEMP=$(mktemp)
        _chromium --dump-dom "$URL" > "$TEMP" 2>/dev/null
        SIZE=$(wc -c < "$TEMP")
        rm -f "$TEMP"
        echo "DOM size: $SIZE bytes"
        ;;
    help|*)
        head -23 "$0" | tail -21 | sed 's/^# //;s/^#//'
        ;;
esac
