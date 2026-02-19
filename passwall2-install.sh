#!/bin/sh

# PassWall2 Installer for OpenWrt
# Installs packages, runetfreedom geodata, pre-creates shunt rules
# User configures nodes and balancer in LuCI after install
# https://github.com/BalgeetTjinder/domain-routing-openwrt

set -e

GREEN='\033[32;1m'
RED='\033[31;1m'
YELLOW='\033[33;1m'
BLUE='\033[34;1m'
NC='\033[0m'

info()   { printf "${GREEN}[*] %s${NC}\n" "$1"; }
warn()   { printf "${YELLOW}[!] %s${NC}\n" "$1"; }
error()  { printf "${RED}[!] %s${NC}\n" "$1"; }
header() { printf "${BLUE}%s${NC}\n" "$1"; }
die()    { error "$1"; exit 1; }

GEODATA_DIR="/usr/share/v2ray"
RUNETFREEDOM_URL="https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release"
UPDATE_SCRIPT="/usr/bin/passwall2-update-geodata"

# ── Checks ────────────────────────────────────────────────────────────

check_system() {
    [ "$(id -u)" -ne 0 ] && die "Run as root"
    [ ! -f /etc/openwrt_release ] && die "OpenWrt not detected"

    . /etc/openwrt_release

    MODEL=$(cat /tmp/sysinfo/model 2>/dev/null || echo "Unknown")
    header "Router : ${MODEL}"
    header "OpenWrt: ${DISTRIB_RELEASE} (${DISTRIB_ARCH})"

    IS_SNAPSHOT=$(echo "${DISTRIB_RELEASE}" | grep -ci snapshot || true)
    if [ "${IS_SNAPSHOT}" -eq 0 ]; then
        VER_MAJOR=$(echo "${DISTRIB_RELEASE}" | cut -d. -f1)
        VER_MINOR=$(echo "${DISTRIB_RELEASE}" | cut -d. -f2)
        if [ "${VER_MAJOR}" -lt 23 ] || \
           { [ "${VER_MAJOR}" -eq 23 ] && [ "${VER_MINOR}" -lt 5 ]; }; then
            die "OpenWrt 23.05+ required (detected ${DISTRIB_RELEASE})"
        fi
    fi
}

# ── Fix /tmp noexec ───────────────────────────────────────────────────
# PassWall2 copies and runs binaries from /tmp/etc/passwall2/bin/.
# Many OpenWrt builds mount /tmp with noexec, which blocks this.
# We remount now AND install a persistent init.d service (START=10)
# that runs before passwall2 (START=99) on every boot.

fix_tmp_exec() {
    info "Fixing /tmp exec permissions..."
    mount -o remount,exec /tmp 2>/dev/null || true

    cat > /etc/init.d/passwall2-fix-tmp << 'INITEOF'
#!/bin/sh /etc/rc.common
START=10
start() {
    mount -o remount,exec /tmp 2>/dev/null
}
INITEOF
    chmod +x /etc/init.d/passwall2-fix-tmp
    /etc/init.d/passwall2-fix-tmp enable 2>/dev/null || true
    info "/tmp exec: fixed now + persistent on boot"
}

# ── PassWall2 opkg feeds (SourceForge pre-built packages) ────────────

add_feeds() {
    info "Adding PassWall2 package feeds..."

    wget -q -O /tmp/passwall.pub \
        https://master.dl.sourceforge.net/project/openwrt-passwall-build/passwall.pub \
        || die "Cannot download feed signing key"
    opkg-key add /tmp/passwall.pub
    rm -f /tmp/passwall.pub

    . /etc/openwrt_release
    ARCH="${DISTRIB_ARCH}"
    IS_SNAPSHOT=$(echo "${DISTRIB_RELEASE}" | grep -ci snapshot || true)

    FEED_BASE="https://master.dl.sourceforge.net/project/openwrt-passwall-build"
    if [ "${IS_SNAPSHOT}" -gt 0 ]; then
        FEED_PATH="snapshots/packages/${ARCH}"
    else
        RELEASE_VER="${DISTRIB_RELEASE%.*}"
        FEED_PATH="releases/packages-${RELEASE_VER}/${ARCH}"
    fi

    [ ! -f /etc/opkg/customfeeds.conf ] && touch /etc/opkg/customfeeds.conf
    sed -i '/passwall/d' /etc/opkg/customfeeds.conf

    for feed in passwall_packages passwall2; do
        echo "src/gz ${feed} ${FEED_BASE}/${FEED_PATH}/${feed}" \
            >> /etc/opkg/customfeeds.conf
    done

    info "Feeds added (${FEED_PATH})"
}

