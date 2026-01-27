#!/bin/sh

# Domain Routing OpenWrt - Sing-box (VLESS Reality + Hysteria 2)
# https://github.com/BalgeetTjinder/domain-routing-openwrt

GREEN='\033[32;1m'
RED='\033[31;1m'
BLUE='\033[34;1m'
NC='\033[0m'

info() { printf "${GREEN}[*] %s${NC}\n" "$1"; }
error() { printf "${RED}[!] %s${NC}\n" "$1"; }
header() { printf "${BLUE}%s${NC}\n" "$1"; }

# Check system
check_system() {
    MODEL=$(cat /tmp/sysinfo/model 2>/dev/null || echo "Unknown")
    
    if [ -f /etc/os-release ]; then
        . /etc/os-release
    else
        error "Cannot detect OpenWrt version"
        exit 1
    fi
    
    header "Router: $MODEL"
    header "Version: $VERSION"
    
    # Extract major version number
    VERSION_NUM=$(echo "$VERSION" | sed 's/[^0-9].*//')
    
    if [ -z "$VERSION_NUM" ]; then
        error "Cannot parse version number"
        exit 1
    fi
    
    if [ "$VERSION_NUM" -lt 23 ]; then
        error "Script requires OpenWrt 23.05+ or 24.10+"
        exit 1
    fi
}

# Update package list
update_packages() {
    info "Updating package list..."
    opkg update >/dev/null 2>&1 || true
    info "Done"
}

# Install packages
install_packages() {
    info "Installing packages..."
    
    for pkg in curl nano; do
        if ! opkg list-installed 2>/dev/null | grep -q "^${pkg} "; then
            info "Installing $pkg..."
            opkg install "$pkg" >/dev/null 2>&1 || true
        else
            info "$pkg already installed"
        fi
    done
    
    # dnsmasq-full
    if opkg list-installed 2>/dev/null | grep -q "^dnsmasq-full "; then
        info "dnsmasq-full already installed"
    else
        info "Installing dnsmasq-full..."
        cd /tmp/ || exit 1
        opkg download dnsmasq-full >/dev/null 2>&1 || true
        opkg remove dnsmasq >/dev/null 2>&1 || true
        opkg install dnsmasq-full --cache /tmp/ >/dev/null 2>&1 || true
        [ -f /etc/config/dhcp-opkg ] && mv /etc/config/dhcp-opkg /etc/config/dhcp
    fi
    
    # sing-box
    if opkg list-installed 2>/dev/null | grep -q "^sing-box "; then
        info "sing-box already installed"
    else
        info "Installing sing-box..."
        opkg install sing-box >/dev/null 2>&1 || true
    fi
    
    # Verify sing-box installed
    if ! opkg list-installed 2>/dev/null | grep -q "^sing-box "; then
        error "Failed to install sing-box"
        exit 1
    fi
    
    # Enable sing-box
    if [ -f /etc/config/sing-box ]; then
        sed -i "s/option enabled '0'/option enabled '1'/" /etc/config/sing-box 2>/dev/null || true
        sed -i "s/option user 'sing-box'/option user 'root'/" /etc/config/sing-box 2>/dev/null || true
    fi
    
    info "Packages installed"
}

