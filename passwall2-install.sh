#!/bin/sh

# Passwall2 Domain Routing — VLESS XHTTP Reality + Hysteria2
# OpenWrt 23.05+ / 24.10+
# https://github.com/BalgeetTjinder/domain-routing-openwrt

GREEN='\033[32;1m'
RED='\033[31;1m'
BLUE='\033[34;1m'
NC='\033[0m'

info()   { printf "${GREEN}[*] %s${NC}\n" "$1"; }
error()  { printf "${RED}[!] %s${NC}\n" "$1"; }
header() { printf "${BLUE}%s${NC}\n" "$1"; }

# ── System check ─────────────────────────────────────────────
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

# ── Add Passwall2 package feed ───────────────────────────────
add_passwall2_feed() {
    info "Configuring Passwall2 package feed..."
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
            2>/dev/null && opkg-key add /tmp/passwall.pub 2>/dev/null
        rm -f /tmp/passwall.pub
        for feed in passwall_luci passwall_packages passwall2; do
            echo "src/gz ${feed} https://master.dl.sourceforge.net/project/openwrt-passwall-build/releases/packages-${RELEASE}/${ARCH}/${feed}" \
                >> /etc/opkg/customfeeds.conf
        done
    else
        info "Passwall2 feed already configured"
    fi
    opkg update >/dev/null 2>&1 || true
}

# ── Install packages ─────────────────────────────────────────
install_packages() {
    info "Installing packages..."

    if ! opkg list-installed 2>/dev/null | grep -q "^dnsmasq-full "; then
        info "Replacing dnsmasq with dnsmasq-full..."
        cd /tmp/ || exit 1
        opkg download dnsmasq-full >/dev/null 2>&1 || true
        opkg remove dnsmasq >/dev/null 2>&1 || true
        opkg install dnsmasq-full --cache /tmp/ >/dev/null 2>&1 || true
        [ -f /etc/config/dhcp-opkg ] && mv /etc/config/dhcp-opkg /etc/config/dhcp
    fi

    PKGS="luci-app-passwall2 xray-core geoview v2ray-geoip v2ray-geosite"
    PKGS="$PKGS kmod-nft-tproxy kmod-nft-socket kmod-tun kmod-inet-diag"
    PKGS="$PKGS ca-bundle curl"
    for pkg in $PKGS; do
        if ! opkg list-installed 2>/dev/null | grep -q "^${pkg} "; then
            info "Installing $pkg..."
            opkg install "$pkg" >/dev/null 2>&1 || error "Failed: $pkg"
        fi
    done

    opkg install hysteria >/dev/null 2>&1 || true

    for pkg in luci-app-passwall2 xray-core; do
        if ! opkg list-installed 2>/dev/null | grep -q "^${pkg} "; then
            error "$pkg installation failed — cannot continue"
            exit 1
        fi
    done

    [ -f /etc/uci-defaults/luci-passwall2 ] && sh /etc/uci-defaults/luci-passwall2 >/dev/null 2>&1
    info "All packages installed"
}

# ── Fix /tmp noexec + prestart hook ──────────────────────────
fix_tmp_exec() {
    if mount | grep " on /tmp " | grep -q "noexec"; then
        info "Remounting /tmp with exec..."
        mount -o remount,exec /tmp
    fi

    cat > /etc/passwall2-prestart.sh << 'PRESTART'
#!/bin/sh
mount -o remount,exec /tmp 2>/dev/null
mkdir -p /tmp/etc/passwall2/bin /tmp/etc/passwall2/script_func
for bin in xray hysteria; do
    src=$(command -v "$bin" 2>/dev/null)
    [ -n "$src" ] && cp -p "$src" /tmp/etc/passwall2/bin/"$bin" 2>/dev/null
done
PRESTART
    chmod +x /etc/passwall2-prestart.sh
    sh /etc/passwall2-prestart.sh

    if ! grep -q "passwall2-prestart" /etc/rc.local 2>/dev/null; then
        if grep -q '^exit 0' /etc/rc.local 2>/dev/null; then
            sed -i '/^exit 0/i sh /etc/passwall2-prestart.sh' /etc/rc.local
        else
            printf '\nsh /etc/passwall2-prestart.sh\nexit 0\n' >> /etc/rc.local
        fi
        info "Prestart hook added to /etc/rc.local"
    fi
}

