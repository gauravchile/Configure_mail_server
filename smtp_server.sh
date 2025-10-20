#!/usr/bin/env bash
# =========================================
# Automated Postfix Mail Server Setup
# Supports any SMTP (Gmail, Mailtrap, etc.)
# Spinner + percentage shown during install
# =========================================
# Usage:
# sudo ./mail_server.sh <domain> <local_user> <relay_host:port> <relay_user> <relay_pass>

set -euo pipefail

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

# Detect distro
if [ -f /etc/debian_version ]; then
    DISTRO="debian"
    PKG_INSTALL="apt-get install -y -qq"
    UPDATE_CMD="apt-get update -y -qq"
else
    DISTRO="rhel"
    PKG_INSTALL="yum install -y -q"
    UPDATE_CMD="yum makecache -q"
fi

spinner() {
    local pid=$1
    local task="$2"
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    local percent=0

    while kill -0 "$pid" 2>/dev/null; do
        i=$(( (i+1) % 10 ))
        percent=$((percent+1))
        [[ $percent -gt 99 ]] && percent=99
        printf "\r%s  %s... %d%%" "${spin:i:1}" "$task" "$percent"
        sleep 0.1
    done
    printf "\r✅  %s... 100%%\n" "$task"
}

update_system() {
    local task="Updating package index"
    $UPDATE_CMD &
    spinner $! "$task"
}

install_pkg() {
    local pkg="$1"
    local task="Installing $pkg"
    $PKG_INSTALL "$pkg" &
    spinner $! "$task"
}

echo "[*] Installing postfix if not present..."
if ! dpkg -s postfix &>/dev/null && ! rpm -q postfix &>/dev/null; then
    install_pkg "postfix"
    if [ "$DISTRO" = "debian" ]; then
        install_pkg "mailutils"
    else
        install_pkg "mailx"
    fi
fi

echo "[*] Adding local user '$LOCAL_USER'..."
id "$LOCAL_USER" &>/dev/null || useradd -m "$LOCAL_USER"

echo "[*] Configuring Postfix..."
HOSTNAME="${RELAY_HOST%%:*}"
PORT="${RELAY_HOST##*:}"
postconf -e "relayhost = [$HOSTNAME]:$PORT"

MAILPASS_FILE="/root/.mail_passwords.txt"
echo "[$HOSTNAME]:$PORT $RELAY_USER:$RELAY_PASS" > "$MAILPASS_FILE"
chmod 600 "$MAILPASS_FILE"
postmap "$MAILPASS_FILE"

postconf -e "smtp_sasl_auth_enable = yes"
postconf -e "smtp_sasl_password_maps = hash:$MAILPASS_FILE"
postconf -e "smtp_sasl_security_options = noanonymous"
postconf -e "smtp_use_tls = yes"
postconf -e "smtp_tls_CAfile = /etc/ssl/certs/ca-certificates.crt"

GENERIC_FILE="/etc/postfix/generic"
echo "$LOCAL_USER@$DOMAIN $RELAY_USER" > "$GENERIC_FILE"
postmap "$GENERIC_FILE"
postconf -e "smtp_generic_maps = hash:$GENERIC_FILE"

echo "[*] Enabling and starting Postfix..."
systemctl enable postfix
systemctl restart postfix
echo "✅  Postfix service started and enabled!"

echo "[*] Sending test email..."
echo "This is a test email from Postfix using $RELAY_USER" | mail -s "Test Email" "$RELAY_USER"
echo "✅  Test email sent to $RELAY_USER. Check inbox (or spam folder)."

echo "[*] Postfix configured successfully for $LOCAL_USER@$DOMAIN using $RELAY_HOST"
