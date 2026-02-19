#!/bin/sh

# Passwall2 + Hysteria — установка
# OpenWrt 23.05+ / 24.10+

if [ -f /etc/os-release ]; then
    . /etc/os-release
fi

ARCH=$(sed -n 's|.*packages/\([^/]*\)/packages.*|\1|p' /etc/opkg/distfeeds.conf 2>/dev/null | head -1)

if [ -z "$ARCH" ]; then
    echo "Ошибка: не удалось определить архитектуру"
    exit 1
fi

if [ -n "$VERSION_ID" ]; then
    RELEASE_SERIES=$(echo "$VERSION_ID" | sed -n 's/^\([0-9]\+\.[0-9]\+\).*/\1/p')
fi

case "$RELEASE_SERIES" in
    24.*) CANDIDATES="24.10 23.05" ;;
    23.*) CANDIDATES="23.05 24.10" ;;
    *)    CANDIDATES="24.10 23.05" ;;
esac

echo "Архитектура: $ARCH"
echo "OpenWrt: ${VERSION_ID:-unknown}"

# Feeds
FEED_FILE="/etc/opkg/customfeeds.conf"
touch "$FEED_FILE"
SELECTED=""

for SERIES in $CANDIDATES; do
    PW_BASE="https://downloads.sourceforge.net/project/openwrt-passwall-build/releases/packages-${SERIES}/${ARCH}"
    echo "Проверка passwall feeds для packages-${SERIES}..."

    # Чистим старые/битые записи перед каждой попыткой
    sed -i '/passwall_packages/d' "$FEED_FILE" 2>/dev/null
    sed -i '/passwall2/d' "$FEED_FILE" 2>/dev/null

    echo "src/gz passwall_packages ${PW_BASE}/passwall_packages" >> "$FEED_FILE"
    echo "src/gz passwall2 ${PW_BASE}/passwall2" >> "$FEED_FILE"

    opkg update >/dev/null 2>&1 || true

    if opkg list 2>/dev/null | grep -q "^luci-app-passwall2 -"; then
        SELECTED="$SERIES"
        break
    fi
done

if [ -z "$SELECTED" ]; then
    echo "Ошибка: не удалось подключить passwall feeds ни для 24.10, ни для 23.05."
    echo "Проверь доступ к SourceForge с роутера:"
    echo "  wget -O- https://downloads.sourceforge.net/project/openwrt-passwall-build/releases/packages-24.10/${ARCH}/passwall2/Packages.gz >/dev/null && echo OK || echo FAIL"
    echo "  wget -O- https://downloads.sourceforge.net/project/openwrt-passwall-build/releases/packages-23.05/${ARCH}/passwall2/Packages.gz >/dev/null && echo OK || echo FAIL"
    exit 1
fi

echo "Используется feed: packages-${SELECTED}"
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