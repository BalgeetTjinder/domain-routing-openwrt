#!/bin/sh

# Passwall2 + Russia Domain Routing for OpenWrt
# https://github.com/BalgeetTjinder/domain-routing-openwrt

GREEN='\033[32;1m'
RED='\033[31;1m'
BLUE='\033[34;1m'
NC='\033[0m'

info()   { printf "${GREEN}[*] %s${NC}\n" "$1"; }
error()  { printf "${RED}[!] %s${NC}\n" "$1"; }
header() { printf "${BLUE}%s${NC}\n" "$1"; }

# ── Detect system ────────────────────────────────────────────
check_system() {
    if [ -f /etc/openwrt_release ]; then
        . /etc/openwrt_release
    else
        error "Not an OpenWrt system"; exit 1
    fi
    RELEASE="${DISTRIB_RELEASE%.*}"
    ARCH="$DISTRIB_ARCH"
    [ -z "$RELEASE" ] || [ -z "$ARCH" ] && { error "Cannot detect release/arch"; exit 1; }
    MODEL=$(cat /tmp/sysinfo/model 2>/dev/null || echo "Unknown")
    header "Router: $MODEL  |  OpenWrt $DISTRIB_RELEASE ($ARCH)"
}

# ── Add Passwall2 package feed ───────────────────────────────
add_feed() {
    if grep -q "passwall2" /etc/opkg/customfeeds.conf 2>/dev/null; then
        info "Feed already configured"
        return
    fi
    info "Adding Passwall2 feed..."
    wget -qO /tmp/passwall.pub \
        https://master.dl.sourceforge.net/project/openwrt-passwall-build/passwall.pub 2>/dev/null \
        && opkg-key add /tmp/passwall.pub 2>/dev/null
    rm -f /tmp/passwall.pub
    for feed in passwall_luci passwall_packages passwall2; do
        echo "src/gz ${feed} https://master.dl.sourceforge.net/project/openwrt-passwall-build/releases/packages-${RELEASE}/${ARCH}/${feed}" \
            >> /etc/opkg/customfeeds.conf
    done
    opkg update >/dev/null 2>&1
}

# ── Install packages ─────────────────────────────────────────
install_packages() {
    info "Installing packages..."

    if ! opkg list-installed 2>/dev/null | grep -q "^dnsmasq-full "; then
        info "Replacing dnsmasq with dnsmasq-full..."
        cd /tmp/ && opkg download dnsmasq-full >/dev/null 2>&1
        opkg remove dnsmasq >/dev/null 2>&1
        opkg install dnsmasq-full --cache /tmp/ >/dev/null 2>&1
        [ -f /etc/config/dhcp-opkg ] && mv /etc/config/dhcp-opkg /etc/config/dhcp
    fi

    for pkg in luci-app-passwall2 xray-core kmod-nft-tproxy kmod-nft-socket ca-bundle curl; do
        opkg list-installed 2>/dev/null | grep -q "^${pkg} " || opkg install "$pkg" >/dev/null 2>&1
    done
    opkg install hysteria >/dev/null 2>&1 || true

    for pkg in luci-app-passwall2 xray-core; do
        opkg list-installed 2>/dev/null | grep -q "^${pkg} " || { error "$pkg not installed"; exit 1; }
    done

    [ -f /etc/uci-defaults/luci-passwall2 ] && sh /etc/uci-defaults/luci-passwall2 >/dev/null 2>&1
    info "Packages installed"
}

