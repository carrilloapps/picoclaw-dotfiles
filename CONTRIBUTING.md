# Contributing to PicoClaw Dotfiles

Thanks for your interest in contributing! This project is a personal dotfiles/configuration repository for deploying [PicoClaw](https://github.com/sipeed/picoclaw) on Android via Termux, but contributions are welcome.

## How to Contribute

1. **Fork** the repository and create a feature branch from `main`.
2. **Make your changes** -- keep commits focused and descriptive.
3. **Test** on an actual Android/Termux device if possible, or at minimum verify scripts parse correctly.
4. **Open a pull request** against `main` with a clear description of what changed and why.

## Guidelines

- **No secrets**: Never commit API keys, tokens, passwords, or PINs. Use `<PLACEHOLDER>` values in templates.
- **Shell scripts**: Use `#!/data/data/com.termux/files/usr/bin/bash` for device-side scripts. Use `set -euo pipefail` where appropriate.
- **Python scripts**: Target Python 3.6+ (Termux default). Use `paramiko` for SSH.
- **Documentation**: Keep docs in US English. Update cross-references if you rename or move files.
- **Testing**: If you add a new script, verify it works both from a cloned repo and via the `curl | bash` installer path.

## Reporting Issues

Use the [issue templates](https://github.com/carrilloapps/picoclaw-dotfiles/issues/new/choose) for bug reports and feature requests.

## Code of Conduct

Be respectful and constructive. This is a small project maintained by one person.

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).
