#!/bin/sh

# Passwall2 + Hysteria — удаление
# OpenWrt 23.05+ / 24.10+

echo "Остановка Passwall2..."
/etc/init.d/passwall2 stop 2>/dev/null
/etc/init.d/passwall2 disable 2>/dev/null

echo "Удаление пакетов..."
opkg remove luci-app-passwall2 xray-core hysteria kmod-nft-tproxy kmod-nft-socket

echo "Удаление feeds..."
sed -i '/passwall_packages/d' /etc/opkg/customfeeds.conf 2>/dev/null
sed -i '/passwall2/d' /etc/opkg/customfeeds.conf 2>/dev/null

echo "Очистка LuCI..."
rm -f /tmp/luci-indexcache
/etc/init.d/uhttpd restart 2>/dev/null

echo ""
echo "Готово."
