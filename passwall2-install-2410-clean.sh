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

CONF="/etc/opkg.d/99-passwall2-clean.conf"
cat > "$CONF" <<EOF
option wget_options '-L -4'
option check_signature 0
src/gz passwall_packages ${PW_BASE}/${ARCH}/passwall_packages
src/gz passwall2 ${PW_BASE}/${ARCH}/passwall2
EOF

opkg update

opkg install luci-app-passwall2 xray-core kmod-nft-socket kmod-nft-tproxy hysteria || \
opkg install luci-app-passwall2 xray-core kmod-nft-socket kmod-nft-tproxy hysteria2

echo ""
echo "Готово. LuCI → Services → PassWall2"

