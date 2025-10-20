#!/usr/bin/env bash
# postfix_setup.sh
# Automated Postfix Mail Server Setup (relay + SASL)
# Spinner + percentage for install & restart
# Usage: sudo ./postfix_setup.sh <domain> <local_user> <relay_host:port> <relay_user> <relay_pass>

set -euo pipefail

GREEN="\e[32m"
YELLOW="\e[33m"
RED="\e[31m"
RESET="\e[0m"

timestamp() { date +"%Y%m%d-%H%M%S"; }
logfile="/tmp/postfix_setup.$(timestamp).log"

spinner_watch() {
  local pid=$1
  local msg="$2"
  local spin_chars=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
  local i=0
  local pct=0
  printf "%b" "$YELLOW"
  while kill -0 "$pid" 2>/dev/null; do
    i=$(((i+1) % 10))
    pct=$((pct + 1))
    [ $pct -gt 98 ] && pct=98
    printf "\r%s  %s... %3d%%" "${spin_chars[$i]}" "$msg" "$pct"
    sleep 0.1
  done
  printf "\r%b✅  %s... 100%%%b\n" "$GREEN" "$msg" "$RESET"
}

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Please run as root${RESET}"
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

# distro detect
if [ -f /etc/debian_version ]; then
  DISTRO="debian"
  UPDATE_CMD=(apt-get update -y -qq)
  INSTALL_CMD=(apt-get install -y -qq)
  MAIL_PKG="mailutils"
elif [ -f /etc/redhat-release ]; then
  DISTRO="rhel"
  if command -v dnf &>/dev/null; then
    UPDATE_CMD=(dnf makecache -y -q)
    INSTALL_CMD=(dnf install -y -q)
  else
    UPDATE_CMD=(yum makecache -y -q)
    INSTALL_CMD=(yum install -y -q)
  fi
  MAIL_PKG="mailx"
else
  echo -e "${RED}Unsupported OS${RESET}"
  exit 1
fi

# install postfix if missing
echo "[*] Installing postfix if not present (logs: $logfile)"
if ! dpkg -s postfix &>/dev/null && ! rpm -q postfix &>/dev/null; then
  # update
  ("${UPDATE_CMD[@]}") >>"$logfile" 2>&1 &
  pid=$!
  spinner_watch $pid "Updating package index"
  wait $pid || { echo -e "${RED}Update failed. See $logfile${RESET}"; exit 1; }

  # postfix
  ("${INSTALL_CMD[@]}" postfix) >>"$logfile" 2>&1 &
  pid=$!
  spinner_watch $pid "Installing postfix"
  wait $pid || { echo -e "${RED}Postfix install failed. See $logfile${RESET}"; exit 1; }

  # mail utils
  ("${INSTALL_CMD[@]}" "$MAIL_PKG") >>"$logfile" 2>&1 &
  pid=$!
  spinner_watch $pid "Installing mail utilities"
  wait $pid || { echo -e "${RED}Mail utils install failed. See $logfile${RESET}"; exit 1; }
else
  echo "[*] Postfix already installed"
fi

# create local user if missing
id "$LOCAL_USER" &>/dev/null || useradd -m "$LOCAL_USER"

echo "[*] Configuring Postfix (relay -> $RELAY_HOST)"
HOSTNAME="${RELAY_HOST%%:*}"
PORT="${RELAY_HOST##*:}"

# set relayhost
postconf -e "relayhost = [$HOSTNAME]:$PORT"

# create SASL password map
MAILPASS_FILE="/etc/postfix/sasl_password"
echo "[$HOSTNAME]:$PORT $RELAY_USER:$RELAY_PASS" > "$MAILPASS_FILE"
chmod 600 "$MAILPASS_FILE"
postmap "$MAILPASS_FILE" >>"$logfile" 2>&1 || true

postconf -e "smtp_sasl_auth_enable = yes"
postconf -e "smtp_sasl_password_maps = hash:$MAILPASS_FILE"
postconf -e "smtp_sasl_security_options = noanonymous"
postconf -e "smtp_use_tls = yes"
postconf -e "smtp_tls_CAfile = /etc/ssl/certs/ca-certificates.crt"

# generic mapping (optional)
GENERIC_FILE="/etc/postfix/generic"
echo "$LOCAL_USER@$DOMAIN $RELAY_USER" > "$GENERIC_FILE"
postmap "$GENERIC_FILE" >>"$logfile" 2>&1 || true
postconf -e "smtp_generic_maps = hash:$GENERIC_FILE"

# enable & restart postfix with spinner
systemctl enable postfix >>"$logfile" 2>&1 || true
systemctl restart postfix >>"$logfile" 2>&1 &
pid=$!
spinner_watch $pid "Restarting Postfix service"
wait $pid || { echo -e "${RED}Postfix restart failed. See $logfile${RESET}"; exit 1; }

# verify service active
if systemctl is-active --quiet postfix; then
  echo -e "${GREEN}[+] Postfix service is active and enabled${RESET}"
else
  echo -e "${RED}[!] Postfix is not active. See $logfile${RESET}"
  exit 1
fi

# send test mail
echo "This is a test email from Postfix using $RELAY_USER" | mail -s "Test Email" "$RELAY_USER" >>"$logfile" 2>&1 || true
echo -e "${GREEN}[+] Test email queued/sent to $RELAY_USER (check inbox/spam).${RESET}"

echo -e "\n${GREEN}Postfix configured successfully for ${LOCAL_USER}@${DOMAIN}${RESET}"
echo "Logs: $logfile"
