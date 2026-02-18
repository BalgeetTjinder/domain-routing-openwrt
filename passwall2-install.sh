#!/bin/sh

# Passwall2 Domain Routing - VLESS XHTTP Reality + Hysteria2
# OpenWrt 23.05+ / 24.10+
# https://github.com/BalgeetTjinder/domain-routing-openwrt

GREEN='\033[32;1m'
RED='\033[31;1m'
BLUE='\033[34;1m'
NC='\033[0m'

info()   { printf "${GREEN}[*] %s${NC}\n" "$1"; }
error()  { printf "${RED}[!] %s${NC}\n" "$1"; }
header() { printf "${BLUE}%s${NC}\n" "$1"; }

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
    VERSION_NUM=$(echo "$VERSION" | sed 's/[^0-9].*//')
    if [ -z "$VERSION_NUM" ]; then
        error "Cannot parse version number"
        exit 1
    fi
    if [ "$VERSION_NUM" -lt 23 ]; then
        error "Script requires OpenWrt 23.05+"
        exit 1
    fi
}

add_passwall2_feed() {
    info "Configuring Passwall2 package feed..."
    RELEASE=""
    ARCH=""
    if [ -f /etc/openwrt_release ]; then
        . /etc/openwrt_release
        RELEASE="${DISTRIB_RELEASE%.*}"
        ARCH="$DISTRIB_ARCH"
    fi
    if [ -z "$RELEASE" ] || [ -z "$ARCH" ]; then
        error "Cannot detect OpenWrt release/arch"
        exit 1
    fi
    if ! grep -q "passwall2" /etc/opkg/customfeeds.conf 2>/dev/null; then
        info "Adding feed for OpenWrt $RELEASE ($ARCH)..."
        wget -q -O /tmp/passwall.pub \
            https://master.dl.sourceforge.net/project/openwrt-passwall-build/passwall.pub \
            2>/dev/null && opkg-key add /tmp/passwall.pub 2>/dev/null || true
        for feed in passwall_luci passwall_packages passwall2; do
            echo "src/gz ${feed} https://master.dl.sourceforge.net/project/openwrt-passwall-build/releases/packages-${RELEASE}/${ARCH}/${feed}" \
                >> /etc/opkg/customfeeds.conf
        done
    else
        info "Passwall2 feed already configured"
    fi
    info "Updating package lists..."
    opkg update >/dev/null 2>&1 || true
    info "Done"
}

install_packages() {
    info "Installing packages..."
    if ! opkg list-installed 2>/dev/null | grep -q "^dnsmasq-full "; then
        info "Replacing dnsmasq with dnsmasq-full..."
        cd /tmp/ || exit 1
        opkg download dnsmasq-full >/dev/null 2>&1 || true
        opkg remove dnsmasq >/dev/null 2>&1 || true
        opkg install dnsmasq-full --cache /tmp/ >/dev/null 2>&1 || true
        [ -f /etc/config/dhcp-opkg ] && mv /etc/config/dhcp-opkg /etc/config/dhcp
    else
        info "dnsmasq-full already installed"
    fi

    CORE_PKGS="luci-app-passwall2 xray-core geoview v2ray-geoip v2ray-geosite"
    KERN_PKGS="kmod-nft-tproxy kmod-nft-socket kmod-tun kmod-inet-diag"
    UTIL_PKGS="ca-bundle curl"
    for pkg in $CORE_PKGS $KERN_PKGS $UTIL_PKGS; do
        if ! opkg list-installed 2>/dev/null | grep -q "^${pkg} "; then
            info "Installing $pkg..."
            opkg install "$pkg" >/dev/null 2>&1 || error "Warning: failed to install $pkg"
        else
            info "$pkg already installed"
        fi
    done

    # Optional: standalone Hysteria2 client (for Salamander obfs; Xray does not support it)
    if ! opkg list-installed 2>/dev/null | grep -q "^hysteria "; then
        info "Installing hysteria (optional, for Hysteria2 nodes with Salamander obfs)..."
        opkg install hysteria >/dev/null 2>&1 || info "hysteria not in feed or skipped"
    fi

    if ! opkg list-installed 2>/dev/null | grep -q "^luci-app-passwall2 "; then
        error "luci-app-passwall2 installation failed"
        exit 1
    fi
    if ! opkg list-installed 2>/dev/null | grep -q "^xray-core "; then
        error "xray-core installation failed"
        exit 1
    fi

    if [ -f /etc/uci-defaults/luci-passwall2 ]; then
        info "Initializing Passwall2 config..."
        sh /etc/uci-defaults/luci-passwall2 >/dev/null 2>&1 || true
    fi
    info "All packages installed"
}

