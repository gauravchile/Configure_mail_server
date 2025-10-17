# 📧 Mail Server Setup Automation

Automated bash script to configure **Postfix** for any SMTP server (Gmail, Mailtrap, custom) on Linux.  
Sets up the relay, authentication, TLS, and sends a test email.

---

## ⚙️ Usage

```bash
sudo ./mail_server.sh <domain> <local_user> <relay_host:port> <relay_user> <relay_pass>
```

### Example

```bash
sudo ./mail_server.sh example.com <username> smtp.gmail.com:587 <username>@example.com "app_password_here"
```

---

## 🌟 Features

- Works with **any SMTP server**  
- Configures **SASL authentication** automatically  
- Sends a **test email**  
- Compatible with **Debian and RHEL**  

---

## 📁 Folder Structure

```
Mail_Server_Setup_Automation/
│
├─ README.md            # Project documentation
└─ mail_server.sh       # Main installation & configuration script
```

---

## 🎯 Skills Demonstrated

- Linux server administration  
- Mail server setup & configuration  
- Postfix relay & authentication  
- Bash scripting for automation  
- Testing SMTP connectivity
