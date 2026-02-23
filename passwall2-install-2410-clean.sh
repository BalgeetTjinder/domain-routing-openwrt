#!/bin/sh
#
# Максимально чистая установка Passwall2 + Hysteria(2)
# Только OpenWrt 24.10.x
#

RELEASE_SERIES="24.10"
PW_BASE="https://downloads.sourceforge.net/project/openwrt-passwall-build/releases/packages-${RELEASE_SERIES}"

if [ -f /etc/os-release ]; then
    . /etc/os-release
fi

case "${VERSION_ID:-}" in
    24.10.*) ;;
    *)
        echo "Ошибка: скрипт только для OpenWrt 24.10.x. У вас: ${VERSION_ID:-unknown}"
        exit 1
        ;;
esac

ARCH=$(sed -n 's|.*packages/\([^/]*\)/packages.*|\1|p' /etc/opkg/distfeeds.conf 2>/dev/null | head -1)
if [ -z "$ARCH" ]; then
    echo "Ошибка: не удалось определить архитектуру"
    exit 1
fi

echo "OpenWrt: $VERSION_ID"
echo "ARCH: $ARCH"

# Минимально необходимые опции для SourceForge (редиректы, IPv4, без проверки подписи)
sed -i '/wget_options/d' /etc/opkg.conf 2>/dev/null
sed -i '/check_signature/d' /etc/opkg.conf 2>/dev/null
echo "option wget_options '-L -4'" >> /etc/opkg.conf
echo "option check_signature 0" >> /etc/opkg.conf

FEED_FILE="/etc/opkg/customfeeds.conf"
touch "$FEED_FILE"
sed -i '/passwall_packages/d' "$FEED_FILE" 2>/dev/null
sed -i '/passwall2/d' "$FEED_FILE" 2>/dev/null
echo "src/gz passwall_packages ${PW_BASE}/${ARCH}/passwall_packages" >> "$FEED_FILE"
echo "src/gz passwall2 ${PW_BASE}/${ARCH}/passwall2" >> "$FEED_FILE"

opkg update

if ! opkg list 2>/dev/null | grep -q "^luci-app-passwall2 "; then
    echo "Ошибка: luci-app-passwall2 не найден в списке пакетов после opkg update."
    echo "Проверь доступ к SourceForge:"
    echo "  wget -4 -qO- \"${PW_BASE}/${ARCH}/passwall2/Packages.gz\" >/dev/null && echo OK || echo FAIL"
    exit 1
fi

opkg install luci-app-passwall2 xray-core kmod-nft-socket kmod-nft-tproxy hysteria || \
opkg install luci-app-passwall2 xray-core kmod-nft-socket kmod-nft-tproxy hysteria2

echo ""
echo "Готово. LuCI → Services → PassWall2"