# Configure Sing-box
configure_singbox() {
    echo ""
    header "=== Sing-box Configuration ==="
    echo ""
    echo "Get these values from S-UI panel on your VPS"
    echo ""
    
    printf "VPS IP address: "
    read VPS_IP
    
    if [ -z "$VPS_IP" ]; then
        error "VPS IP is required"
        exit 1
    fi
    
    echo ""
    header "--- VLESS Reality ---"
    printf "UUID: "
    read VLESS_UUID
    
    if [ -z "$VLESS_UUID" ]; then
        error "UUID is required"
        exit 1
    fi
    
    printf "Public Key: "
    read VLESS_PUBLIC_KEY
    
    if [ -z "$VLESS_PUBLIC_KEY" ]; then
        error "Public Key is required"
        exit 1
    fi
    
    printf "Short ID (first one): "
    read VLESS_SHORT_ID
    VLESS_SHORT_ID=${VLESS_SHORT_ID:-""}
    
    printf "SNI [www.microsoft.com]: "
    read VLESS_SNI
    VLESS_SNI=${VLESS_SNI:-www.microsoft.com}
    
    printf "Port [443]: "
    read VLESS_PORT
    VLESS_PORT=${VLESS_PORT:-443}
    
    echo ""
    header "--- Hysteria 2 ---"
    printf "Password: "
    read HY2_PASSWORD
    
    if [ -z "$HY2_PASSWORD" ]; then
        error "Hysteria 2 password is required"
        exit 1
    fi
    
    printf "Domain (SNI): "
    read HY2_SNI
    
    if [ -z "$HY2_SNI" ]; then
        error "Hysteria 2 domain is required"
        exit 1
    fi
    
    printf "Port [8443]: "
    read HY2_PORT
    HY2_PORT=${HY2_PORT:-8443}
    
    printf "Upload Mbps [100]: "
    read HY2_UP
    HY2_UP=${HY2_UP:-100}
    
    printf "Download Mbps [100]: "
    read HY2_DOWN
    HY2_DOWN=${HY2_DOWN:-100}
    
    info "Creating /etc/sing-box/config.json..."
    
    mkdir -p /etc/sing-box
    
    cat > /etc/sing-box/config.json << EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "dns": {
    "servers": [
      {"tag": "google", "address": "tls://8.8.8.8"},
      {"tag": "local", "address": "local", "detour": "direct"}
    ],
    "rules": [{"outbound": "any", "server": "local"}],
    "strategy": "ipv4_only"
  },
  "inbounds": [
    {
      "type": "tun",
      "tag": "tun-in",
      "interface_name": "tun0",
      "address": ["172.16.250.1/30"],
      "mtu": 1400,
      "auto_route": false,
      "strict_route": false,
      "sniff": true,
      "sniff_override_destination": true
    }
  ],
  "outbounds": [
    {
      "type": "urltest",
      "tag": "auto",
      "outbounds": ["vless-reality", "hysteria2"],
      "url": "https://www.gstatic.com/generate_204",
      "interval": "1m",
      "tolerance": 50
    },
    {
      "type": "vless",
      "tag": "vless-reality",
      "server": "${VPS_IP}",
      "server_port": ${VLESS_PORT},
      "uuid": "${VLESS_UUID}",
      "flow": "xtls-rprx-vision",
      "tls": {
        "enabled": true,
        "server_name": "${VLESS_SNI}",
        "utls": {"enabled": true, "fingerprint": "chrome"},
        "reality": {"enabled": true, "public_key": "${VLESS_PUBLIC_KEY}", "short_id": "${VLESS_SHORT_ID}"}
      }
    },
    {
      "type": "hysteria2",
      "tag": "hysteria2",
      "server": "${VPS_IP}",
      "server_port": ${HY2_PORT},
      "password": "${HY2_PASSWORD}",
      "tls": {"enabled": true, "server_name": "${HY2_SNI}", "alpn": ["h3"]},
      "up_mbps": ${HY2_UP},
      "down_mbps": ${HY2_DOWN}
    },
    {"type": "direct", "tag": "direct"},
    {"type": "block", "tag": "block"},
    {"type": "dns", "tag": "dns-out"}
  ],
  "route": {
    "rules": [
      {"protocol": "dns", "outbound": "dns-out"},
      {"ip_is_private": true, "outbound": "direct"}
    ],
    "auto_detect_interface": true,
    "final": "auto"
  }
}
EOF

    info "Config created"
}

# Configure routing
configure_routing() {
    info "Configuring routing..."
    
    # Ensure rt_tables file exists
    [ ! -f /etc/iproute2/rt_tables ] && mkdir -p /etc/iproute2 && touch /etc/iproute2/rt_tables
    
    if ! grep -q "99 vpn" /etc/iproute2/rt_tables 2>/dev/null; then
        echo "99 vpn" >> /etc/iproute2/rt_tables
    fi
    
    if ! uci show network 2>/dev/null | grep -q "name='mark0x1'"; then
        uci add network rule >/dev/null 2>&1 || true
        uci set network.@rule[-1].name='mark0x1'
        uci set network.@rule[-1].mark='0x1'
        uci set network.@rule[-1].priority='100'
        uci set network.@rule[-1].lookup='vpn'
        uci commit network 2>/dev/null || true
    fi
    
    mkdir -p /etc/hotplug.d/iface
    mkdir -p /etc/hotplug.d/net
    
    cat > /etc/hotplug.d/iface/30-vpnroute << 'HOTPLUGEOF'
#!/bin/sh
sleep 10
ip route replace table vpn default dev tun0 2>/dev/null || true
HOTPLUGEOF
    
    chmod +x /etc/hotplug.d/iface/30-vpnroute
    cp /etc/hotplug.d/iface/30-vpnroute /etc/hotplug.d/net/30-vpnroute 2>/dev/null || true
    
    info "Routing configured"
}

