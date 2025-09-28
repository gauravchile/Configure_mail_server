# Mail Server Setup Automation

This project provides an automated bash script to configure Postfix for any SMTP server (Gmail, Mailtrap, custom) on Linux. It sets up the relay, authentication, TLS, and sends a test email.

## Usage
```bash
sudo ./mail_server.sh <domain> <local_user> <relay_host:port> <relay_user> <relay_pass>
```

Example:
```bash
sudo ./mail_server.sh gmail.com gaurav smtp.gmail.com:587 gauravchile05@gmail.com "app_password_here"
```

## Features
- Works with any SMTP server
- Configures SASL authentication automatically
- Sends a test email
- Debian and RHEL compatible
