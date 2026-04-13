# Contributing to PicoClaw Dotfiles

Thanks for your interest in contributing! This project is a personal dotfiles/configuration repository for deploying [PicoClaw](https://github.com/sipeed/picoclaw) on Android via Termux, maintained by [José Carrillo](https://carrillo.app) ([@carrilloapps](https://github.com/carrilloapps)).

## How to Contribute

1. **Fork** the repository and create a feature branch from `main`.
2. **Make your changes** -- keep commits focused and descriptive.
3. **Test** on an actual Android/Termux device if possible, or at minimum verify scripts parse correctly (`bash -n`, `python -m py_compile`).
4. **Open a pull request** against `main` with a clear description of what changed and why.

## Guidelines

- **No secrets**: Never commit API keys, tokens, passwords, or PINs. Use `<PLACEHOLDER>` values in templates. See [SECRETS.md](SECRETS.md).
- **Shell scripts**: Use `#!/data/data/com.termux/files/usr/bin/bash` for device-side scripts. Use `set -euo pipefail` where appropriate.
- **Python scripts**: Target Python 3.8+ (Termux compatible). Use `paramiko` for SSH.
- **Documentation**: Update cross-references if you rename or move files. Keep the [Complete Setup Guide](docs/10-complete-setup-guide.md) in sync.
- **Testing**: If you add a new script, verify it works both from a cloned repo and via the `curl | bash` installer path.
- **Security**: Scripts run with `chmod 700`, secrets with `chmod 600`. Gateway binds to `127.0.0.1` only. No `setprop`/`stop`/`start` commands (require root).

## Tech Stack

| Component | Technology |
|-----------|-----------|
| AI runtime | Go (PicoClaw binary) |
| Automation scripts | Python 3 (paramiko) |
| MCP servers | Node.js / TypeScript |
| Device scripts | Bash (Termux) |
| Cloud providers | Azure OpenAI, Ollama Cloud, Groq |
| CI | GitHub Actions |

## Reporting Issues

Use the [issue templates](https://github.com/carrilloapps/picoclaw-dotfiles/issues/new/choose) for bug reports and feature requests. For questions, use [Discussions](https://github.com/carrilloapps/picoclaw-dotfiles/discussions).

## Code of Conduct

See [CODE_OF_CONDUCT.md](.github/CODE_OF_CONDUCT.md). Be respectful and constructive.

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).

---

<p align="center">
  <a href="README.md">Back to README</a>
  &nbsp;&nbsp;|&nbsp;&nbsp;
  <a href="docs/10-complete-setup-guide.md">Setup Guide</a>
  &nbsp;&nbsp;|&nbsp;&nbsp;
  <a href="https://carrillo.app">carrillo.app</a>
</p>
