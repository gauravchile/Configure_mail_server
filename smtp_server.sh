#!/usr/bin/env bash
# =========================================
# Automated Postfix Mail Server Setup
# Supports any SMTP (Gmail, Mailtrap, etc.)
# =========================================
# Usage:
# sudo ./mail_server.sh <domain> <local_user> <relay_host:port> <relay_user> <relay_pass>

set -e

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

if [ $# -lt 5 ]; then
  echo "Usage: sudo $0 <domain> <local_user> <relay_host:port> <relay_user> <relay_pass>"
  exit 1
fi

DOMAIN="$1"
LOCAL_USER="$2"
RELAY_HOST="$3"
RELAY_USER="$4"
RELAY_PASS="$5"

echo "[*] Installing postfix if not present..."
if ! dpkg -s postfix &>/dev/null && ! rpm -q postfix &>/dev/null; then
  if [ -f /etc/debian_version ]; then
    apt update && DEBIAN_FRONTEND=noninteractive apt install -y postfix mailutils
  else
    yum install -y postfix mailx
  fi
fi

echo "[*] Adding local user '$LOCAL_USER'..."
id "$LOCAL_USER" &>/dev/null || useradd -m "$LOCAL_USER"

echo "[*] Configuring Postfix..."
# Set relayhost properly: [host]:port
HOSTNAME="${RELAY_HOST%%:*}"
PORT="${RELAY_HOST##*:}"
postconf -e "relayhost = [$HOSTNAME]:$PORT"

# Setup SASL authentication
MAILPASS_FILE="/root/.mail_passwords.txt"
echo "[$HOSTNAME]:$PORT $RELAY_USER:$RELAY_PASS" > "$MAILPASS_FILE"
chmod 600 "$MAILPASS_FILE"
postmap "$MAILPASS_FILE"

postconf -e "smtp_sasl_auth_enable = yes"
postconf -e "smtp_sasl_password_maps = hash:$MAILPASS_FILE"
postconf -e "smtp_sasl_security_options = noanonymous"
postconf -e "smtp_use_tls = yes"
postconf -e "smtp_tls_CAfile = /etc/ssl/certs/ca-certificates.crt"

# Optional: Generic mapping so local user appears as relay user
GENERIC_FILE="/etc/postfix/generic"
echo "$LOCAL_USER@$DOMAIN $RELAY_USER" > "$GENERIC_FILE"
postmap "$GENERIC_FILE"
postconf -e "smtp_generic_maps = hash:$GENERIC_FILE"

# Ensure Postfix starts on boot and restart
systemctl enable postfix
systemctl restart postfix

echo "[*] Postfix configured successfully for $LOCAL_USER@$DOMAIN using $RELAY_HOST"

# Send test email
echo "This is a test email from Postfix using $RELAY_USER" | mail -s "Test Email" "$RELAY_USER"
echo "[*] Test email sent to $RELAY_USER. Check inbox (or spam folder)."

