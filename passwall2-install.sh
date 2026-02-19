#!/bin/sh

# Passwall2 + Hysteria — установка
# OpenWrt 23.05+ / 24.10+

ARCH=$(sed -n 's|.*packages/\([^/]*\)/packages.*|\1|p' /etc/opkg/distfeeds.conf 2>/dev/null | head -1)

if [ -z "$ARCH" ]; then
    echo "Ошибка: не удалось определить архитектуру"
    exit 1
fi

echo "Архитектура: $ARCH"

# Feeds
FEED_FILE="/etc/opkg/customfeeds.conf"
grep -q "passwall_packages" "$FEED_FILE" 2>/dev/null || \
    echo "src/gz passwall_packages https://raw.githubusercontent.com/xiaorouji/openwrt-passwall-packages/main/passwall_packages/${ARCH}/" >> "$FEED_FILE"
grep -q "passwall2 " "$FEED_FILE" 2>/dev/null || \
    echo "src/gz passwall2 https://raw.githubusercontent.com/xiaorouji/openwrt-passwall2/main/passwall2/${ARCH}/" >> "$FEED_FILE"

echo "Обновление пакетов..."
opkg update

echo "Установка dnsmasq-full..."
if ! opkg list-installed | grep -q "^dnsmasq-full "; then
    cd /tmp
    opkg download dnsmasq-full
    opkg remove dnsmasq
    opkg install dnsmasq-full --cache /tmp/
    [ -f /etc/config/dhcp-opkg ] && mv /etc/config/dhcp-opkg /etc/config/dhcp
fi

echo "Установка пакетов..."
opkg install kmod-nft-socket kmod-nft-tproxy xray-core hysteria luci-app-passwall2

echo ""
echo "Готово. Открой LuCI → Services → PassWall2"