# ── Install packages ──────────────────────────────────────────────────

install_packages() {
    info "Updating package lists..."
    opkg update || die "opkg update failed — check internet"

    # dnsmasq-full: ipset/nftset support required for domain-based routing
    if ! opkg list-installed 2>/dev/null | grep -q "^dnsmasq-full "; then
        info "Replacing dnsmasq -> dnsmasq-full..."
        cd /tmp
        opkg download dnsmasq-full >/dev/null 2>&1 || true
        opkg remove dnsmasq 2>/dev/null || true
        opkg install dnsmasq-full --cache /tmp/ 2>/dev/null || true
        [ -f /etc/config/dhcp-opkg ] && mv /etc/config/dhcp-opkg /etc/config/dhcp
        cd /
    else
        info "dnsmasq-full already installed"
    fi

    info "Installing luci-app-passwall2..."
    opkg install luci-app-passwall2 || die "Failed to install luci-app-passwall2"

    info "Installing xray-core..."
    opkg install xray-core || warn "xray-core install failed (check storage)"

    info "Installing hysteria..."
    opkg install hysteria || warn "hysteria install failed (optional)"

    opkg install geoview 2>/dev/null || true
    opkg install v2ray-geoip v2ray-geosite 2>/dev/null || true
    opkg install kmod-nft-socket kmod-nft-tproxy 2>/dev/null || true

    info "All packages installed"
}

# ── Download runetfreedom geodata ─────────────────────────────────────

install_geodata() {
    info "Downloading runetfreedom geosite/geoip..."

    mkdir -p "${GEODATA_DIR}"

    wget -q -O "${GEODATA_DIR}/geosite.dat" "${RUNETFREEDOM_URL}/geosite.dat" \
        || die "Failed to download geosite.dat"
    wget -q -O "${GEODATA_DIR}/geoip.dat" "${RUNETFREEDOM_URL}/geoip.dat" \
        || die "Failed to download geoip.dat"

    info "Geodata ready (geosite:ru-blocked, geoip:ru-blocked, ...)"
}

# ── Configure PassWall2 via UCI ───────────────────────────────────────
# Only create shunt RULES (data sections) — they work reliably via UCI.
# Nodes (shunt, balancer) must be created in LuCI to get correct format.

configure_passwall2() {
    info "Configuring PassWall2..."

    /etc/init.d/passwall2 stop 2>/dev/null || true

    # ── Global settings ──
    uci set passwall2.@global[0].enabled='0'
    uci set passwall2.@global[0].remote_dns='1.1.1.1'
    uci set passwall2.@global[0].tcp_proxy_way='tproxy'

    # ── Forwarding: redirect all ports ──
    uci set passwall2.@global_forwarding[0].tcp_no_redir_ports='disable'
    uci set passwall2.@global_forwarding[0].udp_no_redir_ports='disable'
    uci set passwall2.@global_forwarding[0].tcp_redir_ports='1:65535'
    uci set passwall2.@global_forwarding[0].udp_redir_ports='1:65535'

    # ── Geo update URLs (LuCI -> Rule Manage -> Update buttons) ──
    uci set passwall2.@global_rules[0].geosite_url="${RUNETFREEDOM_URL}/geosite.dat" 2>/dev/null || true
    uci set passwall2.@global_rules[0].geoip_url="${RUNETFREEDOM_URL}/geoip.dat" 2>/dev/null || true

    # ── Shunt rule: Russia_Block ──
    uci set passwall2.Russia_Block=shunt_rules
    uci set passwall2.Russia_Block.remarks='Russia_Block'
    uci set passwall2.Russia_Block.network='tcp,udp'
    uci set passwall2.Russia_Block.domain_list='geosite:ru-blocked'
    uci set passwall2.Russia_Block.ip_list='geoip:ru-blocked'

    # ── Shunt rule: Custom_VPN ──
    uci set passwall2.Custom_VPN=shunt_rules
    uci set passwall2.Custom_VPN.remarks='Custom VPN Domains'
    uci set passwall2.Custom_VPN.network='tcp,udp'

    uci commit passwall2
    info "Shunt rules created (Russia_Block + Custom VPN Domains)"
}

# ── Geodata auto-update cron (every 6h) ──────────────────────────────

