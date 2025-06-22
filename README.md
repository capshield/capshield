
# CapShield

**CapShield** — Advanced DDoS and Firewall Protection for Linux Servers.

---

## Overview

CapShield is a lightweight, easy-to-install security solution designed to protect your Linux server from DDoS attacks and unauthorized access using iptables firewall rules, connection tracking, and IP whitelisting/blacklisting.

CapShield applies hardened network settings, dynamically manages firewall rules, and keeps your system protected against common network attacks.

---

## Features

* Automated iptables rules optimized for DDoS mitigation
* IP whitelist and blacklist management
* Connection limits to prevent SYN floods
* Kernel sysctl tuning for network robustness
* Systemd service for automatic startup and management
* Automatic dependency checks and fixes
* Simple CLI interface for administration
* Kernel version check with reboot notification

---

## Requirements

* Linux server (Ubuntu/Debian tested)
* Root or sudo privileges
* iptables, ipset, conntrack tools installed (the installer will handle this)

---

## Installation

Run the following command to download and install CapShield:

```bash
curl -fsSL https://raw.githubusercontent.com/capshield/capshield/main/install.sh | sudo bash
```

This script will:

* Check and install dependencies
* Apply kernel sysctl network hardening
* Set up iptables firewall rules
* Install systemd service for CapShield
* Provide command-line tool at `/usr/local/bin/capshield`

---

## Usage

Run the main CapShield script with:

```bash
sudo capshield enable
```

This applies the firewall rules and sysctl settings immediately.

Available commands:

| Command                    | Description                 |
| -------------------------- | --------------------------- |
| `capshield enable`         | Apply protection rules      |
| `capshield status`         | Show current firewall rules |
| `capshield ban <IP>`       | Add IP to blacklist         |
| `capshield whitelist <IP>` | Add IP to whitelist         |
| `capshield logs`           | View CapShield logs         |

---

## Kernel Updates and Reboot

CapShield requires a modern Linux kernel for best performance and compatibility. The installer checks if a newer kernel version is installed but not yet running.

If a kernel update is detected, you will see a prompt:

```
⚠️ Newer kernel available  
Currently running kernel: 6.8.0-60-generic  
Latest installed kernel: 6.8.0-62-generic  

You need to reboot for the new kernel to take effect.

Do you want to reboot now? [y/N]:
```

* **It is strongly recommended to reboot** to load the new kernel and ensure full compatibility.
* If you skip rebooting, some features or protection might not work optimally.

---

### Manually Update the Kernel

To manually update your kernel on Ubuntu/Debian, run:

```bash
sudo apt update && sudo apt full-upgrade -y
sudo reboot
```

Make sure to reboot promptly after kernel upgrades.

---

## Troubleshooting

### 1. Permission Denied Errors

If you see errors like:

```
/usr/local/bin/capshield: line XX: /opt/capshield/config/blacklist.txt: Permission denied
tee: /var/log/capshield/activity.log: Permission denied
```

This means your user does not have write permission to these files. Solutions:

* Run commands with `sudo`, e.g.:

  ```bash
  sudo capshield ban <IP>
  ```

* Or adjust ownership/permissions:

  ```bash
  sudo chown -R $(whoami):$(whoami) /opt/capshield/config
  sudo chown $(whoami):$(whoami) /var/log/capshield/activity.log
  ```

---

### 2. iptables “Permission denied” or “Could not fetch rule set”

This usually means you are running `capshield status` without root privileges.

Use:

```bash
sudo capshield status
```

---

### 3. Broken dependencies when installing packages

If you get errors about unmet dependencies during installation, try:

```bash
sudo apt --fix-broken install -y
sudo apt update && sudo apt full-upgrade -y
```

Then rerun the install script.

---

## Logs and Debugging

CapShield logs its activities to:

```
/var/log/capshield/activity.log
```

Check this file for detailed logs of firewall rule application, kernel tuning, and IP bans.

---

## Uninstallation

To remove CapShield, run:

```bash
sudo systemctl stop capshield.service
sudo systemctl disable capshield.service
sudo rm /etc/systemd/system/capshield.service
sudo rm /usr/local/bin/capshield
sudo rm -rf /opt/capshield
sudo systemctl daemon-reload
```

---

## Contributing

Contributions and feature requests are welcome! Feel free to open issues or pull requests on GitHub.

---

## License

CapShield is open-source under the MIT License. See LICENSE file for details.

---

## Contact

For questions, issues, or support, please open an issue on GitHub or contact the maintainer.

---

**Stay safe. Stay protected. CapShield your server today!**
