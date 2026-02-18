#!/bin/sh

# Passwall2 Domain Routing — Uninstall Script
# https://github.com/BalgeetTjinder/domain-routing-openwrt

GREEN='\033[32;1m'
BLUE='\033[34;1m'
NC='\033[0m'

info()   { printf "${GREEN}[*] %s${NC}\n" "$1"; }
header() { printf "${BLUE}%s${NC}\n" "$1"; }

echo ""
header "=========================================="
header "  Passwall2 Domain Routing — Uninstall"
header "=========================================="
echo ""
echo "This will completely remove Passwall2:"
echo "  - Packages (luci-app-passwall2, xray-core, geoview, hysteria, ...)"
echo "  - All config, geodata, runtime files, package feeds, startup hooks"
echo ""
printf "Continue? [y/N]: "
read CONFIRM
case $CONFIRM in
    [yY]|[yY][eE][sS]) ;;
    *) echo "Cancelled"; exit 0 ;;
esac
echo ""

# 1. Stop service and kill lingering processes
info "Stopping Passwall2..."
/etc/init.d/passwall2 stop 2>/dev/null || true
/etc/init.d/passwall2 disable 2>/dev/null || true
sleep 1
kill $(pgrep -f '/tmp/etc/passwall2/bin/') 2>/dev/null || true

# 2. Flush nftables rules
info "Flushing nftables rules..."
nft delete table inet passwall2 2>/dev/null || true
nft delete table ip passwall2 2>/dev/null || true

# 3. Remove packages
info "Removing packages..."
REMOVE_PKGS="luci-app-passwall2 xray-core geoview v2ray-geoip v2ray-geosite hysteria"
for pkg in $REMOVE_PKGS; do
    if opkg list-installed 2>/dev/null | grep -q "^${pkg} "; then
        opkg remove "$pkg" >/dev/null 2>&1 && info "  Removed: $pkg"
    fi
done

# 4. Remove config and geodata
info "Removing config and geodata..."
rm -f /etc/config/passwall2 2>/dev/null || true
rm -f /usr/share/v2ray/geosite.dat /usr/share/v2ray/geoip.dat 2>/dev/null || true

# 5. Remove package feeds
info "Removing package feeds..."
[ -f /etc/opkg/customfeeds.conf ] && \
    sed -i '/openwrt-passwall-build\/releases\/packages-/d' /etc/opkg/customfeeds.conf

# 6. Remove prestart hook and rc.local entries
info "Removing startup hooks..."
rm -f /etc/passwall2-prestart.sh 2>/dev/null || true
sed -i '/passwall2-prestart/d' /etc/rc.local 2>/dev/null || true
sed -i '/mount -o remount,exec \/tmp/d' /etc/rc.local 2>/dev/null || true

# 7. Remove all runtime/temp files
info "Removing runtime files..."
rm -rf /tmp/etc/passwall2 2>/dev/null || true
rm -f /tmp/passwall.pub 2>/dev/null || true

# 8. Clear LuCI caches
info "Clearing LuCI caches..."
rm -f /usr/lib/lua/luci/controller/vpndomains.lua 2>/dev/null || true
rm -f /usr/lib/lua/luci/model/cbi/vpndomains.lua 2>/dev/null || true
rm -f /etc/config/vpndomains 2>/dev/null || true
rm -f /tmp/luci-indexcache /tmp/luci-indexcache.* 2>/dev/null || true
rm -rf /tmp/luci-modulecache 2>/dev/null || true
/etc/init.d/rpcd restart 2>/dev/null || true
/etc/init.d/uhttpd restart 2>/dev/null || true

echo ""
header "=========================================="
header "  Uninstall complete"
header "=========================================="
echo ""
echo "Reinstall:"
echo "  sh <(wget -O - https://raw.githubusercontent.com/BalgeetTjinder/domain-routing-openwrt/master/passwall2-install.sh)"
echo ""
