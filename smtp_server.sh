#!/usr/bin/env bash
# =========================================
# Automated Postfix Mail Server Setup
# Supports any SMTP (Gmail, Mailtrap, etc.)
# Shows spinner + percentage during installation and service start
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

# --- Spinner + Percentage function ---
spinner_with_percentage() {
    local duration=$1
    local message=$2
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    local percent=0

    while [ $percent -le 100 ]; do
        local temp=${spin:i++%${#spin}:1}
        printf "\r%s  %s %3d%%" "$temp" "$message" "$percent"
        sleep $(echo "$duration / 50" | bc -l)
        ((percent+=2))
    done
    echo -e "\r✅  $message 100%"
}

# --- Install Postfix if not present ---
echo "[*] Installing Postfix if not present..."
if ! dpkg -s postfix &>/dev/null && ! rpm -q postfix &>/dev/null; then
    if [ -f /etc/debian_version ]; then
        spinner_with_percentage 5 "Installing postfix & mailutils..." &
        apt update &>/dev/null
        DEBIAN_FRONTEND=noninteractive apt install -y postfix mailutils &>/dev/null
        wait
    else
        spinner_with_percentage 5 "Installing postfix & mailx..." &
        yum install -y postfix mailx &>/dev/null
        wait
    fi
fi

# --- Add local user ---
echo "[*] Adding local user '$LOCAL_USER'..."
id "$LOCAL_USER" &>/dev/null || useradd -m "$LOCAL_USER"

# --- Configure Postfix ---
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

# --- Enable and restart Postfix with spinner ---
systemctl enable postfix
spinner_with_percentage 5 "Restarting Postfix service..." &
systemctl restart postfix &>/dev/null
wait

echo "[*] Postfix configured successfully for $LOCAL_USER@$DOMAIN using $RELAY_HOST"

# --- Send test email ---
echo "This is a test email from Postfix using $RELAY_USER" | mail -s "Test Email" "$RELAY_USER"
echo "[*] Test email sent to $RELAY_USER. Check inbox (or spam folder)."