# ── Configure shunt rules ───────────────────────────────────
configure_routing() {
    info "Configuring routing rules..."

    [ -s /etc/config/passwall2 ] || {
        [ -f /usr/share/passwall2/0_default_config ] \
            && cp /usr/share/passwall2/0_default_config /etc/config/passwall2 \
            || touch /etc/config/passwall2
    }

    # Shunt rule: Russia blocked domains/IPs
    uci set passwall2.Russia_Block=shunt_rules
    uci set passwall2.Russia_Block.remarks='Russia_Block'
    uci set passwall2.Russia_Block.network='tcp,udp'
    uci set passwall2.Russia_Block.domain_list='geosite:ru-blocked'
    uci set passwall2.Russia_Block.ip_list='geoip:ru-blocked'

    # Shunt rule: user-defined domains (fill via LuCI)
    uci set passwall2.pw2_custom=shunt_rules
    uci set passwall2.pw2_custom.remarks='Custom VPN Domains'
    uci set passwall2.pw2_custom.network='tcp,udp'
    uci set passwall2.pw2_custom.domain_list=''

    # Main-Shunt node — routes Russia_Block and custom domains through VPN
    uci set passwall2.pw2_shunt=nodes
    uci set passwall2.pw2_shunt.remarks='Main-Shunt'
    uci set passwall2.pw2_shunt.type='Xray'
    uci set passwall2.pw2_shunt.protocol='_shunt'
    uci set passwall2.pw2_shunt.default_node='_direct'
    uci set passwall2.pw2_shunt.domainStrategy='IPOnDemand'
    uci set passwall2.pw2_shunt.domainMatcher='hybrid'
    uci set passwall2.pw2_shunt.Russia_Block='_direct'
    uci set passwall2.pw2_shunt.pw2_custom='_direct'
    # Disable geoview IP validation — incompatible with runetfreedom geodata
    uci set passwall2.pw2_shunt.write_ipset_direct='0'
    uci set passwall2.pw2_shunt.enable_geoview_ip='0'

    # Point main node to shunt, keep disabled until user adds VPN nodes
    uci set passwall2.@global[0].enabled='0'
    uci set passwall2.@global[0].node='pw2_shunt'

    # Geodata source: runetfreedom Russia rules
    uci set passwall2.@global_rules[0].geosite_url='https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download/geosite.dat'
    uci set passwall2.@global_rules[0].geoip_url='https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download/geoip.dat'

    uci commit passwall2
    info "Routing rules configured"
}

# ── Download Russia geodata ──────────────────────────────────
download_geodata() {
    info "Downloading Russia geodata..."
    GEO_DIR="/usr/share/v2ray"
    mkdir -p "$GEO_DIR"
    BASE="https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download"

    curl -sL --max-time 60 "$BASE/geosite.dat" -o "$GEO_DIR/geosite.dat" \
        && info "geosite.dat OK" || error "Failed: geosite.dat"
    curl -sL --max-time 60 "$BASE/geoip.dat" -o "$GEO_DIR/geoip.dat" \
        && info "geoip.dat OK" || error "Failed: geoip.dat"
}

# ── Done ─────────────────────────────────────────────────────
finish() {
    /etc/init.d/passwall2 enable 2>/dev/null || true
    echo ""
    header "=========================================="
    header "        INSTALLATION COMPLETE"
    header "=========================================="
    echo ""
    echo "Next steps in LuCI (Services -> PassWall2):"
    echo ""
    echo "  1. Add VPN nodes:"
    echo "     Node Subscribe -> Add -> paste URL -> Save & Apply -> Manual subscription"
    echo "     — or —"
    echo "     Node List -> Add node via link -> paste vless://... link"
    echo ""
    echo "  2. Configure routing:"
    echo "     Basic Settings -> Main Node = Main-Shunt"
    echo "     Edit Main-Shunt -> Russia_Block      = [your VPN node]"
    echo "                     -> Custom VPN Domains = [your VPN node]"
    echo "                     -> Default            = Direct Connection"
    echo "     Save & Apply"
    echo ""
    echo "  3. Enable:"
    echo "     Basic Settings -> Enable -> Save & Apply"
    echo "     Then: /etc/init.d/passwall2 restart"
    echo ""
}

# ── Main ─────────────────────────────────────────────────────
echo ""
header "=========================================="
header "  Passwall2 + Russia Domain Routing"
header "=========================================="
echo ""
printf "Continue? [y/N]: "
read CONFIRM
case $CONFIRM in [yY]|[yY][eE][sS]) ;; *) echo "Cancelled"; exit 0 ;; esac

check_system
add_feed
install_packages
configure_routing
download_geodata
finish
