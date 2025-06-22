#!/bin/bash

# CAPSHIELD 2025
# COPYRIGHT

set -euo pipefail

LOG_FILE="/var/log/capshield/install.log"
mkdir -p /var/log/capshield
exec > >(tee -a "$LOG_FILE") 2>&1

echo -e "\e[1;36m"
cat << "EOF"
   _____            _____ _     _      _     _ 
  / ____|          / ____| |   (_)    | |   | |
 | |     __ _ _ __| (___ | |__  _  ___| | __| |
 | |    / _` | '_ \\___ \| '_ \| |/ _ \ |/ _` |
 | |___| (_| | |_) |___) | | | | |  __/ | (_| |
  \_____\__,_| .__/_____/|_| |_|_|\___|_|\__,_|
             | |                               
             |_|                               
EOF
echo -e "\e[0m"
echo -e "\n⚙️  Installing CapShield Basic..."
retry() {
    local -r -i max_attempts="$1"; shift
    local -i attempt_num=1

    until "$@"; do
        if (( attempt_num == max_attempts )); then
            echo "❌ Command failed after $attempt_num attempts."
            return 1
        else
            echo "⚠️ Command failed. Attempt $attempt_num/$max_attempts:"
            sleep $((attempt_num * 2))
            ((attempt_num++))
        fi
    done
}

fix_apt_dependencies() {
    echo "🔧 Fixing broken dependencies..."
    retry 3 apt --fix-broken install -y
}

update_package_cache() {
    echo "🔄 Updating package cache..."
    retry 3 apt update -y
}

install_package() {
    local pkg=$1
    echo "📦 Installing package: $pkg"
    retry 3 apt install -y "$pkg"
}

check_requirements() {
    echo "🔍 Checking dependencies..."

    # Packages needed
    REQUIRED_PKGS=(iptables ipset conntrack)

    # Check if apt available
    if ! command -v apt >/dev/null 2>&1; then
        echo "❌ apt package manager not found. Please install dependencies manually."
        exit 1
    fi

    update_package_cache
    fix_apt_dependencies

    for pkg in "${REQUIRED_PKGS[@]}"; do
        if ! dpkg -s "$pkg" >/dev/null 2>&1; then
            install_package "$pkg" || {
                echo "❌ Failed to install $pkg. Trying to fix dependencies and retry."
                fix_apt_dependencies
                install_package "$pkg" || {
                    echo "❌ Could not install $pkg after fixing dependencies. Exiting."
                    exit 1
                }
            }
        else
            echo "✅ $pkg is already installed."
        fi
    done

    fix_apt_dependencies
}

load_kernel_modules() {
    echo "📦 Ensuring kernel modules are loaded..."

    local modules=(ip_conntrack xt_recent ip_tables)
    for mod in "${modules[@]}"; do
        if ! lsmod | grep -q "^$mod"; then
            echo "Loading kernel module: $mod"
            if ! modprobe "$mod"; then
                echo "⚠️ Could not load module $mod (may not be critical)."
            else
                echo "✅ Module $mod loaded."
            fi
        else
            echo "✅ Module $mod already loaded."
        fi
    done
}

summary() {
    echo -e "\n📄 \e[1;34mINSTALL SUMMARY\e[0m"
    echo " - Logs saved at: $LOG_FILE"
    echo " - Check firewall: capshield status"
    echo " - Use 'capshield logs' to debug"
    echo " - Use 'systemctl status capshield' to see if the protection service is running"
    echo "✅ All done!"
}
check_requirements
load_kernel_modules

INSTALL_DIR="/opt/capshield"
BIN_PATH="/usr/local/bin/capshield"
SERVICE_PATH="/etc/systemd/system/capshield.service"
LOG_DIR="/var/log/capshield"

mkdir -p "$INSTALL_DIR/config" "$LOG_DIR"

cat << 'EOF' > "$INSTALL_DIR/capshield.sh"
#!/bin/bash
LOG_FILE="/var/log/capshield/activity.log"
WHITELIST="/opt/capshield/config/whitelist.txt"
BLACKLIST="/opt/capshield/config/blacklist.txt"

log() {
    echo "[$(date)] $1" | tee -a "$LOG_FILE"
}

apply_sysctl() {
    cat << EOT > /etc/sysctl.d/capshield.conf
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 4096
net.ipv4.tcp_rmem = 4096 87380 6291456
net.ipv4.tcp_wmem = 4096 16384 4194304
net.ipv4.tcp_fin_timeout = 15
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
EOT
    sysctl --system
    log "🔧 Kernel sysctl rules applied."
}

apply_iptables() {
    log "🛡️  Applying iptables firewall rules..."

    iptables -F
    iptables -X
    iptables -Z

    iptables -A INPUT -m conntrack --ctstate INVALID -j DROP
    iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

    while IFS= read -r ip; do
        [[ -n "$ip" ]] && iptables -A INPUT -s "$ip" -j ACCEPT
    done < "$WHITELIST"

    while IFS= read -r ip; do
        [[ -n "$ip" ]] && iptables -A INPUT -s "$ip" -j DROP
    done < "$BLACKLIST"

    iptables -A INPUT -p tcp --syn -m connlimit --connlimit-above 60 -j LOG --log-prefix "DDoS SYN: "
    iptables -A INPUT -p tcp --syn -m connlimit --connlimit-above 60 -j DROP

    iptables -A INPUT -p icmp --icmp-type echo-request -m limit --limit 1/second -j ACCEPT
    iptables -A INPUT -p icmp --icmp-type echo-request -j DROP

    iptables -A INPUT -p udp -m length --length 0:28 -j DROP
    iptables -A INPUT -p udp -m limit --limit 50/sec -j ACCEPT
    iptables -A INPUT -p udp -j DROP

    iptables -N port-scanning
    iptables -A port-scanning -p tcp --tcp-flags SYN,ACK,FIN,RST RST -m limit --limit 1/s --limit-burst 2 -j RETURN
    iptables -A port-scanning -j DROP

    iptables -A INPUT -p tcp --tcp-flags ALL NONE -j DROP
    iptables -A INPUT -p tcp --tcp-flags ALL ALL -j DROP
    iptables -A INPUT -j port-scanning

    iptables -A INPUT -m recent --name badguys --rcheck --seconds 60 -j DROP
    iptables -A INPUT -p tcp --dport 80 -m connlimit --connlimit-above 50 --connlimit-mask 32 -m recent --set --name badguys -j LOG --log-prefix "BanTemp: "
    iptables -A INPUT -p tcp --dport 80 -m connlimit --connlimit-above 50 --connlimit-mask 32 -m recent --set --name badguys -j DROP

    iptables -A INPUT -i lo -j ACCEPT
    iptables -A INPUT -j DROP

    log "✅ iptables rules applied."
}

case "$1" in
    enable)
        apply_sysctl
        apply_iptables
        ;;
    status)
        iptables -L -n -v
        ;;
    ban)
        echo "$2" >> "$BLACKLIST"
        log "🚫 Banned IP: $2"
        ;;
    whitelist)
        echo "$2" >> "$WHITELIST"
        log "✅ Whitelisted IP: $2"
        ;;
    logs)
        cat "$LOG_FILE"
        ;;
    *)
        echo "Usage:"
        echo "  capshield enable         - Apply protection"
        echo "  capshield status         - Show current rules"
        echo "  capshield ban <IP>       - Ban an IP"
        echo "  capshield whitelist <IP> - Whitelist an IP"
        echo "  capshield logs           - View logs"
        ;;
esac
EOF

chmod +x "$INSTALL_DIR/capshield.sh"
ln -sf "$INSTALL_DIR/capshield.sh" "$BIN_PATH"

touch "$INSTALL_DIR/config/whitelist.txt"
touch "$INSTALL_DIR/config/blacklist.txt"

cat << EOF > "$SERVICE_PATH"
[Unit]
Description=CapShield Advanced DDoS Protection
After=network.target

[Service]
ExecStart=$BIN_PATH enable
Type=oneshot
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reexec
systemctl daemon-reload
systemctl enable capshield.service
systemctl start capshield.service

summary

