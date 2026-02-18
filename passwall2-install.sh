#!/bin/sh

# Passwall2 clean install for OpenWrt 23.05/24.10
# VLESS + Hysteria2 templates + Russia routing presets

GREEN='\033[32;1m'
RED='\033[31;1m'
BLUE='\033[34;1m'
NC='\033[0m'

info()   { printf "${GREEN}[*] %s${NC}\n" "$1"; }
warn()   { printf "${RED}[!] %s${NC}\n" "$1"; }
header() { printf "${BLUE}%s${NC}\n" "$1"; }

release=""
arch=""

check_system() {
    [ -f /etc/openwrt_release ] || {
        warn "OpenWrt not detected"; exit 1;
    }
    . /etc/openwrt_release
    release="${DISTRIB_RELEASE%.*}"
    arch="$DISTRIB_ARCH"
    [ -n "$release" ] && [ -n "$arch" ] || {
        warn "Unable to detect OpenWrt release/arch"; exit 1;
    }
    model="$(cat /tmp/sysinfo/model 2>/dev/null || echo Unknown)"
    header "Router: $model"
    header "OpenWrt: $DISTRIB_RELEASE ($arch)"
}

add_feed() {
    info "Configuring Passwall feed..."
    feed_file="/etc/opkg/customfeeds.conf"
    [ -f "$feed_file" ] || touch "$feed_file"

    if ! grep -q "openwrt-passwall-build/releases/packages-${release}/${arch}" "$feed_file" 2>/dev/null; then
        wget -qO /tmp/passwall.pub "https://master.dl.sourceforge.net/project/openwrt-passwall-build/passwall.pub" 2>/dev/null \
            && opkg-key add /tmp/passwall.pub >/dev/null 2>&1
        rm -f /tmp/passwall.pub
        {
            echo "src/gz passwall_packages https://master.dl.sourceforge.net/project/openwrt-passwall-build/releases/packages-${release}/${arch}/passwall_packages"
            echo "src/gz passwall_luci https://master.dl.sourceforge.net/project/openwrt-passwall-build/releases/packages-${release}/${arch}/passwall_luci"
            echo "src/gz passwall2 https://master.dl.sourceforge.net/project/openwrt-passwall-build/releases/packages-${release}/${arch}/passwall2"
        } >> "$feed_file"
    else
        info "Feed already configured"
    fi

    info "Updating package indexes..."
    opkg update >/dev/null 2>&1 || {
        warn "opkg update failed"; exit 1;
    }
}

install_dnsmasq_full() {
    if opkg list-installed 2>/dev/null | grep -q "^dnsmasq-full "; then
        return 0
    fi

    info "Replacing dnsmasq with dnsmasq-full..."
    cd /tmp || return 1
    opkg download dnsmasq-full >/dev/null 2>&1 || return 1
    opkg remove dnsmasq >/dev/null 2>&1 || true
    opkg install dnsmasq-full --cache /tmp >/dev/null 2>&1 || return 1
    [ -f /etc/config/dhcp-opkg ] && mv /etc/config/dhcp-opkg /etc/config/dhcp
    return 0
}

install_packages() {
    info "Installing required packages..."
    install_dnsmasq_full || warn "dnsmasq-full setup failed, continuing"

    required_pkgs="luci-app-passwall2 xray-core geoview v2ray-geoip v2ray-geosite ca-bundle curl"
    for pkg in $required_pkgs; do
        if ! opkg list-installed 2>/dev/null | grep -q "^${pkg} "; then
            info "Installing $pkg..."
            opkg install "$pkg" >/dev/null 2>&1 || {
                warn "Failed to install required package: $pkg"; exit 1;
            }
        fi
    done

    optional_pkgs="hysteria kmod-nft-tproxy kmod-nft-socket kmod-nft-nat kmod-tun kmod-inet-diag"
    for pkg in $optional_pkgs; do
        if ! opkg list-installed 2>/dev/null | grep -q "^${pkg} "; then
            info "Installing optional package: $pkg"
            opkg install "$pkg" >/dev/null 2>&1 || warn "Optional package not installed: $pkg"
        fi
    done

    [ -f /etc/uci-defaults/luci-passwall2 ] && sh /etc/uci-defaults/luci-passwall2 >/dev/null 2>&1
}

ensure_base_config() {
    [ -s /etc/config/passwall2 ] && return 0
    if [ -f /usr/share/passwall2/0_default_config ]; then
        cp /usr/share/passwall2/0_default_config /etc/config/passwall2
    else
        touch /etc/config/passwall2
    fi
}

