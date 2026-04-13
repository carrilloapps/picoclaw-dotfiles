---
name: Bug Report
about: Report a bug or unexpected behavior
title: "[Bug] "
labels: bug
assignees: carrilloapps
---

## Description

A clear and concise description of the bug.

## Environment

Run `make info` or `python scripts/device_info.py` and paste the output:

<details>
<summary>Device info output</summary>

```
Paste make info output here
```

</details>

Or fill manually:

- **Device**: (e.g., Xiaomi Redmi Note 10 Pro)
- **Android version**: (e.g., 16 / API 36)
- **Termux version**: (e.g., 0.118.1)
- **PicoClaw version**: (e.g., v0.2.6)
- **ROM**: (e.g., PixelOS, Stock)
- **Installation method**: (install.sh / full_deploy.py / manual)

## Steps to Reproduce

1. ...
2. ...
3. ...

## Expected Behavior

What you expected to happen.

## Actual Behavior

What actually happened. Include error messages or logs if available.

## Diagnostic Output

<details>
<summary>Gateway log</summary>

```
# Run: cat ~/.picoclaw/gateway.log | tail -50
```

</details>

<details>
<summary>Watchdog log</summary>

```
# Run: cat ~/watchdog.log | tail -20
```

</details>

<details>
<summary>PicoClaw status</summary>

```
# Run: ./picoclaw status
```

</details>

## Additional Context

Any other context, screenshots, or information.
