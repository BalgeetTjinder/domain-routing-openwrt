#!/bin/sh

# Passwall2 Domain Routing - Uninstall Script
# https://github.com/BalgeetTjinder/domain-routing-openwrt

GREEN='\033[32;1m'
RED='\033[31;1m'
BLUE='\033[34;1m'
NC='\033[0m'

info()   { printf "${GREEN}[*] %s${NC}\n" "$1"; }
warn()   { printf "${RED}[!] %s${NC}\n" "$1"; }
header() { printf "${BLUE}%s${NC}\n" "$1"; }

echo ""
header "=========================================="
header "  Passwall2 Domain Routing - Uninstall"
header "=========================================="
echo ""
echo "This will remove:"
echo "  - Passwall2 nodes (VLESS, Hysteria2, Shunt)"
echo "  - Passwall2 shunt rules added by this script"
echo "  - Passwall2 global configuration"
echo ""
echo "The following will NOT be removed:"
echo "  - luci-app-passwall2 package"
echo "  - xray-core, geoview, v2ray-geosite/geoip packages"
echo "  - dnsmasq-full"
echo ""
printf "Continue? [y/N]: "
read CONFIRM

case $CONFIRM in
    [yY]|[yY][eE][sS]) ;;
    *) echo "Cancelled"; exit 0 ;;
esac

echo ""

# Stop Passwall2
info "Stopping Passwall2..."
/etc/init.d/passwall2 stop 2>/dev/null || true
/etc/init.d/passwall2 disable 2>/dev/null || true

# Remove nodes added by this script
info "Removing Passwall2 nodes..."
for section in pw2_vless pw2_hy2 pw2_shunt; do
    if uci -q get passwall2."$section" >/dev/null 2>&1; then
        uci delete passwall2."$section" 2>/dev/null || true
        info "  Removed node: $section"
    fi
done

# Remove shunt rules added by this script
info "Removing shunt rules..."
for rule in pw2_custom Russia_Block; do
    if uci -q get passwall2."$rule" >/dev/null 2>&1; then
        uci delete passwall2."$rule" 2>/dev/null || true
        info "  Removed shunt rule: $rule"
    fi
done

# Reset global settings
info "Resetting Passwall2 global settings..."
uci set passwall2.@global[0].enabled='0' 2>/dev/null || true
uci -q delete passwall2.@global[0].node 2>/dev/null || true

# Reset geosite/geoip URLs to default (Loyalsoldier)
uci set passwall2.@global_rules[0].auto_update='0' 2>/dev/null || true
uci set passwall2.@global_rules[0].geosite_url='https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat' 2>/dev/null || true
uci set passwall2.@global_rules[0].geoip_url='https://github.com/Loyalsoldier/geoip/releases/latest/download/geoip.dat' 2>/dev/null || true

uci commit passwall2 2>/dev/null || true

# Remove LuCI VPN Domains helper (installed by older version of this script)
rm -f /usr/lib/lua/luci/controller/vpndomains.lua 2>/dev/null || true
rm -f /usr/lib/lua/luci/model/cbi/vpndomains.lua 2>/dev/null || true
rm -f /etc/config/vpndomains 2>/dev/null || true

# Clear LuCI caches
rm -f /tmp/luci-indexcache /tmp/luci-indexcache.* 2>/dev/null || true
rm -rf /tmp/luci-modulecache 2>/dev/null || true

# Restart LuCI
/etc/init.d/rpcd restart 2>/dev/null || true
/etc/init.d/uhttpd restart 2>/dev/null || true

echo ""
header "=========================================="
header "  Uninstall complete"
header "=========================================="
echo ""
echo "Passwall2 is stopped and deconfigured."
echo ""
echo "To fully remove packages:"
echo "  opkg remove luci-app-passwall2 xray-core geoview v2ray-geoip v2ray-geosite"
echo ""
echo "To reinstall:"
echo "  sh <(wget -O - https://raw.githubusercontent.com/BalgeetTjinder/domain-routing-openwrt/master/passwall2-install.sh)"
echo ""