configure_passwall2() {
    info "Applying Passwall2 presets..."
    ensure_base_config

    # Clean demo sections if present
    for s in examplenode rulenode; do
        uci -q get "passwall2.${s}" >/dev/null 2>&1 && uci -q delete "passwall2.${s}"
    done

    # Core shunt rules
    uci set passwall2.Russia_Block=shunt_rules
    uci set passwall2.Russia_Block.remarks='Russia_Block'
    uci set passwall2.Russia_Block.network='tcp,udp'
    uci set passwall2.Russia_Block.domain_list='geosite:ru-blocked'
    uci set passwall2.Russia_Block.ip_list='geoip:ru-blocked'

    uci set passwall2.pw2_custom=shunt_rules
    uci set passwall2.pw2_custom.remarks='Custom VPN Domains'
    uci set passwall2.pw2_custom.network='tcp,udp'
    uci set passwall2.pw2_custom.domain_list=''

    # Balancer template for VLESS nodes
    uci set passwall2.bal_vless=nodes
    uci set passwall2.bal_vless.remarks='BAL-VLESS'
    uci set passwall2.bal_vless.type='Xray'
    uci set passwall2.bal_vless.protocol='_balancing'
    uci set passwall2.bal_vless.node_add_mode='batch'
    uci set passwall2.bal_vless.node_group='default'
    uci set passwall2.bal_vless.balancingStrategy='leastPing'
    uci set passwall2.bal_vless.useCustomProbeUrl='1'
    uci set passwall2.bal_vless.probeUrl='https://www.gstatic.com/generate_204'
    uci set passwall2.bal_vless.probeInterval='1m'

    # Balancer template for Hysteria2 nodes
    uci set passwall2.bal_hy2=nodes
    uci set passwall2.bal_hy2.remarks='BAL-HY2'
    uci set passwall2.bal_hy2.type='Xray'
    uci set passwall2.bal_hy2.protocol='_balancing'
    uci set passwall2.bal_hy2.node_add_mode='batch'
    uci set passwall2.bal_hy2.node_group='default'
    uci set passwall2.bal_hy2.balancingStrategy='leastPing'
    uci set passwall2.bal_hy2.useCustomProbeUrl='1'
    uci set passwall2.bal_hy2.probeUrl='https://www.gstatic.com/generate_204'
    uci set passwall2.bal_hy2.probeInterval='1m'

    # Main shunt entrypoint
    uci set passwall2.pw2_shunt=nodes
    uci set passwall2.pw2_shunt.remarks='Main-Shunt'
    uci set passwall2.pw2_shunt.type='Xray'
    uci set passwall2.pw2_shunt.protocol='_shunt'
    uci set passwall2.pw2_shunt.default_node='_direct'
    uci set passwall2.pw2_shunt.domainStrategy='IPOnDemand'
    uci set passwall2.pw2_shunt.domainMatcher='hybrid'
    uci set passwall2.pw2_shunt.write_ipset_direct='0'
    uci set passwall2.pw2_shunt.enable_geoview_ip='0'
    uci set passwall2.pw2_shunt.Russia_Block='bal_vless'
    uci set passwall2.pw2_shunt.pw2_custom='bal_hy2'

    # Global
    uci set passwall2.@global[0].enabled='1'
    uci set passwall2.@global[0].node='pw2_shunt'

    # Geodata source
    uci set passwall2.@global_rules[0].auto_update='0'
    uci set passwall2.@global_rules[0].geosite_update='1'
    uci set passwall2.@global_rules[0].geoip_update='1'
    uci set passwall2.@global_rules[0].geosite_url='https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release/geosite.dat'
    uci set passwall2.@global_rules[0].geoip_url='https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release/geoip.dat'

    uci commit passwall2
}

download_geodata() {
    info "Downloading geodata..."
    geodir="/usr/share/v2ray"
    mkdir -p "$geodir"

    curl -fsSL --max-time 90 "https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release/geosite.dat" -o "$geodir/geosite.dat" || {
        warn "Failed to download geosite.dat"; exit 1;
    }
    curl -fsSL --max-time 90 "https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release/geoip.dat" -o "$geodir/geoip.dat" || {
        warn "Failed to download geoip.dat"; exit 1;
    }

    [ -s "$geodir/geosite.dat" ] || { warn "geosite.dat is empty"; exit 1; }
    [ -s "$geodir/geoip.dat" ] || { warn "geoip.dat is empty"; exit 1; }
}

finish() {
    info "Enabling service..."
    /etc/init.d/passwall2 enable >/dev/null 2>&1 || true
    /etc/init.d/passwall2 restart >/dev/null 2>&1 || true

    echo ""
    header "=========================================="
    header "        INSTALLATION COMPLETE"
    header "=========================================="
    echo ""
    echo "Done presets:"
    echo "  - Main Node: Main-Shunt"
    echo "  - Russia_Block -> BAL-VLESS"
    echo "  - Custom VPN Domains -> BAL-HY2"
    echo "  - Default -> Direct"
    echo ""
    echo "Your next step in LuCI:"
    echo "  1) Services -> PassWall2 -> Node Subscribe / Node List"
    echo "  2) Add your VLESS and Hysteria2 node URLs"
    echo "  3) Save & Apply, then restart if needed:"
    echo "     /etc/init.d/passwall2 restart"
    echo ""
}

echo ""
header "=========================================="
header "  Passwall2 Clean Install"
header "=========================================="
echo ""
printf "Continue? [y/N]: "
read yn
case "$yn" in
    [yY]|[yY][eE][sS]) ;;
    *) echo "Cancelled"; exit 0 ;;
esac

check_system
add_feed
install_packages
configure_passwall2
download_geodata
finish

