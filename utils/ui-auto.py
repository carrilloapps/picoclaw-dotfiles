#!/usr/bin/env python3
"""
ui-auto.py — Advanced Android UI automation for PicoClaw.

More powerful than ui-control.sh: finds elements by text, id, class,
content-desc. Can wait for elements, scroll to find them, and handle
complex multi-step flows like app setup wizards.

Usage:
    ~/bin/ui-auto.py screenshot                     # Take screenshot
    ~/bin/ui-auto.py dump                            # Show all clickable elements
    ~/bin/ui-auto.py find "Accept"                   # Find by text (partial match)
    ~/bin/ui-auto.py findid "com.whatsapp:id/agree"  # Find by resource-id
    ~/bin/ui-auto.py tap "Accept"                    # Find by text and tap
    ~/bin/ui-auto.py tapid "agree_button"            # Find by resource-id and tap
    ~/bin/ui-auto.py tapdesc "Accept terms"          # Find by content-desc and tap
    ~/bin/ui-auto.py tapxy 540 1200                  # Tap coordinates
    ~/bin/ui-auto.py type "Hello world"              # Type text
    ~/bin/ui-auto.py clear                           # Clear text field
    ~/bin/ui-auto.py key ENTER                       # Press key
    ~/bin/ui-auto.py scroll down                     # Scroll direction
    ~/bin/ui-auto.py wait "Accept" 15                # Wait up to 15s for element
    ~/bin/ui-auto.py waittap "Accept" 15             # Wait then tap
    ~/bin/ui-auto.py buttons                         # List all buttons on screen
    ~/bin/ui-auto.py inputs                          # List all input fields
    ~/bin/ui-auto.py all                             # List ALL elements with bounds
"""
import subprocess
import sys
import os
import re
import time
import xml.etree.ElementTree as ET

ADB_CMD = os.path.expanduser("~/bin/adb-shell.sh")
ENSURE_UNLOCK = os.path.expanduser("~/bin/ensure-unlocked.sh")
MEDIA_DIR = os.path.expanduser("~/media")
UI_XML = "/sdcard/picoclaw_ui.xml"

_unlocked = False


def ensure_unlocked():
    """Make sure device is awake and unlocked before any UI operation."""
    global _unlocked
    if _unlocked:
        return True
    result = subprocess.run([ENSURE_UNLOCK], capture_output=True, text=True, timeout=20)
    out = result.stdout.strip()
    if "READY" in out or "UNLOCKED" in out:
        _unlocked = True
        return True
    else:
        print(f"DEVICE LOCKED: {out}")
        print("Provide PIN: python3 ~/bin/ui-auto.py unlock <PIN>")
        return False


def adb(cmd):
    """Run ADB shell command."""
    result = subprocess.run(
        [ADB_CMD, cmd], capture_output=True, text=True, timeout=15
    )
    return result.stdout.strip()


def dump_ui():
    """Dump UI hierarchy and parse XML."""
    adb(f"uiautomator dump {UI_XML}")
    xml_text = adb(f"cat {UI_XML}")
    if not xml_text or "<hierarchy" not in xml_text:
        return None
    try:
        return ET.fromstring(xml_text)
    except ET.ParseError:
        return None


def parse_bounds(bounds_str):
    """Parse bounds='[X1,Y1][X2,Y2]' into center (cx, cy)."""
    m = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", bounds_str)
    if not m:
        return None, None
    x1, y1, x2, y2 = int(m.group(1)), int(m.group(2)), int(m.group(3)), int(m.group(4))
    return (x1 + x2) // 2, (y1 + y2) // 2


def find_elements(root, text=None, resource_id=None, content_desc=None,
                  class_name=None, clickable=None):
    """Find UI elements by various attributes."""
    results = []
    for node in root.iter("node"):
        attrs = node.attrib
        if text and text.lower() not in attrs.get("text", "").lower():
            continue
        if resource_id and resource_id.lower() not in attrs.get("resource-id", "").lower():
            continue
        if content_desc and content_desc.lower() not in attrs.get("content-desc", "").lower():
            continue
        if class_name and class_name not in attrs.get("class", ""):
            continue
        if clickable is not None and attrs.get("clickable") != str(clickable).lower():
            continue
        cx, cy = parse_bounds(attrs.get("bounds", ""))
        results.append({
            "text": attrs.get("text", ""),
            "id": attrs.get("resource-id", ""),
            "desc": attrs.get("content-desc", ""),
            "class": attrs.get("class", ""),
            "clickable": attrs.get("clickable", "false"),
            "enabled": attrs.get("enabled", "false"),
            "bounds": attrs.get("bounds", ""),
            "cx": cx,
            "cy": cy,
        })
    return results


