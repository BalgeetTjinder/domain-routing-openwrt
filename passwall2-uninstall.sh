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
echo "  - Passwall2 service (stop + disable)"
echo "  - All Passwall2 config (nodes, shunt rules, subscriptions)"
echo "  - Passwall2 runtime files (/tmp/etc/passwall2)"
echo "  - Geodata files (/usr/share/v2ray/geosite.dat, geoip.dat)"
echo "  - Package feeds (passwall2 entries in customfeeds.conf)"
echo "  - Prestart hook (/etc/passwall2-prestart.sh + rc.local entry)"
echo "  - LuCI module cache"
echo ""
echo "Packages (luci-app-passwall2, xray-core, etc.) will NOT be removed."
echo ""
printf "Continue? [y/N]: "
read CONFIRM
case $CONFIRM in
    [yY]|[yY][eE][sS]) ;;
    *) echo "Cancelled"; exit 0 ;;
esac
echo ""

# --- 1. Stop service ---
info "Stopping Passwall2..."
/etc/init.d/passwall2 stop 2>/dev/null || true
/etc/init.d/passwall2 disable 2>/dev/null || true
sleep 1

# --- 2. Wipe nftables rules left by Passwall2 ---
info "Flushing Passwall2 nftables rules..."
nft delete table inet passwall2 2>/dev/null || true
nft delete table ip passwall2 2>/dev/null || true

# --- 3. Reset /etc/config/passwall2 to package default ---
info "Resetting Passwall2 config to package default..."
if [ -f /usr/share/passwall2/0_default_config ]; then
    cp /usr/share/passwall2/0_default_config /etc/config/passwall2
else
    rm -f /etc/config/passwall2
    touch /etc/config/passwall2
fi
# Force disabled, no node selected
uci set passwall2.@global[0].enabled='0' 2>/dev/null || true
uci -q delete passwall2.@global[0].node 2>/dev/null || true
uci commit passwall2 2>/dev/null || true

# --- 4. Remove geodata ---
info "Removing geodata files..."
rm -f /usr/share/v2ray/geosite.dat 2>/dev/null || true
rm -f /usr/share/v2ray/geoip.dat 2>/dev/null || true

# --- 5. Remove package feeds ---
info "Removing Passwall2 package feeds..."
if [ -f /etc/opkg/customfeeds.conf ]; then
    sed -i '/openwrt-passwall-build\/releases\/packages-/d' /etc/opkg/customfeeds.conf
fi

# --- 6. Remove prestart hook ---
info "Removing prestart script and rc.local hooks..."
rm -f /etc/passwall2-prestart.sh 2>/dev/null || true
sed -i '/passwall2-prestart/d' /etc/rc.local 2>/dev/null || true
sed -i '/mount -o remount,exec \/tmp/d' /etc/rc.local 2>/dev/null || true

# --- 7. Remove all runtime and temp files ---
info "Removing runtime files..."
rm -rf /tmp/etc/passwall2 2>/dev/null || true
rm -f /tmp/passwall2_*.json 2>/dev/null || true
rm -f /tmp/passwall.pub 2>/dev/null || true

# --- 8. Remove LuCI caches so Passwall2 tabs disappear cleanly ---
info "Clearing LuCI caches..."
rm -f /usr/lib/lua/luci/controller/vpndomains.lua 2>/dev/null || true
rm -f /usr/lib/lua/luci/model/cbi/vpndomains.lua 2>/dev/null || true
rm -f /etc/config/vpndomains 2>/dev/null || true
rm -f /tmp/luci-indexcache 2>/dev/null || true
rm -f /tmp/luci-indexcache.* 2>/dev/null || true
rm -rf /tmp/luci-modulecache 2>/dev/null || true

# --- 9. Restart LuCI ---
info "Restarting LuCI..."
/etc/init.d/rpcd restart 2>/dev/null || true
/etc/init.d/uhttpd restart 2>/dev/null || true

echo ""
header "=========================================="
header "  Uninstall complete — system is clean"
header "=========================================="
echo ""
echo "Packages still installed (remove manually if needed):"
echo "  opkg remove luci-app-passwall2 xray-core geoview v2ray-geoip v2ray-geosite hysteria"
echo ""
echo "Reinstall:"
echo "  sh <(wget -O - https://raw.githubusercontent.com/BalgeetTjinder/domain-routing-openwrt/master/passwall2-install.sh)"
echo ""
