#!/usr/bin/env python3
"""Install scraping stack on the PicoClaw device."""
import os
import sys
import time

if sys.platform == 'win32' and hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')

sys.path.insert(0, os.path.dirname(__file__))
from connect import connect, run


def main():
    ssh = connect()

    # Step 1: Quick Python packages (pre-compiled wheels, no compilation)
    print("=== [1/4] Python scraping packages (quick) ===")
    out, _ = run(ssh, "pip install httpx parsel feedparser fake-useragent cloudscraper trafilatura playwright 2>&1 | tail -5", timeout=120)
    print(out)

    # Step 2: Compile-heavy packages (lxml etc.)
    print("\n=== [2/4] Compiling lxml + dependencies (background) ===")
    run(ssh, "nohup bash -c 'pip install lxml readability-lxml newspaper4k selectolax > /tmp/pip_compile.log 2>&1' &")
    print("Compiling in background. Check: cat /tmp/pip_compile.log")

    # Step 3: Node.js packages
    print("\n=== [3/4] Node.js scraping packages ===")
    out, _ = run(ssh, "npm list -g puppeteer-core cheerio 2>/dev/null | grep -v npm | tail -5", timeout=10)
    if "puppeteer" in out:
        print("Already installed:")
        print(out)
    else:
        out, _ = run(ssh, "npm install -g puppeteer-core cheerio 2>&1 | tail -3", timeout=60)
        print(out)

    # Step 4: Verify what's installed
    print("\n=== [4/4] Installed scraping tools ===")
    out, _ = run(ssh, "pip list 2>/dev/null | grep -iE 'httpx|parsel|beautifulsoup|cloudscraper|trafilatura|playwright|feedparser|fake.useragent|requests|aiohttp|lxml|newspaper|selectolax|readability'", timeout=10)
    print("Python:")
    print(out)

    out, _ = run(ssh, "npm list -g --depth=0 2>/dev/null | grep -iE 'puppeteer|cheerio|stealth'", timeout=10)
    print("\nNode.js:")
    print(out)

    # Step 5: Test playwright
    print("\n=== Testing playwright ===")
    out, _ = run(ssh, "python3 -c 'import playwright; print(f\"playwright {playwright.__version__}\")' 2>&1", timeout=10)
    print(out)

    ssh.close()
    print("\nDone. lxml may still be compiling — check /tmp/pip_compile.log on device.")


if __name__ == "__main__":
    main()
