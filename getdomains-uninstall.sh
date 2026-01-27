#!/bin/sh

# Domain Routing Uninstall Script
# https://github.com/BalgeetTjinder/domain-routing-openwrt

GREEN='\033[32;1m'
RED='\033[31;1m'
BLUE='\033[34;1m'
NC='\033[0m'

info() { printf "${GREEN}[*] %s${NC}\n" "$1"; }
warn() { printf "${RED}[!] %s${NC}\n" "$1"; }
header() { printf "${BLUE}%s${NC}\n" "$1"; }

echo ""
header "=========================================="
header "  Domain Routing Uninstall"
header "=========================================="
echo ""

echo "This will remove:"
echo "  - sing-box configuration"
echo "  - Firewall rules (zone, forwarding, ipset)"
echo "  - Routing rules"
echo "  - getdomains script and cron job"
echo "  - Domain lists"
echo ""
echo "Packages (sing-box, dnsmasq-full, stubby) will NOT be removed."
echo ""
printf "Continue? [y/N]: "
read CONFIRM

case $CONFIRM in
    [yY]|[yY][eE][sS]) ;;
    *) echo "Cancelled"; exit 0 ;;
esac

echo ""

# Stop services
info "Stopping sing-box..."
/etc/init.d/sing-box stop 2>/dev/null || true
/etc/init.d/sing-box disable 2>/dev/null || true

# Remove scripts
info "Removing scripts..."
/etc/init.d/getdomains disable 2>/dev/null || true
rm -f /etc/init.d/getdomains
rm -f /etc/hotplug.d/iface/30-vpnroute
rm -f /etc/hotplug.d/net/30-vpnroute

# Remove from crontab
info "Removing from crontab..."
if [ -f /etc/crontabs/root ]; then
    sed -i '/getdomains/d' /etc/crontabs/root
    /etc/init.d/cron restart 2>/dev/null || true
fi

# Remove domain list
info "Removing domain lists..."
rm -f /tmp/dnsmasq.d/domains.lst

# Clean firewall - singbox zone
info "Cleaning firewall..."

zone_id=$(uci show firewall 2>/dev/null | grep -E "@zone.*name='singbox'" | head -n1 | sed "s/.*\[\([0-9]*\)\].*/\1/")
if [ -n "$zone_id" ]; then
    uci delete firewall.@zone[$zone_id] 2>/dev/null || true
fi

# Clean firewall - forwarding
fwd_id=$(uci show firewall 2>/dev/null | grep -E "@forwarding.*name='singbox-lan'" | head -n1 | sed "s/.*\[\([0-9]*\)\].*/\1/")
if [ -n "$fwd_id" ]; then
    uci delete firewall.@forwarding[$fwd_id] 2>/dev/null || true
fi

# Clean firewall - ipset vpn_domains
ipset_id=$(uci show firewall 2>/dev/null | grep -E "@ipset.*name='vpn_domains'" | head -n1 | sed "s/.*\[\([0-9]*\)\].*/\1/")
if [ -n "$ipset_id" ]; then
    uci delete firewall.@ipset[$ipset_id] 2>/dev/null || true
fi

# Clean firewall - rule mark_domains
rule_id=$(uci show firewall 2>/dev/null | grep -E "@rule.*name='mark_domains'" | head -n1 | sed "s/.*\[\([0-9]*\)\].*/\1/")
if [ -n "$rule_id" ]; then
    uci delete firewall.@rule[$rule_id] 2>/dev/null || true
fi

uci commit firewall 2>/dev/null || true

# Clean network
info "Cleaning network rules..."

# Remove from rt_tables
if [ -f /etc/iproute2/rt_tables ]; then
    sed -i '/99 vpn/d' /etc/iproute2/rt_tables
fi

# Remove network rule
rule_id=$(uci show network 2>/dev/null | grep -E "@rule.*name='mark0x1'" | head -n1 | sed "s/.*\[\([0-9]*\)\].*/\1/")
if [ -n "$rule_id" ]; then
    uci delete network.@rule[$rule_id] 2>/dev/null || true
fi

uci commit network 2>/dev/null || true

# Remove sing-box config (optional - keep it)
# rm -rf /etc/sing-box/config.json

# Restart services
info "Restarting services..."
/etc/init.d/firewall restart 2>/dev/null || true
/etc/init.d/network restart 2>/dev/null || true
/etc/init.d/dnsmasq restart 2>/dev/null || true

echo ""
header "=========================================="
header "  Uninstall complete"
header "=========================================="
echo ""
echo "The following was NOT removed:"
echo "  - Packages (sing-box, dnsmasq-full, stubby)"
echo "  - sing-box config (/etc/sing-box/config.json)"
echo ""
echo "To fully remove packages:"
echo "  opkg remove sing-box stubby"
echo ""
