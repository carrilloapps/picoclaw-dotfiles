# Config Templates

Sanitized configuration templates for PicoClaw. These contain `<PLACEHOLDER>` values — never real credentials.

## Files

| File | Deployed to (on device) | Purpose |
| ---- | ----------------------- | ------- |
| `config.template.json` | `~/.picoclaw/config.json` | Main PicoClaw config (providers, models, channels, tools, MCP) |
| `security.template.yml` | `~/.picoclaw/.security.yml` | API keys and bot tokens |

## Usage

### Via install.sh (automatic)

The one-click installer generates `config.json` and `security.yml` from your input — no need to copy these templates manually.

### Manual setup

```bash
# Copy templates to device
scp config.template.json <user>@<device-ip>:~/.picoclaw/config.json
scp security.template.yml <user>@<device-ip>:~/.picoclaw/.security.yml

# Replace all <PLACEHOLDER> values with real credentials
# See .env.example for the required values
```

### Via Makefile

```bash
make deploy-config    # Push templates to device
```

## Important

- **Never commit** real `config.json` or `.security.yml` — they contain API keys
- The `.gitignore` in this directory only allows `*.template.*` files
- See [SECRETS.md](../SECRETS.md) for credential management details

---

<p align="center">
  <a href="../README.md">📋 Back to README</a>
  &nbsp;&nbsp;|&nbsp;&nbsp;
  <a href="../docs/02-picoclaw-installation.md">📖 Installation Guide</a>
</p>