def tap_element(elem):
    """Tap the center of an element."""
    if elem["cx"] and elem["cy"]:
        adb(f"input tap {elem['cx']} {elem['cy']}")
        label = elem["text"] or elem["desc"] or elem["id"] or "element"
        print(f"Tapped '{label}' at ({elem['cx']}, {elem['cy']})")
        return True
    return False


def wait_for(text=None, resource_id=None, content_desc=None, timeout=15):
    """Wait for an element to appear on screen."""
    start = time.time()
    while time.time() - start < timeout:
        root = dump_ui()
        if root is not None:
            elems = find_elements(root, text=text, resource_id=resource_id,
                                  content_desc=content_desc)
            if elems:
                return elems[0]
        time.sleep(1)
    return None


def screenshot():
    """Take screenshot and return path."""
    os.makedirs(MEDIA_DIR, exist_ok=True)
    ts = time.strftime("%Y%m%d_%H%M%S")
    out = os.path.join(MEDIA_DIR, f"screenshot_{ts}.png")
    adb("screencap -p /sdcard/picoclaw_ss.png")
    subprocess.run(["cp", "/sdcard/picoclaw_ss.png", out],
                   capture_output=True, timeout=5)
    print(out)
    return out


def print_element(e, idx=None):
    """Pretty-print a UI element."""
    prefix = f"[{idx}] " if idx is not None else ""
    parts = []
    if e["text"]:
        parts.append(f'text="{e["text"]}"')
    if e["id"]:
        parts.append(f'id="{e["id"]}"')
    if e["desc"]:
        parts.append(f'desc="{e["desc"]}"')
    parts.append(f'class={e["class"].split(".")[-1]}')
    if e["clickable"] == "true":
        parts.append("CLICKABLE")
    parts.append(f'({e["cx"]},{e["cy"]})')
    print(f"{prefix}{' | '.join(parts)}")


