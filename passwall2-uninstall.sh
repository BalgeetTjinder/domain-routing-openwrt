#!/bin/sh

# Passwall2 full uninstall and cleanup

GREEN='\033[32;1m'
RED='\033[31;1m'
BLUE='\033[34;1m'
NC='\033[0m'

info()   { printf "${GREEN}[*] %s${NC}\n" "$1"; }
warn()   { printf "${RED}[!] %s${NC}\n" "$1"; }
header() { printf "${BLUE}%s${NC}\n" "$1"; }

echo ""
header "=========================================="
header "  Passwall2 Full Uninstall"
header "=========================================="
echo ""
echo "This will remove Passwall2 packages, config, geodata, runtime files and feeds."
echo ""
printf "Continue? [y/N]: "
read yn
case "$yn" in
    [yY]|[yY][eE][sS]) ;;
    *) echo "Cancelled"; exit 0 ;;
esac
echo ""

info "Stopping service..."
/etc/init.d/passwall2 stop >/dev/null 2>&1 || true
/etc/init.d/passwall2 disable >/dev/null 2>&1 || true
kill "$(pgrep -f '/tmp/etc/passwall2/bin/')" >/dev/null 2>&1 || true

info "Flushing nftables tables..."
nft delete table inet passwall2 >/dev/null 2>&1 || true
nft delete table ip passwall2 >/dev/null 2>&1 || true

info "Removing packages..."
remove_pkgs="luci-app-passwall2 xray-core hysteria geoview v2ray-geoip v2ray-geosite"
for pkg in $remove_pkgs; do
    if opkg list-installed 2>/dev/null | grep -q "^${pkg} "; then
        opkg remove "$pkg" >/dev/null 2>&1 || warn "Failed removing $pkg"
    fi
done

info "Removing configuration and data..."
rm -f /etc/config/passwall2 >/dev/null 2>&1 || true
rm -f /usr/share/v2ray/geosite.dat >/dev/null 2>&1 || true
rm -f /usr/share/v2ray/geoip.dat >/dev/null 2>&1 || true
rm -rf /tmp/etc/passwall2 >/dev/null 2>&1 || true
rm -f /tmp/log/passwall2.log >/dev/null 2>&1 || true

info "Removing package feed lines..."
if [ -f /etc/opkg/customfeeds.conf ]; then
    sed -i '/openwrt-passwall-build\/releases\/packages-/d' /etc/opkg/customfeeds.conf
fi

info "Clearing LuCI caches..."
rm -f /tmp/luci-indexcache /tmp/luci-indexcache.* >/dev/null 2>&1 || true
rm -rf /tmp/luci-modulecache >/dev/null 2>&1 || true
/etc/init.d/rpcd restart >/dev/null 2>&1 || true
/etc/init.d/uhttpd restart >/dev/null 2>&1 || true

echo ""
header "=========================================="
header "      UNINSTALL COMPLETE"
header "=========================================="
echo ""
echo "Reinstall command:"
echo "  sh <(wget -O - https://raw.githubusercontent.com/BalgeetTjinder/domain-routing-openwrt/master/passwall2-install.sh)"
echo ""

