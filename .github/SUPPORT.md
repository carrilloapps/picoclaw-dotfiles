# Support

## Getting Help

| Resource | When to use |
|----------|-------------|
| [Documentation](../docs/) | Step-by-step setup guides (00-10) |
| [Complete Setup Guide](../docs/10-complete-setup-guide.md) | End-to-end from zero to running |
| [Troubleshooting](../docs/10-complete-setup-guide.md#troubleshooting) | Common issues and fixes |
| [SECRETS.md](../SECRETS.md) | Credential management and rotation |
| [Bug Reports](https://github.com/carrilloapps/picoclaw-dotfiles/issues/new?template=bug_report.md) | Something is broken |
| [Feature Requests](https://github.com/carrilloapps/picoclaw-dotfiles/issues/new?template=feature_request.md) | Suggest improvements |
| [Discussions](https://github.com/carrilloapps/picoclaw-dotfiles/discussions) | Questions, ideas, show & tell |

## Quick Diagnostics

Run these from your workstation to diagnose issues:

```bash
make status          # PicoClaw status
make info            # Full device diagnostic
make health          # API connectivity check
make verify          # 8-phase resilience test
```

Or if the device IP changed:

```bash
python scripts/find_device.py --update    # Auto-discover and update .env
```

## Common Issues

| Symptom | Likely cause | Quick fix |
|---------|-------------|-----------|
| SSH connection refused | sshd not running | Open Termux, run `sshd` |
| SSH connection timeout | IP changed (DHCP) | `python scripts/find_device.py` |
| Gateway exits silently | Missing API keys in security.yml | See [v0.2.6 guide](../docs/02-picoclaw-installation.md) |
| ADB not connecting | TCP 5555 not enabled | Re-run `bash utils/grant-permissions.sh` |
| Notifications empty | Listener not enabled | Use `~/bin/notifications.sh` (ADB method) |

## Contact

- **Email**: [m@carrillo.app](mailto:m@carrillo.app)
- **Telegram**: [@carrilloapps](https://t.me/carrilloapps)
- **LinkedIn**: [carrilloapps](https://linkedin.com/in/carrilloapps)
- **Website**: [carrillo.app](https://carrillo.app)

## PicoClaw Upstream

For issues with the PicoClaw binary itself (not this dotfiles repo), see: [sipeed/picoclaw](https://github.com/sipeed/picoclaw)
