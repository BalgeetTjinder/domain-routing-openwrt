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

# Check OpenWrt version
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

# Add Passwall2 opkg feed
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

# Install required packages
install_packages() {
    info "Installing packages..."

    # Replace dnsmasq with dnsmasq-full (needed for Passwall2 DNS)
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

    if ! opkg list-installed 2>/dev/null | grep -q "^luci-app-passwall2 "; then
        error "luci-app-passwall2 installation failed"
        error "Check internet connection and that the feed is reachable"
        exit 1
    fi

    if ! opkg list-installed 2>/dev/null | grep -q "^xray-core "; then
        error "xray-core installation failed"
        exit 1
    fi

    # Run uci-defaults immediately so @global[0], @global_rules[0], @global_forwarding[0]
    # sections exist before we configure them (normally they run only on next boot)
    if [ -f /etc/uci-defaults/luci-passwall2 ]; then
        info "Initializing Passwall2 config..."
        sh /etc/uci-defaults/luci-passwall2 >/dev/null 2>&1 || true
    fi

    info "All packages installed"
}

# Configure Passwall2 structure via UCI
# Nodes are created as placeholders — fill in server details via LuCI (Services -> PassWall2 -> Node List)
configure_passwall2() {
    info "Configuring Passwall2 routing structure..."

    # Initialize config from default template if missing
    if [ ! -s /etc/config/passwall2 ]; then
        if [ -f /usr/share/passwall2/0_default_config ]; then
            cp /usr/share/passwall2/0_default_config /etc/config/passwall2
        else
            touch /etc/config/passwall2
        fi
    fi

    # --- Node: VLESS XHTTP Reality (placeholder — enter server details in LuCI) ---
    # Both nodes use Xray core (type='Xray'); no separate hysteria binary needed.
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

    # --- Node: Hysteria2 via Xray core (placeholder — enter server details in LuCI) ---
    # Requires Xray >= 26.1.13 (available in Passwall2 feed for OpenWrt 23/24)
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

    # --- Shunt Rule: Russia blocked domains ---
    # Recreate explicitly to ensure it exists regardless of previous Passwall2 state
    uci set passwall2.Russia_Block=shunt_rules
    uci set passwall2.Russia_Block.remarks='Russia_Block'
    uci set passwall2.Russia_Block.network='tcp,udp'
    uci set passwall2.Russia_Block.domain_list='geosite:ru-blocked'
    uci set passwall2.Russia_Block.ip_list='geoip:ru-blocked'

    # --- Shunt Rule: Custom VPN Domains (managed via LuCI Services -> VPN Domains) ---
    uci set passwall2.pw2_custom=shunt_rules
    uci set passwall2.pw2_custom.remarks='Custom VPN Domains'
    uci set passwall2.pw2_custom.network='tcp,udp'
    uci set passwall2.pw2_custom.domain_list=''

    # --- Node: Main Shunt ---
    # Routing: Russia blocked (geosite:ru-blocked) → VLESS, custom domains → VLESS, rest → direct
    # Switch to Hysteria2 anytime via Passwall2 UI without reinstalling
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

    # --- Global Settings ---
    uci set passwall2.@global[0].enabled='1'
    uci set passwall2.@global[0].node='pw2_shunt'
    uci set passwall2.@global[0].remote_dns='1.1.1.1'
    uci set passwall2.@global[0].remote_dns_protocol='tcp'
    uci set passwall2.@global[0].localhost_proxy='1'
    uci set passwall2.@global[0].client_proxy='1'
    uci set passwall2.@global[0].log_node='1'
    uci set passwall2.@global[0].loglevel='error'

    # Use runetfreedom geosite/geoip (daily-updated Russia blocked domains)
    uci set passwall2.@global_rules[0].auto_update='1'
    uci set passwall2.@global_rules[0].geosite_update='1'
    uci set passwall2.@global_rules[0].geoip_update='1'
    uci set passwall2.@global_rules[0].geosite_url='https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download/geosite.dat'
    uci set passwall2.@global_rules[0].geoip_url='https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download/geoip.dat'

    # Use nftables (fw4) — works on both 23.x and 24.x
    uci set passwall2.@global_forwarding[0].prefer_nft='1'
    uci set passwall2.@global_forwarding[0].tcp_redir_ports='1:65535'
    uci set passwall2.@global_forwarding[0].udp_redir_ports='1:65535'
    uci set passwall2.@global_forwarding[0].tcp_no_redir_ports='disable'
    uci set passwall2.@global_forwarding[0].udp_no_redir_ports='disable'

    uci commit passwall2 2>/dev/null || true
    info "Passwall2 routing structure configured"
}

# Download Russia-specific geosite/geoip from runetfreedom
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
        error "Failed to download geosite.dat — will retry on next auto-update"
    fi

    if curl -sL --max-time 60 "$GEOIP_URL" -o "$GEO_DIR/geoip.dat" 2>/dev/null; then
        info "geoip.dat downloaded"
    else
        error "Failed to download geoip.dat — will retry on next auto-update"
    fi
}