setup_cron() {
    info "Setting up geodata auto-update..."

    cat > "${UPDATE_SCRIPT}" << 'SCRIPTEOF'
#!/bin/sh
GEODATA_DIR="/usr/share/v2ray"
BASE_URL="https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release"
UPDATED=0
for f in geosite.dat geoip.dat; do
    wget -q -O "${GEODATA_DIR}/${f}.tmp" "${BASE_URL}/${f}" 2>/dev/null && {
        mv "${GEODATA_DIR}/${f}.tmp" "${GEODATA_DIR}/${f}"
        UPDATED=1
        logger -t passwall2-geo "Updated ${f}"
    } || {
        rm -f "${GEODATA_DIR}/${f}.tmp"
        logger -t passwall2-geo "Failed to update ${f}"
    }
done
[ "${UPDATED}" -eq 1 ] && /etc/init.d/passwall2 reload 2>/dev/null
exit 0
SCRIPTEOF

    chmod +x "${UPDATE_SCRIPT}"

    CRON_FILE="/etc/crontabs/root"
    mkdir -p /etc/crontabs
    touch "${CRON_FILE}"
    sed -i '/passwall2-update-geodata/d' "${CRON_FILE}"
    CRON_MIN=$(awk 'BEGIN{srand();printf "%d",rand()*59}')
    echo "${CRON_MIN} */6 * * * ${UPDATE_SCRIPT}" >> "${CRON_FILE}"

    /etc/init.d/cron enable 2>/dev/null || true
    /etc/init.d/cron restart 2>/dev/null || true

    info "Cron: geodata updates every 6 hours from runetfreedom"
}

# ── Finish ────────────────────────────────────────────────────────────

finish() {
    rm -f /tmp/luci-indexcache /tmp/luci-indexcache.* 2>/dev/null || true
    rm -rf /tmp/luci-modulecache 2>/dev/null || true
    /etc/init.d/rpcd restart 2>/dev/null || true
    /etc/init.d/uhttpd restart 2>/dev/null || true

    LAN_IP=$(uci -q get network.lan.ipaddr 2>/dev/null || echo "192.168.1.1")

    echo ""
    header "=========================================="
    header "  PassWall2 installed successfully!"
    header "=========================================="
    echo ""
    echo "NEXT STEPS (in LuCI -> Services -> PassWall2):"
    echo "http://${LAN_IP}/cgi-bin/luci/admin/services/passwall2"
    echo ""
    echo "1. Add your VPN nodes:"
    echo "   Node Subscribe -> Add -> paste URL -> Save & Apply -> Manual subscription"
    echo "   Or: Node List -> Add the node via the link -> paste vless://... or hy2://..."
    echo ""
    echo "2. Create a Shunt node (Node List -> Add):"
    echo "   - Type: Xray"
    echo "   - Protocol: Shunt"
    echo "   - Russia_Block    -> your VPN node (or a balancer)"
    echo "   - Custom VPN      -> your VPN node (or a balancer)"
    echo "   - Default         -> Direct Connection"
    echo "   Save & Apply"
    echo ""
    echo "3. (Optional) Create a Balancer node for auto-failover:"
    echo "   Node List -> Add -> Type: Xray, Protocol: Balancer"
    echo "   -> add VLESS + Hysteria2 nodes, strategy: leastPing"
    echo "   Then use this balancer in step 2 instead of individual nodes"
    echo ""
    echo "4. Basic Settings -> Main Node = your Shunt node -> Enable -> Save & Apply"
    echo ""
    echo "PRE-CONFIGURED by this script:"
    echo "  - Shunt rule 'Russia_Block':      geosite:ru-blocked + geoip:ru-blocked"
    echo "  - Shunt rule 'Custom VPN Domains': add your domains in Rule Manage"
    echo "  - Geodata: runetfreedom (auto-updates every 6h)"
    echo "  - /tmp exec fix (persistent across reboots)"
    echo ""
}

# ── Main ──────────────────────────────────────────────────────────────

echo ""
header "=========================================="
header "  PassWall2 Installer"
header "=========================================="
echo ""

printf "Install PassWall2 with Russia routing presets? [y/N]: "
read CONFIRM
case ${CONFIRM} in
    [yY]|[yY][eE][sS]) ;;
    *) echo "Cancelled"; exit 0 ;;
esac
echo ""

check_system
fix_tmp_exec
add_feeds
install_packages
install_geodata
configure_passwall2
setup_cron
finish
