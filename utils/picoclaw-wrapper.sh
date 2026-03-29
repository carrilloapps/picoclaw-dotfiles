#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# picoclaw-wrapper.sh — TLS wrapper for PicoClaw binary on Termux
# =============================================================================
# Ensures SSL_CERT_FILE is set before executing the PicoClaw Go binary.
# Without this, all HTTPS requests fail with:
#   "x509: certificate signed by unknown authority"
#
# Termux stores CA certs at a non-standard path that Go doesn't check.
# This wrapper guarantees the variable is set regardless of how PicoClaw
# is invoked (direct exec, cron, scripts, SSH, tmux, etc.)
#
# Installation on the device:
#   mv ~/picoclaw ~/picoclaw.bin
#   cp utils/picoclaw-wrapper.sh ~/picoclaw
#   chmod +x ~/picoclaw
#
# Optionally for PATH-based access:
#   mkdir -p ~/bin
#   cp ~/picoclaw ~/bin/picoclaw
# =============================================================================

export SSL_CERT_FILE=/data/data/com.termux/files/usr/etc/tls/cert.pem
exec /data/data/com.termux/files/home/picoclaw.bin "$@"