# Install LuCI page for managing custom VPN domains
configure_vpndomains_luci() {
    info "Installing LuCI VPN Domains helper..."

    if [ ! -d /usr/lib/lua/luci ]; then
        info "LuCI not found, skipping"
        return 0
    fi

    # UCI config for custom domains
    if [ ! -f /etc/config/vpndomains ]; then
        cat > /etc/config/vpndomains << 'EOF'
config vpndomains 'general'
    option enabled '1'

# Add domains below or via LuCI (Services -> VPN Domains)
config domain
    option name 'example.com'
EOF
    else
        if ! uci -q get vpndomains.general.enabled >/dev/null 2>&1; then
            uci set vpndomains.general.enabled='1'
            uci commit vpndomains 2>/dev/null || true
        fi
    fi

    mkdir -p /usr/lib/lua/luci/controller /usr/lib/lua/luci/model/cbi

    # LuCI controller
    cat > /usr/lib/lua/luci/controller/vpndomains.lua << 'EOF'
module("luci.controller.vpndomains", package.seeall)

function index()
    if not nixio.fs.access("/etc/config/vpndomains") then
        return
    end
    entry(
        {"admin", "services", "vpndomains"},
        cbi("vpndomains"),
        _("VPN Domains"),
        90
    ).dependent = true
end
EOF

    # LuCI CBI model
    # on_commit: writes domain list to passwall2.pw2_custom.domain_list and restarts Passwall2
    cat > /usr/lib/lua/luci/model/cbi/vpndomains.lua << 'EOF'
local sys     = require "luci.sys"
local uci_pw2 = require("luci.model.uci").cursor()

local m = Map("vpndomains", translate("VPN Domains"),
    translate("Domains routed through VPN via Passwall2 shunt rule."))

local s_gen = m:section(NamedSection, "general", "vpndomains", translate("General"))
local o_en  = s_gen:option(Flag, "enabled", translate("Enable"))
o_en.default = o_en.enabled

local s = m:section(TypedSection, "domain", translate("Domains"))
s.addremove = true
s.anonymous = true

local o = s:option(Value, "name", translate("Domain"))
o.datatype    = "host"
o.placeholder = "example.com"

function m.on_commit(map)
    local enabled = map.uci:get("vpndomains", "general", "enabled")

    if not enabled or enabled == "" then
        enabled = "1"
        map.uci:set("vpndomains", "general", "enabled", "1")
        map.uci:commit("vpndomains")
    end

    local domains = {}

    if enabled ~= "0" then
        map.uci:foreach("vpndomains", "domain", function(s)
            local name = s.name
            if name and name ~= "" and name ~= "example.com" then
                table.insert(domains, name)
            end
        end)
    end

    -- Write domain list to Passwall2 shunt rule pw2_custom
    uci_pw2:set("passwall2", "pw2_custom", "domain_list",
        table.concat(domains, "\n"))
    uci_pw2:commit("passwall2")

    -- Restart Passwall2 in background to apply changes
    sys.call("/etc/init.d/passwall2 restart >/dev/null 2>&1 &")
end

return m
EOF

    # Sync existing non-example domains to Passwall2 right now
    ENABLED=$(uci -q get vpndomains.general.enabled 2>/dev/null)
    if [ "$ENABLED" != "0" ]; then
        DOMAIN_LINES=""
        while IFS= read -r line; do
            DOMAIN=$(echo "$line" | grep "\.name=" | sed "s/.*='\(.*\)'/\1/")
            if [ -n "$DOMAIN" ] && [ "$DOMAIN" != "example.com" ]; then
                DOMAIN_LINES="${DOMAIN_LINES}${DOMAIN}
"
            fi
        done << UCIEOF
$(uci show vpndomains 2>/dev/null | grep "\.name=")
UCIEOF

        if [ -n "$DOMAIN_LINES" ]; then
            uci set passwall2.pw2_custom.domain_list="$DOMAIN_LINES"
            uci commit passwall2 2>/dev/null || true
        fi
    fi

    rm -f /tmp/luci-indexcache* 2>/dev/null || true
    /etc/init.d/rpcd restart 2>/dev/null || true
    /etc/init.d/uhttpd restart 2>/dev/null || true

    info "LuCI VPN Domains helper installed (Services -> VPN Domains)"
}

# Start services
start_services() {
    info "Starting Passwall2..."

    /etc/init.d/passwall2 enable 2>/dev/null || true
    /etc/init.d/passwall2 restart 2>/dev/null || true

    sleep 3

    echo ""
    header "=========================================="
    header "        INSTALLATION COMPLETE"
    header "=========================================="
    echo ""
    echo "Next step — enter your VPS server details in LuCI:"
    echo ""
    echo "  1. Open LuCI: Services -> PassWall2 -> Node List"
    echo "  2. Edit node 'VLESS-XHTTP-Reality':"
    echo "       Address, Port, UUID, Public Key, Short ID, SNI, Path"
    echo "  3. Edit node 'Hysteria2':"
    echo "       Address, Port, Password, SNI"
    echo "  4. Go to Global Settings, enable and click Save & Apply"
    echo ""
    echo "Routing is pre-configured:"
    echo "  geosite:ru-blocked  →  VLESS-XHTTP-Reality"
    echo "  Custom VPN Domains  →  VLESS-XHTTP-Reality"
    echo "  Everything else     →  direct"
    echo ""
    echo "To add custom domains: Services -> VPN Domains"
    echo "To switch to Hysteria2: Passwall2 -> Shunt Rules -> change node"
    echo ""
    echo "Useful commands:"
    echo "  logread | grep passwall2        - logs"
    echo "  /etc/init.d/passwall2 restart   - restart"
    echo "  /etc/init.d/passwall2 status    - status"
    echo ""
}

# === MAIN ===

echo ""
header "=========================================="
header "  Passwall2 Domain Routing"
header "  VLESS XHTTP Reality + Hysteria2"
header "=========================================="
echo ""
echo "Installs and configures Passwall2 on your router."
echo "VPN server details are entered after install via LuCI."
echo "Old scripts (getdomains-*) are NOT affected."
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
configure_passwall2
download_geodata
configure_vpndomains_luci
start_services
