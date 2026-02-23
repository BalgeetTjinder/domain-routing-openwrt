#!/bin/sh
#
# Чистая установка Passwall2 + Hysteria
# Только OpenWrt 24.10.x
#

. /etc/openwrt_release 2>/dev/null || { echo "Ошибка: /etc/openwrt_release не найден"; exit 1; }

case "$DISTRIB_RELEASE" in
    24.10.*) ;;
    *) echo "Ошибка: скрипт только для OpenWrt 24.10.x. У вас: $DISTRIB_RELEASE"; exit 1 ;;
esac

RELEASE="${DISTRIB_RELEASE%.*}"
ARCH="$DISTRIB_ARCH"
MIRROR="https://master.dl.sourceforge.net/project/openwrt-passwall-build"

echo "OpenWrt: $DISTRIB_RELEASE"
echo "ARCH: $ARCH"
echo ""

# Убрать мусор от предыдущих попыток (wget_options / check_signature)
sed -i '/wget_options/d' /etc/opkg.conf 2>/dev/null
sed -i '/check_signature/d' /etc/opkg.conf 2>/dev/null

# Публичный ключ Passwall (подпись будет проходить без отключения check_signature)
echo "Добавление ключа Passwall..."
wget -qO /tmp/passwall.pub "${MIRROR}/passwall.pub"
opkg-key add /tmp/passwall.pub
rm -f /tmp/passwall.pub

# Фиды Passwall (master.dl — прямое зеркало без редиректов)
FEED_FILE="/etc/opkg/customfeeds.conf"
touch "$FEED_FILE"
sed -i '/passwall_packages/d' "$FEED_FILE" 2>/dev/null
sed -i '/passwall2/d' "$FEED_FILE" 2>/dev/null
echo "src/gz passwall_packages ${MIRROR}/releases/packages-${RELEASE}/${ARCH}/passwall_packages" >> "$FEED_FILE"
echo "src/gz passwall2 ${MIRROR}/releases/packages-${RELEASE}/${ARCH}/passwall2" >> "$FEED_FILE"

echo ""
echo "opkg update..."
opkg update

echo ""
echo "Установка пакетов..."
opkg install luci-app-passwall2 xray-core kmod-nft-socket kmod-nft-tproxy hysteria

echo ""
echo "Готово. LuCI → Services → PassWall2"
