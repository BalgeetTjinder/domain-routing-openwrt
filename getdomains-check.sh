#!/bin/sh

# Domain Routing Check Script
# https://github.com/BalgeetTjinder/domain-routing-openwrt

GREEN='\033[32;1m'
RED='\033[31;1m'
BLUE='\033[34;1m'
NC='\033[0m'

ok() { printf "${GREEN}[OK] %s${NC}\n" "$1"; }
fail() { printf "${RED}[FAIL] %s${NC}\n" "$1"; }
info() { printf "${BLUE}[INFO] %s${NC}\n" "$1"; }

echo ""
info "=========================================="
info "  Domain Routing Check"
info "=========================================="
echo ""

# System info
MODEL=$(cat /tmp/sysinfo/model 2>/dev/null || echo "Unknown")
if [ -f /etc/os-release ]; then
    . /etc/os-release
fi

info "Router: $MODEL"
info "Version: $VERSION"
info "Date: $(date)"
echo ""

# Check packages
info "Checking packages..."

if opkg list-installed 2>/dev/null | grep -q "^curl "; then
    ok "curl installed"
else
    fail "curl not installed"
fi

if opkg list-installed 2>/dev/null | grep -q "^dnsmasq-full "; then
    ok "dnsmasq-full installed"
else
    fail "dnsmasq-full not installed"
fi

if opkg list-installed 2>/dev/null | grep -q "^sing-box "; then
    ok "sing-box installed"
else
    fail "sing-box not installed"
fi

if opkg list-installed 2>/dev/null | grep -q "^stubby "; then
    ok "stubby installed (DNS encryption)"
fi

echo ""

# Check services
info "Checking services..."

if service dnsmasq status 2>/dev/null | grep -q 'running'; then
    ok "dnsmasq is running"
else
    fail "dnsmasq is not running"
fi

if service sing-box status 2>/dev/null | grep -q 'running'; then
    ok "sing-box is running"
else
    fail "sing-box is not running. Check: logread | grep sing-box"
fi

if opkg list-installed 2>/dev/null | grep -q "^stubby "; then
    if service stubby status 2>/dev/null | grep -q 'running'; then
        ok "stubby is running"
    else
        fail "stubby is not running"
    fi
fi

echo ""

# Check sing-box config
info "Checking sing-box configuration..."

if [ -f /etc/sing-box/config.json ]; then
    ok "config.json exists"
    
    if sing-box check -c /etc/sing-box/config.json 2>/dev/null; then
        ok "config.json is valid"
    else
        fail "config.json has errors"
        echo "Run: sing-box check -c /etc/sing-box/config.json"
    fi
else
    fail "config.json not found"
fi

echo ""

# Check tun interface
info "Checking tun0 interface..."

if ip link show tun0 >/dev/null 2>&1; then
    ok "tun0 interface exists"
else
    fail "tun0 interface not found"
fi

echo ""

# Check routing table
info "Checking routing..."

if grep -q "99 vpn" /etc/iproute2/rt_tables 2>/dev/null; then
    ok "VPN routing table defined"
else
    fail "VPN routing table not defined in /etc/iproute2/rt_tables"
fi

if ip route show table vpn 2>/dev/null | grep -q "default dev tun0"; then
    ok "Default route via tun0 in vpn table"
else
    fail "No default route in vpn table. Try: ip route add table vpn default dev tun0"
fi

if uci show network 2>/dev/null | grep -q "name='mark0x1'"; then
    ok "Network rule mark0x1 exists"
else
    fail "Network rule mark0x1 not found"
fi

echo ""

# Check firewall
info "Checking firewall..."

if uci show firewall 2>/dev/null | grep -q "name='singbox'"; then
    ok "Firewall zone singbox exists"
else
    fail "Firewall zone singbox not found"
fi

if uci show firewall 2>/dev/null | grep -q "name='singbox-lan'"; then
    ok "Firewall forwarding singbox-lan exists"
else
    fail "Firewall forwarding singbox-lan not found"
fi

if uci show firewall 2>/dev/null | grep -q "name='vpn_domains'"; then
    ok "Firewall ipset vpn_domains exists"
else
    fail "Firewall ipset vpn_domains not found"
fi

if uci show firewall 2>/dev/null | grep -q "name='mark_domains'"; then
    ok "Firewall rule mark_domains exists"
else
    fail "Firewall rule mark_domains not found"
fi

echo ""

# Check domains list
info "Checking domain list..."

DOMAINS_LST="/etc/dnsmasq.d/domains.lst"
[ -f "$DOMAINS_LST" ] || DOMAINS_LST="/tmp/dnsmasq.d/domains.lst"
if [ -f "$DOMAINS_LST" ]; then
    LINES=$(wc -l < "$DOMAINS_LST")
    ok "domains.lst exists ($LINES entries)"
else
    fail "domains.lst not found. Run: /etc/init.d/getdomains start"
fi

echo ""

# Check getdomains script
info "Checking getdomains script..."

if [ -f /etc/init.d/getdomains ]; then
    ok "getdomains script exists"
else
    fail "getdomains script not found"
fi

if grep -q "getdomains" /etc/crontabs/root 2>/dev/null; then
    ok "getdomains in crontab"
else
    fail "getdomains not in crontab"
fi

echo ""

# Check VPN connectivity
info "Checking VPN connectivity..."

IP_LOCAL=$(curl -s --max-time 5 ifconfig.me 2>/dev/null)
IP_VPN=$(curl -s --max-time 5 --interface tun0 ifconfig.me 2>/dev/null)

if [ -n "$IP_LOCAL" ]; then
    info "Your IP: $IP_LOCAL"
else
    fail "Cannot get external IP"
fi

if [ -n "$IP_VPN" ]; then
    if [ "$IP_LOCAL" != "$IP_VPN" ]; then
        ok "VPN IP: $IP_VPN (different from local)"
    else
        fail "VPN IP same as local IP - routing may not work"
    fi
else
    fail "Cannot connect through tun0"
fi

echo ""

# Check nfset
info "Checking nfset..."

# Force resolve some domains
nslookup youtube.com 127.0.0.1 >/dev/null 2>&1
nslookup instagram.com 127.0.0.1 >/dev/null 2>&1

VPN_IPS=$(nft list ruleset 2>/dev/null | grep -A 20 "set vpn_domains" | grep -c -E '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}')

if [ "$VPN_IPS" -ge 1 ] 2>/dev/null; then
    ok "IPs added to vpn_domains set ($VPN_IPS IPs)"
else
    fail "No IPs in vpn_domains set. Check dnsmasq config"
fi

echo ""
info "=========================================="
info "  Check complete"
info "=========================================="
echo ""
echo "If everything is OK, try opening a blocked website."
echo ""
echo "Useful commands:"
echo "  logread | grep sing-box        - view logs"
echo "  service sing-box restart       - restart sing-box"
echo "  /etc/init.d/getdomains start   - update domains"
echo "  cat /etc/sing-box/config.json  - view config"
echo ""
