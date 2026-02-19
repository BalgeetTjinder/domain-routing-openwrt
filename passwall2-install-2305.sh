#!/bin/sh
#
# Чистая установка Passwall2 + Hysteria
# Только OpenWrt 23.05.x
# https://github.com/BalgeetTjinder/domain-routing-openwrt
#

RELEASE="23.05"
PW_BASE="https://downloads.sourceforge.net/project/openwrt-passwall-build/releases/packages-${RELEASE}"

# Проверка версии: только 23.05
if [ -f /etc/openwrt_release ]; then
    . /etc/openwrt_release
else
    echo "Ошибка: не найден /etc/openwrt_release"
    exit 1
fi

case "$DISTRIB_RELEASE" in
    23.05.*) ;;
    *)
        echo "Ошибка: скрипт только для OpenWrt 23.05.x. У вас: $DISTRIB_RELEASE"
        exit 1
        ;;
esac

# Архитектура из distfeeds (как в официальном OpenWrt)
ARCH=$(sed -n 's|.*packages/\([^/]*\)/packages.*|\1|p' /etc/opkg/distfeeds.conf 2>/dev/null | head -1)
if [ -z "$ARCH" ]; then
    ARCH="${DISTRIB_ARCH}"
fi
if [ -z "$ARCH" ]; then
    echo "Ошибка: не удалось определить архитектуру"
    exit 1
fi

echo "OpenWrt $DISTRIB_RELEASE, архитектура: $ARCH"
echo ""

# Принудительно отключить проверку подписи (фиды Passwall не подписаны ключом OpenWrt)
sed -i '/check_signature/d' /etc/opkg.conf 2>/dev/null
echo 'option check_signature 0' >> /etc/opkg.conf

# Опции opkg для SourceForge (редиректы, IPv4)
if [ -d /etc/opkg.d ]; then
    echo "option wget_options '-L -4'" > /etc/opkg.d/99-passwall-feeds.conf 2>/dev/null || true
fi

# Один feed для 23.05
FEED_FILE="/etc/opkg/customfeeds.conf"
touch "$FEED_FILE"
sed -i '/passwall_packages/d' "$FEED_FILE" 2>/dev/null
sed -i '/passwall2/d'   "$FEED_FILE" 2>/dev/null

echo "src/gz passwall_packages ${PW_BASE}/${ARCH}/passwall_packages" >> "$FEED_FILE"
echo "src/gz passwall2         ${PW_BASE}/${ARCH}/passwall2"         >> "$FEED_FILE"

# Удалить старые списки Passwall, чтобы opkg заново скачал их без проверки подписи
rm -f /var/opkg-lists/passwall_packages /var/opkg-lists/passwall2 2>/dev/null

echo "Обновление списка пакетов..."
if ! opkg update 2>&1 | tee /tmp/opkg-update.log; then
    echo "Ошибка: opkg update не удался. См. /tmp/opkg-update.log"
    exit 1
fi

if ! opkg list 2>/dev/null | grep -q "^luci-app-passwall2 "; then
    echo "Ошибка: пакет luci-app-passwall2 не найден в списке."
    echo ""
    echo "Отладка: check_signature в opkg.conf:"
    grep -n check_signature /etc/opkg.conf 2>/dev/null || true
    echo "Списки Passwall в /var/opkg-lists:"
    ls -la /var/opkg-lists/passwall* 2>/dev/null || echo "(нет файлов)"
    echo "Пакеты с passwall в opkg list:"
    opkg list 2>/dev/null | grep -i passwall || echo "(ничего)"
    echo ""
    echo "Проверка доступа: wget -4 -q -O- \"${PW_BASE}/${ARCH}/passwall2/Packages.gz\" | zcat | grep -A1 'Package: luci-app-passwall2'"
    exit 1
fi

# dnsmasq-full (нужен для nftset/tproxy)
if ! opkg list-installed 2>/dev/null | grep -q "^dnsmasq-full "; then
    echo "Установка dnsmasq-full..."
    cd /tmp
    opkg download dnsmasq-full 2>/dev/null || true
    opkg remove dnsmasq 2>/dev/null || true
    opkg install dnsmasq-full --cache /tmp/ || opkg install dnsmasq-full
    [ -f /etc/config/dhcp-opkg ] && mv /etc/config/dhcp-opkg /etc/config/dhcp
    cd - >/dev/null
fi
if ! opkg list-installed 2>/dev/null | grep -q "^dnsmasq-full "; then
    echo "Ошибка: не удалось установить dnsmasq-full"
    exit 1
fi

echo "Установка Passwall2, xray-core, hysteria и зависимостей..."
opkg install kmod-nft-socket kmod-nft-tproxy xray-core hysteria luci-app-passwall2

echo ""
echo "Готово. LuCI → Services → PassWall2"
echo "Проверка подписи opkg отключена в /etc/opkg.conf (option check_signature 0). При желании верни 1 после установки."
echo ""
