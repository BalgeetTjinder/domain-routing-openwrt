#!/bin/sh

# PassWall2 Full Uninstall for OpenWrt
# Removes: service, packages, configs, runtime, geodata, feeds, LuCI cache
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
header "  PassWall2 Full Uninstall"
header "=========================================="
echo ""
echo "This will remove:"
echo "  - PassWall2 service and all related packages"
echo "  - UCI configs and runtime data"
echo "  - Geodata files and auto-update cron"
echo "  - PassWall2 opkg feeds"
echo "  - LuCI cache"
echo ""
echo "Will NOT remove: dnsmasq-full, kernel modules, getdomains-* scripts"
echo ""
printf "Continue? [y/N]: "
read CONFIRM
case ${CONFIRM} in
    [yY]|[yY][eE][sS]) ;;
    *) echo "Cancelled"; exit 0 ;;
esac
echo ""

# ── Stop and disable service ──────────────────────────────────────────

info "Stopping PassWall2 service..."
/etc/init.d/passwall2 stop 2>/dev/null || true
/etc/init.d/passwall2 disable 2>/dev/null || true

# ── Remove packages ───────────────────────────────────────────────────

info "Removing packages..."
for pkg in \
    luci-app-passwall2 \
    luci-i18n-passwall2-zh-cn \
    luci-i18n-passwall2-en \
    xray-core \
    hysteria \
    geoview \
    v2ray-geoip \
    v2ray-geosite; do
    opkg remove "${pkg}" 2>/dev/null || true
done

# ── Remove UCI configuration ─────────────────────────────────────────

info "Removing PassWall2 configuration..."
rm -f /etc/config/passwall2
rm -f /etc/config/passwall2_show

# ── Remove runtime and temporary files ────────────────────────────────

info "Removing runtime data..."
rm -rf /tmp/passwall2* 2>/dev/null || true
rm -rf /tmp/passwall_* 2>/dev/null || true
rm -rf /tmp/etc/passwall2 2>/dev/null || true
rm -rf /var/etc/passwall2 2>/dev/null || true
rm -rf /var/log/passwall2* 2>/dev/null || true
rm -rf /tmp/dnsmasq.passwall2 2>/dev/null || true
rm -f /tmp/passwall2_dns_* 2>/dev/null || true

# ── Remove geodata ────────────────────────────────────────────────────

info "Removing geodata files..."
rm -f /usr/share/v2ray/geosite.dat 2>/dev/null || true
rm -f /usr/share/v2ray/geoip.dat 2>/dev/null || true
rmdir /usr/share/v2ray 2>/dev/null || true

# ── Remove geodata auto-update script and cron ────────────────────────

info "Removing geodata cron job..."
rm -f /usr/bin/passwall2-update-geodata 2>/dev/null || true
if [ -f /etc/crontabs/root ]; then
    sed -i '/passwall2-update-geodata/d' /etc/crontabs/root
    /etc/init.d/cron restart 2>/dev/null || true
fi

# ── Remove PassWall2 opkg feeds ───────────────────────────────────────

info "Removing PassWall2 feeds from customfeeds.conf..."
if [ -f /etc/opkg/customfeeds.conf ]; then
    sed -i '/passwall/d' /etc/opkg/customfeeds.conf
fi

# ── Remove init script and shared files ───────────────────────────────

info "Removing PassWall2 shared files..."
rm -f /etc/init.d/passwall2 2>/dev/null || true
rm -rf /usr/share/passwall2 2>/dev/null || true

# Lua modules and LuCI views
rm -rf /usr/lib/lua/luci/passwall2 2>/dev/null || true
rm -f /usr/lib/lua/luci/controller/passwall2.lua 2>/dev/null || true
rm -f /usr/lib/lua/luci/model/cbi/passwall2.lua 2>/dev/null || true
rm -rf /usr/lib/lua/luci/model/cbi/passwall2 2>/dev/null || true
rm -rf /usr/lib/lua/luci/view/passwall2 2>/dev/null || true
rm -rf /www/luci-static/resources/view/passwall2 2>/dev/null || true

# ── Clear LuCI cache ─────────────────────────────────────────────────

info "Clearing LuCI cache..."
rm -f /tmp/luci-indexcache /tmp/luci-indexcache.* 2>/dev/null || true
rm -rf /tmp/luci-modulecache 2>/dev/null || true
/etc/init.d/rpcd restart 2>/dev/null || true
/etc/init.d/uhttpd restart 2>/dev/null || true

# ── Restart DNS ───────────────────────────────────────────────────────

info "Restarting dnsmasq..."
/etc/init.d/dnsmasq restart 2>/dev/null || true

# ── Done ──────────────────────────────────────────────────────────────

echo ""
header "=========================================="
header "  PassWall2 fully uninstalled"
header "=========================================="
echo ""
echo "NOT removed (safe to keep):"
echo "  - dnsmasq-full"
echo "  - kmod-nft-socket, kmod-nft-tproxy"
echo ""
echo "To also remove dnsmasq-full:"
echo "  opkg remove dnsmasq-full && opkg install dnsmasq"
echo ""