def main():
    if len(sys.argv) < 2:
        print("Usage: ui-auto.py <command> [args]")
        print("Commands: screenshot, dump, find, findid, tap, tapid, tapdesc,")
        print("  tapxy, type, clear, key, scroll, wait, waittap, buttons, inputs, all")
        return

    cmd = sys.argv[1]
    args = sys.argv[2:]

    # Commands that don't need the screen unlocked
    no_unlock = {"unlock", "status", "locked"}

    # Auto-unlock before any UI operation
    if cmd not in no_unlock:
        if not ensure_unlocked():
            return

    if cmd == "unlock":
        pin = args[0] if args else None
        if pin:
            result = subprocess.run([ENSURE_UNLOCK, pin],
                                    capture_output=True, text=True, timeout=20)
            print(result.stdout.strip())
        else:
            print("Usage: ui-auto.py unlock <PIN>")

    elif cmd == "status":
        result = subprocess.run(
            [os.path.expanduser("~/bin/ui-control.sh"), "status"],
            capture_output=True, text=True, timeout=10)
        print(result.stdout.strip())

    elif cmd == "locked":
        result = subprocess.run(
            [os.path.expanduser("~/bin/ui-control.sh"), "locked"],
            capture_output=True, text=True, timeout=10)
        print(result.stdout.strip())

    elif cmd == "screenshot":
        screenshot()

    elif cmd == "dump":
        root = dump_ui()
        if root is None:
            print("ERROR: Could not dump UI")
            return
        elems = find_elements(root, clickable=True)
        print(f"Found {len(elems)} clickable elements:\n")
        for i, e in enumerate(elems):
            print_element(e, i)

    elif cmd == "all":
        root = dump_ui()
        if root is None:
            print("ERROR: Could not dump UI")
            return
        elems = find_elements(root)
        print(f"Found {len(elems)} total elements:\n")
        for i, e in enumerate(elems):
            if e["text"] or e["id"] or e["desc"]:
                print_element(e, i)

    elif cmd == "buttons":
        root = dump_ui()
        if root is None:
            print("ERROR: Could not dump UI"); return
        elems = find_elements(root, class_name="Button")
        elems += find_elements(root, clickable=True)
        seen = set()
        print("Buttons and clickable elements:\n")
        for i, e in enumerate(elems):
            key = (e["cx"], e["cy"])
            if key not in seen:
                seen.add(key)
                print_element(e, i)

    elif cmd == "inputs":
        root = dump_ui()
        if root is None:
            print("ERROR: Could not dump UI"); return
        elems = find_elements(root, class_name="EditText")
        print(f"Input fields ({len(elems)}):\n")
        for i, e in enumerate(elems):
            print_element(e, i)

    elif cmd == "find" and args:
        root = dump_ui()
        if root is None:
            print("ERROR: Could not dump UI"); return
        elems = find_elements(root, text=args[0])
        if not elems:
            elems = find_elements(root, content_desc=args[0])
        if not elems:
            elems = find_elements(root, resource_id=args[0])
        if elems:
            for i, e in enumerate(elems):
                print_element(e, i)
        else:
            print(f"Not found: '{args[0]}'")

    elif cmd == "findid" and args:
        root = dump_ui()
        if root is None:
            print("ERROR: Could not dump UI"); return
        elems = find_elements(root, resource_id=args[0])
        for i, e in enumerate(elems):
            print_element(e, i)

    elif cmd in ("tap", "taptext") and args:
        root = dump_ui()
        if root is None:
            print("ERROR: Could not dump UI"); return
        # Search text, then desc, then id
        elems = find_elements(root, text=args[0])
        if not elems:
            elems = find_elements(root, content_desc=args[0])
        if not elems:
            elems = find_elements(root, resource_id=args[0])
        if elems:
            tap_element(elems[0])
        else:
            print(f"Not found: '{args[0]}'")
            # Show what IS on screen
            clickable = find_elements(root, clickable=True)
            if clickable:
                print(f"\nClickable elements on screen ({len(clickable)}):")
                for i, e in enumerate(clickable[:10]):
                    print_element(e, i)

    elif cmd == "tapid" and args:
        root = dump_ui()
        if root is None:
            print("ERROR: Could not dump UI"); return
        elems = find_elements(root, resource_id=args[0])
        if elems:
            tap_element(elems[0])
        else:
            print(f"Resource-id not found: '{args[0]}'")

    elif cmd == "tapdesc" and args:
        root = dump_ui()
        if root is None:
            print("ERROR: Could not dump UI"); return
        elems = find_elements(root, content_desc=args[0])
        if elems:
            tap_element(elems[0])
        else:
            print(f"Content-desc not found: '{args[0]}'")

    elif cmd == "tapxy" and len(args) >= 2:
        adb(f"input tap {args[0]} {args[1]}")
        print(f"Tapped ({args[0]}, {args[1]})")

    elif cmd == "type" and args:
        text = args[0].replace(" ", "%s")
        adb(f"input text '{text}'")
        print(f"Typed: {args[0]}")

    elif cmd == "clear":
        adb("input keyevent KEYCODE_MOVE_HOME")
        adb("input keyevent --longpress KEYCODE_SHIFT_LEFT KEYCODE_MOVE_END")
        adb("input keyevent KEYCODE_DEL")
        print("Cleared text field")

    elif cmd == "key" and args:
        key = args[0] if args[0].startswith("KEYCODE_") else f"KEYCODE_{args[0]}"
        adb(f"input keyevent {key}")
        print(f"Pressed {key}")

    elif cmd == "scroll" and args:
        d = args[0]
        swipes = {
            "down": "input swipe 540 1600 540 800 300",
            "up": "input swipe 540 800 540 1600 300",
            "left": "input swipe 800 1200 200 1200 300",
            "right": "input swipe 200 1200 800 1200 300",
        }
        adb(swipes.get(d, swipes["down"]))
        print(f"Scrolled {d}")

    elif cmd == "wait" and args:
        text = args[0]
        timeout = int(args[1]) if len(args) > 1 else 15
        print(f"Waiting for '{text}' (max {timeout}s)...")
        elem = wait_for(text=text, timeout=timeout)
        if elem:
            print(f"Found: ", end="")
            print_element(elem)
        else:
            print(f"Timeout: '{text}' not found after {timeout}s")

    elif cmd == "waittap" and args:
        text = args[0]
        timeout = int(args[1]) if len(args) > 1 else 15
        print(f"Waiting for '{text}' (max {timeout}s)...")
        elem = wait_for(text=text, timeout=timeout)
        if elem:
            tap_element(elem)
        else:
            print(f"Timeout: '{text}' not found after {timeout}s")
            # Show what's on screen
            root = dump_ui()
            if root:
                clickable = find_elements(root, clickable=True)
                if clickable:
                    print(f"\nElements on screen ({len(clickable)}):")
                    for i, e in enumerate(clickable[:10]):
                        print_element(e, i)

    else:
        print(f"Unknown command: {cmd}")
        print("Run without args for usage.")


if __name__ == "__main__":
    main()