# ── Configure Passwall2 ─────────────────────────────────────
configure_passwall2() {
    info "Configuring Passwall2..."

    if [ ! -s /etc/config/passwall2 ]; then
        if [ -f /usr/share/passwall2/0_default_config ]; then
            cp /usr/share/passwall2/0_default_config /etc/config/passwall2
        else
            touch /etc/config/passwall2
        fi
    fi

    # Remove default example nodes
    for s in examplenode rulenode; do
        uci -q get passwall2."$s" >/dev/null 2>&1 && uci delete passwall2."$s"
    done

    # ── Shunt rules ──
    uci set passwall2.Russia_Block=shunt_rules
    uci set passwall2.Russia_Block.remarks='Russia_Block'
    uci set passwall2.Russia_Block.network='tcp,udp'
    uci set passwall2.Russia_Block.domain_list='geosite:ru-blocked'
    uci set passwall2.Russia_Block.ip_list='geoip:ru-blocked'

    uci set passwall2.pw2_custom=shunt_rules
    uci set passwall2.pw2_custom.remarks='Custom VPN Domains'
    uci set passwall2.pw2_custom.network='tcp,udp'
    uci set passwall2.pw2_custom.domain_list=''

    # ── Main-Shunt node ──
    uci set passwall2.pw2_shunt=nodes
    uci set passwall2.pw2_shunt.remarks='Main-Shunt'
    uci set passwall2.pw2_shunt.type='Xray'
    uci set passwall2.pw2_shunt.protocol='_shunt'
    uci set passwall2.pw2_shunt.default_node='_direct'
    uci set passwall2.pw2_shunt.domainStrategy='IPOnDemand'
    uci set passwall2.pw2_shunt.domainMatcher='hybrid'
    uci set passwall2.pw2_shunt.write_ipset_direct='0'
    uci set passwall2.pw2_shunt.enable_geoview_ip='0'
    uci set passwall2.pw2_shunt.Russia_Block='_direct'
    uci set passwall2.pw2_shunt.pw2_custom='_direct'

    # ── Global settings ──
    uci set passwall2.@global[0].enabled='0'
    uci set passwall2.@global[0].node='pw2_shunt'
    uci set passwall2.@global[0].remote_dns='1.1.1.1'
    uci set passwall2.@global[0].remote_dns_protocol='tcp'
    uci set passwall2.@global[0].localhost_proxy='1'
    uci set passwall2.@global[0].client_proxy='1'
    uci set passwall2.@global[0].log_node='1'
    uci set passwall2.@global[0].loglevel='warning'

    # ── Geodata URLs (runetfreedom Russia rules) ──
    uci set passwall2.@global_rules[0].auto_update='0'
    uci set passwall2.@global_rules[0].geosite_update='1'
    uci set passwall2.@global_rules[0].geoip_update='1'
    uci set passwall2.@global_rules[0].geosite_url='https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download/geosite.dat'
    uci set passwall2.@global_rules[0].geoip_url='https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download/geoip.dat'

    # ── Forwarding (transparent proxy all ports) ──
    uci set passwall2.@global_forwarding[0].prefer_nft='1'
    uci set passwall2.@global_forwarding[0].tcp_redir_ports='1:65535'
    uci set passwall2.@global_forwarding[0].udp_redir_ports='1:65535'
    uci set passwall2.@global_forwarding[0].tcp_no_redir_ports='disable'
    uci set passwall2.@global_forwarding[0].udp_no_redir_ports='disable'

    uci commit passwall2
    mkdir -p /tmp/etc/passwall2/script_func
    info "Passwall2 configured"
}

# ── Download Russia geodata ──────────────────────────────────
download_geodata() {
    info "Downloading geosite/geoip (Russia rules)..."
    GEO_DIR="/usr/share/v2ray"
    mkdir -p "$GEO_DIR"
    BASE="https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download"

    if curl -sL --max-time 60 "$BASE/geosite.dat" -o "$GEO_DIR/geosite.dat"; then
        SIZE=$(wc -c < "$GEO_DIR/geosite.dat" 2>/dev/null)
        info "geosite.dat — ${SIZE} bytes"
    else
        error "Failed to download geosite.dat"
    fi
    if curl -sL --max-time 60 "$BASE/geoip.dat" -o "$GEO_DIR/geoip.dat"; then
        info "geoip.dat downloaded"
    else
        error "Failed to download geoip.dat"
    fi
}

# ── Finish ───────────────────────────────────────────────────
finish() {
    /etc/init.d/passwall2 enable 2>/dev/null || true
    echo ""
    header "=========================================="
    header "        INSTALLATION COMPLETE"
    header "=========================================="
    echo ""
    echo "Passwall2 is installed but NOT enabled."
    echo ""
    echo "1. Add VPN nodes:"
    echo "   Node Subscribe -> Add -> paste URL -> Save & Apply -> Manual subscription"
    echo "   — or —"
    echo "   Node List -> Add the node via the link -> paste vless://... link"
    echo ""
    echo "2. Configure routing:"
    echo "   Basic Settings -> Main Node = Main-Shunt"
    echo "   Edit Main-Shunt -> Russia_Block = [your VPN node]"
    echo "                   -> Custom VPN Domains = [your VPN node]"
    echo "                   -> Default = Direct Connection"
    echo "   Save & Apply"
    echo ""
    echo "3. Enable:"
    echo "   Basic Settings -> Enable -> Save & Apply"
    echo ""
    echo "Custom domains: Rule Manage -> Custom VPN Domains -> Domain List"
    echo ""
    echo "Commands: /etc/init.d/passwall2 restart | logread | grep passwall2"
    echo ""
}

# ── Main ─────────────────────────────────────────────────────
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
