#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# ssl-certs.sh — System-wide SSL certificate fix for Termux
# =============================================================================
# Placed in /data/data/com.termux/files/usr/etc/profile.d/ to export
# SSL_CERT_FILE for all login shells. This is a secondary safety net
# alongside the picoclaw-wrapper.sh.
#
# Installation on the device:
#   cp utils/ssl-certs.sh /data/data/com.termux/files/usr/etc/profile.d/ssl-certs.sh
#   chmod 644 /data/data/com.termux/files/usr/etc/profile.d/ssl-certs.sh
# =============================================================================

export SSL_CERT_FILE=/data/data/com.termux/files/usr/etc/tls/cert.pem