configure_passwall2() {
    info "Configuring Passwall2 routing structure..."
    if [ ! -s /etc/config/passwall2 ]; then
        if [ -f /usr/share/passwall2/0_default_config ]; then
            cp /usr/share/passwall2/0_default_config /etc/config/passwall2
        else
            touch /etc/config/passwall2
        fi
    fi

    for section in examplenode rulenode; do
        if uci -q get passwall2."$section" >/dev/null 2>&1; then
            uci delete passwall2."$section" 2>/dev/null || true
        fi
    done

    uci set passwall2.pw2_vless=nodes
    uci set passwall2.pw2_vless.remarks='VLESS-XHTTP-Reality'
    uci set passwall2.pw2_vless.type='Xray'
    uci set passwall2.pw2_vless.protocol='vless'
    uci set passwall2.pw2_vless.address=''
    uci set passwall2.pw2_vless.port='443'
    uci set passwall2.pw2_vless.uuid=''
    uci set passwall2.pw2_vless.encryption='none'
    uci set passwall2.pw2_vless.tls='1'
    uci set passwall2.pw2_vless.reality='1'
    uci set passwall2.pw2_vless.reality_publicKey=''
    uci set passwall2.pw2_vless.reality_shortId=''
    uci set passwall2.pw2_vless.tls_serverName='www.microsoft.com'
    uci set passwall2.pw2_vless.fingerprint='chrome'
    uci set passwall2.pw2_vless.transport='xhttp'
    uci set passwall2.pw2_vless.xhttp_mode='auto'
    uci set passwall2.pw2_vless.xhttp_path='/'
    uci set passwall2.pw2_vless.tcp_fast_open='0'
    uci set passwall2.pw2_vless.tcpMptcp='0'

    uci set passwall2.pw2_hy2=nodes
    uci set passwall2.pw2_hy2.remarks='Hysteria2'
    uci set passwall2.pw2_hy2.type='Xray'
    uci set passwall2.pw2_hy2.protocol='hysteria2'
    uci set passwall2.pw2_hy2.address=''
    uci set passwall2.pw2_hy2.port='8443'
    uci set passwall2.pw2_hy2.tls='1'
    uci set passwall2.pw2_hy2.tls_serverName=''
    uci set passwall2.pw2_hy2.hysteria2_auth_password=''
    uci set passwall2.pw2_hy2.hysteria2_up_mbps='100'
    uci set passwall2.pw2_hy2.hysteria2_down_mbps='100'

    uci set passwall2.Russia_Block=shunt_rules
    uci set passwall2.Russia_Block.remarks='Russia_Block'
    uci set passwall2.Russia_Block.network='tcp,udp'
    uci set passwall2.Russia_Block.domain_list='geosite:ru-blocked'
    uci set passwall2.Russia_Block.ip_list='geoip:ru-blocked'

    uci set passwall2.pw2_custom=shunt_rules
    uci set passwall2.pw2_custom.remarks='Custom VPN Domains'
    uci set passwall2.pw2_custom.network='tcp,udp'
    uci set passwall2.pw2_custom.domain_list=''

    uci set passwall2.pw2_shunt=nodes
    uci set passwall2.pw2_shunt.remarks='Main-Shunt'
    uci set passwall2.pw2_shunt.type='Xray'
    uci set passwall2.pw2_shunt.protocol='_shunt'
    uci set passwall2.pw2_shunt.default_node='_direct'
    uci set passwall2.pw2_shunt.domainStrategy='IPOnDemand'
    uci set passwall2.pw2_shunt.domainMatcher='hybrid'
    uci set passwall2.pw2_shunt.write_ipset_direct='1'
    uci set passwall2.pw2_shunt.enable_geoview_ip='1'
    uci set passwall2.pw2_shunt.Russia_Block='pw2_vless'
    uci set passwall2.pw2_shunt.pw2_custom='pw2_vless'

    uci set passwall2.@global[0].enabled='0'
    uci set passwall2.@global[0].node='pw2_shunt'
    uci set passwall2.@global[0].remote_dns='1.1.1.1'
    uci set passwall2.@global[0].remote_dns_protocol='tcp'
    uci set passwall2.@global[0].localhost_proxy='1'
    uci set passwall2.@global[0].client_proxy='1'
    uci set passwall2.@global[0].log_node='1'
    uci set passwall2.@global[0].loglevel='error'

    uci set passwall2.@global_rules[0].auto_update='1'
    uci set passwall2.@global_rules[0].geosite_update='1'
    uci set passwall2.@global_rules[0].geoip_update='1'
    uci set passwall2.@global_rules[0].geosite_url='https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download/geosite.dat'
    uci set passwall2.@global_rules[0].geoip_url='https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download/geoip.dat'

    uci set passwall2.@global_forwarding[0].prefer_nft='1'
    uci set passwall2.@global_forwarding[0].tcp_redir_ports='1:65535'
    uci set passwall2.@global_forwarding[0].udp_redir_ports='1:65535'
    uci set passwall2.@global_forwarding[0].tcp_no_redir_ports='disable'
    uci set passwall2.@global_forwarding[0].udp_no_redir_ports='disable'

    uci commit passwall2 2>/dev/null || true
    mkdir -p /tmp/etc/passwall2/script_func
    info "Passwall2 routing structure configured"
}

