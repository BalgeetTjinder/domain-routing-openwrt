#!/bin/sh

# Passwall2 Domain Routing — Uninstall
# https://github.com/BalgeetTjinder/domain-routing-openwrt

GREEN='\033[32;1m'
BLUE='\033[34;1m'
NC='\033[0m'

info()   { printf "${GREEN}[*] %s${NC}\n" "$1"; }
header() { printf "${BLUE}%s${NC}\n" "$1"; }

echo ""
header "=========================================="
header "  Passwall2 — Uninstall"
header "=========================================="
echo ""
echo "This will remove Passwall2, all config, geodata, and package feeds."
echo ""
printf "Continue? [y/N]: "
read CONFIRM
case $CONFIRM in
    [yY]|[yY][eE][sS]) ;;
    *) echo "Cancelled"; exit 0 ;;
esac
echo ""

# 1. Stop service
info "Stopping Passwall2..."
/etc/init.d/passwall2 stop 2>/dev/null || true
/etc/init.d/passwall2 disable 2>/dev/null || true

# 2. Flush nftables rules
info "Flushing nftables rules..."
nft delete table inet passwall2 2>/dev/null || true
nft delete table ip passwall2 2>/dev/null || true

# 3. Remove packages
info "Removing packages..."
for pkg in luci-app-passwall2 xray-core geoview v2ray-geoip v2ray-geosite hysteria; do
    if opkg list-installed 2>/dev/null | grep -q "^${pkg} "; then
        opkg remove "$pkg" >/dev/null 2>&1 && info "  Removed: $pkg"
    fi
done

# 4. Remove config, geodata, runtime files
info "Removing config and data..."
rm -f /etc/config/passwall2 2>/dev/null || true
rm -f /usr/share/v2ray/geosite.dat /usr/share/v2ray/geoip.dat 2>/dev/null || true
rm -rf /tmp/etc/passwall2 2>/dev/null || true

# 5. Remove package feeds
info "Removing package feeds..."
[ -f /etc/opkg/customfeeds.conf ] && \
    sed -i '/openwrt-passwall-build\/releases\/packages-/d' /etc/opkg/customfeeds.conf

# 6. Clean up legacy files from previous script versions
rm -f /etc/passwall2-prestart.sh 2>/dev/null || true
sed -i '/passwall2-prestart/d' /etc/rc.local 2>/dev/null || true

# 7. Clear LuCI caches
info "Restarting LuCI..."
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