# Configure firewall
configure_firewall() {
    info "Configuring firewall..."
    
    if ! uci show firewall 2>/dev/null | grep -q "name='singbox'"; then
        uci add firewall zone >/dev/null 2>&1 || true
        uci set firewall.@zone[-1].name='singbox'
        uci set firewall.@zone[-1].device='tun0'
        uci set firewall.@zone[-1].forward='ACCEPT'
        uci set firewall.@zone[-1].output='ACCEPT'
        uci set firewall.@zone[-1].input='ACCEPT'
        uci set firewall.@zone[-1].masq='1'
        uci set firewall.@zone[-1].mtu_fix='1'
        uci set firewall.@zone[-1].family='ipv4'
        uci commit firewall 2>/dev/null || true
    fi
    
    if ! uci show firewall 2>/dev/null | grep -q "name='singbox-lan'"; then
        uci add firewall forwarding >/dev/null 2>&1 || true
        uci set firewall.@forwarding[-1].name='singbox-lan'
        uci set firewall.@forwarding[-1].dest='singbox'
        uci set firewall.@forwarding[-1].src='lan'
        uci set firewall.@forwarding[-1].family='ipv4'
        uci commit firewall 2>/dev/null || true
    fi
    
    if ! uci show firewall 2>/dev/null | grep -q "name='vpn_domains'"; then
        uci add firewall ipset >/dev/null 2>&1 || true
        uci set firewall.@ipset[-1].name='vpn_domains'
        uci set firewall.@ipset[-1].match='dst_net'
        uci commit firewall 2>/dev/null || true
    fi
    
    if ! uci show firewall 2>/dev/null | grep -q "name='mark_domains'"; then
        uci add firewall rule >/dev/null 2>&1 || true
        uci set firewall.@rule[-1].name='mark_domains'
        uci set firewall.@rule[-1].src='lan'
        uci set firewall.@rule[-1].dest='*'
        uci set firewall.@rule[-1].proto='all'
        uci set firewall.@rule[-1].ipset='vpn_domains'
        uci set firewall.@rule[-1].set_mark='0x1'
        uci set firewall.@rule[-1].target='MARK'
        uci set firewall.@rule[-1].family='ipv4'
        uci commit firewall 2>/dev/null || true
    fi
    
    info "Firewall configured"
}

# Configure dnsmasq
configure_dnsmasq() {
    info "Configuring dnsmasq..."
    
    # Get major version
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        VERSION_NUM=$(echo "$VERSION" | sed 's/[^0-9].*//')
    else
        VERSION_NUM=24
    fi
    
    # For OpenWrt 24.x use confdir
    if [ -n "$VERSION_NUM" ] && [ "$VERSION_NUM" -ge 24 ] 2>/dev/null; then
        uci set dhcp.@dnsmasq[0].confdir='/tmp/dnsmasq.d' 2>/dev/null || true
        uci commit dhcp 2>/dev/null || true
    fi
    
    mkdir -p /tmp/dnsmasq.d
    
    info "dnsmasq configured"
}

# DNS resolver
configure_dns() {
    echo ""
    echo "Install Stubby for DNS encryption?"
    echo "Recommended if your ISP spoofs DNS"
    echo ""
    echo "1) Yes"
    echo "2) No"
    
    printf "Choice [1-2]: "
    read DNS_CHOICE
    
    case $DNS_CHOICE in
        1)
            if ! opkg list-installed 2>/dev/null | grep -q "^stubby "; then
                info "Installing Stubby..."
                opkg install stubby >/dev/null 2>&1 || true
                
                uci set dhcp.@dnsmasq[0].noresolv='1' 2>/dev/null || true
                uci -q delete dhcp.@dnsmasq[0].server 2>/dev/null || true
                uci add_list dhcp.@dnsmasq[0].server='127.0.0.1#5453' 2>/dev/null || true
                uci commit dhcp 2>/dev/null || true
                
                /etc/init.d/stubby enable 2>/dev/null || true
                /etc/init.d/stubby start 2>/dev/null || true
            fi
            info "Stubby installed"
            ;;
        *)
            info "Skipping Stubby"
            ;;
    esac
}