fix_tmp_exec() {
    if mount | grep -q "tmp.*noexec"; then
        info "Fixing /tmp noexec (required for Xray/Hysteria binaries)..."
        mount -o remount,exec /tmp
    fi
    if ! grep -q "remount,exec /tmp" /etc/rc.local 2>/dev/null; then
        sed -i '/^exit 0/i mount -o remount,exec /tmp' /etc/rc.local 2>/dev/null || true
        info "/tmp exec persisted in /etc/rc.local"
    fi
}

download_geodata() {
    info "Downloading geosite/geoip (Russia rules)..."
    GEO_DIR="/usr/share/v2ray"
    mkdir -p "$GEO_DIR"
    GEOSITE_URL="https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download/geosite.dat"
    GEOIP_URL="https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download/geoip.dat"
    if curl -sL --max-time 60 "$GEOSITE_URL" -o "$GEO_DIR/geosite.dat" 2>/dev/null; then
        GEOSITE_SIZE=$(wc -c < "$GEO_DIR/geosite.dat" 2>/dev/null || echo "?")
        info "geosite.dat downloaded (${GEOSITE_SIZE} bytes)"
    else
        error "Failed to download geosite.dat"
    fi
    if curl -sL --max-time 60 "$GEOIP_URL" -o "$GEO_DIR/geoip.dat" 2>/dev/null; then
        info "geoip.dat downloaded"
    else
        error "Failed to download geoip.dat"
    fi
}

finish() {
    /etc/init.d/passwall2 enable 2>/dev/null || true
    echo ""
    header "=========================================="
    header "        INSTALLATION COMPLETE"
    header "=========================================="
    echo ""
    echo "Passwall2 is installed but NOT enabled yet."
    echo ""
    echo "Add your VPN nodes via LuCI (pick one method):"
    echo ""
    echo "  Option A — Subscription:"
    echo "    Services -> PassWall2 -> Node Subscribe -> Add"
    echo "    Paste subscription URL -> Save & Apply -> Manual Subscribe"
    echo ""
    echo "  Option B — Manual node:"
    echo "    Services -> PassWall2 -> Node List -> Add"
    echo "    Fill in your VPS data -> Save & Apply"
    echo ""
    echo "Then enable:"
    echo "  1. Basic Settings -> Main Node = Main-Shunt"
    echo "  2. Click on Main-Shunt -> set Russia_Block and Custom VPN Domains"
    echo "     to your VPN node -> Save & Apply"
    echo "  3. Basic Settings -> Enable -> Save & Apply"
    echo ""
    echo "Custom domains: PassWall2 -> Rule -> 'Custom VPN Domains' -> Domain List"
    echo ""
    echo "Useful commands:"
    echo "  logread | grep passwall2        # view logs"
    echo "  /etc/init.d/passwall2 restart   # restart service"
    echo ""
}

echo ""
header "=========================================="
header "  Passwall2 Domain Routing"
header "  VLESS XHTTP Reality + Hysteria2"
header "=========================================="
echo ""
printf "Continue? [y/N]: "
read CONFIRM
case $CONFIRM in
    [yY]|[yY][eE][sS]) ;;
    *) echo "Cancelled"; exit 0 ;;
esac

check_system
add_passwall2_feed
install_packages
fix_tmp_exec
configure_passwall2
download_geodata
finish