# Create getdomains script
create_getdomains() {
    echo ""
    echo "Select domain list:"
    echo "1) Russia (inside) - bypass blocks"
    echo "2) Russia (outside) - access Russian sites"
    echo "3) Ukraine"
    
    printf "Choice [1-3]: "
    read COUNTRY
    
    case $COUNTRY in
        1) DOMAINS_URL="https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Russia/inside-dnsmasq-nfset.lst" ;;
        2) DOMAINS_URL="https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Russia/outside-dnsmasq-nfset.lst" ;;
        3) DOMAINS_URL="https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Ukraine/inside-dnsmasq-nfset.lst" ;;
        *) DOMAINS_URL="https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Russia/inside-dnsmasq-nfset.lst" ;;
    esac
    
    info "Creating /etc/init.d/getdomains..."
    
    cat > /etc/init.d/getdomains << EOF
#!/bin/sh /etc/rc.common

START=99

start() {
    DOMAINS="${DOMAINS_URL}"
    
    count=0
    while true; do
        if curl -s -m 5 https://github.com >/dev/null 2>&1; then
            curl -s -f "\$DOMAINS" -o /tmp/dnsmasq.d/domains.lst
            break
        else
            count=\$((count+1))
            [ \$count -gt 30 ] && break
            sleep 5
        fi
    done
    
    if [ -f /tmp/dnsmasq.d/domains.lst ]; then
        /etc/init.d/dnsmasq restart
    fi
}
EOF
    
    chmod +x /etc/init.d/getdomains
    /etc/init.d/getdomains enable 2>/dev/null || true
    
    # Add to cron using OpenWrt method
    CRON_FILE="/etc/crontabs/root"
    mkdir -p /etc/crontabs
    touch "$CRON_FILE"
    
    if ! grep -q "getdomains" "$CRON_FILE" 2>/dev/null; then
        echo "0 */8 * * * /etc/init.d/getdomains start" >> "$CRON_FILE"
        /etc/init.d/cron enable 2>/dev/null || true
        /etc/init.d/cron restart 2>/dev/null || true
    fi
    
    info "getdomains script created"
}

# Start services
start_services() {
    info "Starting services..."
    
    /etc/init.d/firewall restart >/dev/null 2>&1 || true
    /etc/init.d/network restart >/dev/null 2>&1 || true
    
    info "Waiting for network..."
    sleep 5
    
    /etc/init.d/sing-box enable 2>/dev/null || true
    /etc/init.d/sing-box restart 2>/dev/null || true
    
    info "Waiting for sing-box..."
    sleep 7
    
    # Add route manually
    ip route replace table vpn default dev tun0 2>/dev/null || true
    
    /etc/init.d/getdomains start 2>/dev/null || true
    
    sleep 3
    
    if ip link show tun0 >/dev/null 2>&1; then
        info "SUCCESS: tun0 interface is up"
    else
        error "WARNING: tun0 not found"
        error "Check logs: logread | grep sing-box"
        error "Check config: cat /etc/sing-box/config.json"
    fi
    
    echo ""
    header "=========================================="
    header "        INSTALLATION COMPLETE"
    header "=========================================="
    echo ""
    echo "Test: try opening a blocked website"
    echo ""
    echo "Useful commands:"
    echo "  logread | grep sing-box        - view logs"
    echo "  service sing-box restart       - restart"
    echo "  /etc/init.d/getdomains start   - update domains"
    echo "  cat /etc/sing-box/config.json  - view config"
    echo ""
}

# === MAIN ===

echo ""
header "=========================================="
header "  Domain Routing OpenWrt"
header "  Sing-box: VLESS Reality + Hysteria 2"
header "=========================================="
echo ""

echo "WARNING: Changes cannot be automatically reverted!"
echo ""
printf "Continue? [y/N]: "
read CONFIRM

case $CONFIRM in
    [yY]|[yY][eE][sS]) ;;
    *) echo "Cancelled"; exit 0 ;;
esac

check_system
update_packages
install_packages
configure_singbox
configure_routing
configure_firewall
configure_dnsmasq
configure_dns
create_getdomains
start_services
