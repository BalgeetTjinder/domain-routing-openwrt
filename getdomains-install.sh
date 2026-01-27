#!/bin/sh

# Domain Routing OpenWrt - Sing-box (VLESS Reality + Hysteria 2)
# Форк: github.com/BalgeetTjinder/domain-routing-openwrt
# Оригинал: github.com/itdoginfo/domain-routing-openwrt

set -e

# Цвета
GREEN='\033[32;1m'
RED='\033[31;1m'
BLUE='\033[34;1m'
NC='\033[0m'

print_green() { printf "${GREEN}$1${NC}\n"; }
print_red() { printf "${RED}$1${NC}\n"; }
print_blue() { printf "${BLUE}$1${NC}\n"; }

# Проверка системы
check_system() {
    MODEL=$(cat /tmp/sysinfo/model 2>/dev/null || echo "Unknown")
    . /etc/os-release
    
    print_blue "Роутер: $MODEL"
    print_blue "Версия: $OPENWRT_RELEASE"
    
    VERSION_ID=$(echo $VERSION | awk -F. '{print $1}')
    
    if [ "$VERSION_ID" -lt 23 ]; then
        print_red "Скрипт поддерживает только OpenWrt 23.05+ и 24.10+"
        exit 1
    fi
}

# Проверка репозитория
check_repo() {
    print_green "Проверка доступности репозитория OpenWrt..."
    opkg update 2>&1 | grep -q "Failed to download" && {
        print_red "opkg недоступен. Проверь интернет или дату."
        print_red "Команда для синхронизации времени: ntpd -p ptbtime1.ptb.de"
        exit 1
    }
}

# Установка пакетов
install_packages() {
    print_green "Установка пакетов..."
    
    for pkg in curl nano; do
        if ! opkg list-installed | grep -q "^$pkg "; then
            print_green "Устанавливаю $pkg..."
            opkg install $pkg
        else
            print_green "$pkg уже установлен"
        fi
    done
    
    # dnsmasq-full
    if opkg list-installed | grep -q dnsmasq-full; then
        print_green "dnsmasq-full уже установлен"
    else
        print_green "Устанавливаю dnsmasq-full..."
        cd /tmp/ && opkg download dnsmasq-full
        opkg remove dnsmasq && opkg install dnsmasq-full --cache /tmp/
        [ -f /etc/config/dhcp-opkg ] && cp /etc/config/dhcp /etc/config/dhcp-old && mv /etc/config/dhcp-opkg /etc/config/dhcp
    fi
    
    # sing-box
    if opkg list-installed | grep -q sing-box; then
        print_green "sing-box уже установлен"
    else
        AVAILABLE_SPACE=$(df / | awk 'NR>1 { print $4 }')
        if [ "$AVAILABLE_SPACE" -gt 2000 ]; then
            print_green "Устанавливаю sing-box..."
            opkg install sing-box
        else
            print_red "Недостаточно места для sing-box!"
            exit 1
        fi
    fi
    
    # Включаем sing-box
    if grep -q "option enabled '0'" /etc/config/sing-box 2>/dev/null; then
        sed -i "s/option enabled '0'/option enabled '1'/" /etc/config/sing-box
    fi
    if grep -q "option user 'sing-box'" /etc/config/sing-box 2>/dev/null; then
        sed -i "s/option user 'sing-box'/option user 'root'/" /etc/config/sing-box
    fi
}

# Настройка Sing-box
configure_singbox() {
    print_green "=== Настройка Sing-box (VLESS Reality + Hysteria 2) ==="
    echo ""
    echo "Данные нужно взять из S-UI панели на VPS"
    echo ""
    
    # VPS IP
    read -r -p "IP адрес VPS сервера: " VPS_IP
    
    echo ""
    print_blue "--- VLESS Reality ---"
    read -r -p "UUID клиента: " VLESS_UUID
    read -r -p "Public Key: " VLESS_PUBLIC_KEY
    read -r -p "Short ID: " VLESS_SHORT_ID
    read -r -p "SNI (по умолчанию www.microsoft.com): " VLESS_SNI
    VLESS_SNI=${VLESS_SNI:-www.microsoft.com}
    read -r -p "Порт VLESS (по умолчанию 443): " VLESS_PORT
    VLESS_PORT=${VLESS_PORT:-443}
    
    echo ""
    print_blue "--- Hysteria 2 ---"
    read -r -p "Пароль: " HY2_PASSWORD
    read -r -p "Домен (SNI): " HY2_SNI
    read -r -p "Порт Hysteria2 (по умолчанию 8443): " HY2_PORT
    HY2_PORT=${HY2_PORT:-8443}
    read -r -p "Скорость Upload Mbps (по умолчанию 100): " HY2_UP
    HY2_UP=${HY2_UP:-100}
    read -r -p "Скорость Download Mbps (по умолчанию 100): " HY2_DOWN
    HY2_DOWN=${HY2_DOWN:-100}
    
    print_green "Создаю конфиг /etc/sing-box/config.json..."
    
    cat << EOF > /etc/sing-box/config.json
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "dns": {
    "servers": [
      {
        "tag": "google",
        "address": "tls://8.8.8.8"
      },
      {
        "tag": "local",
        "address": "local",
        "detour": "direct"
      }
    ],
    "rules": [
      {
        "outbound": "any",
        "server": "local"
      }
    ],
    "strategy": "ipv4_only"
  },
  "inbounds": [
    {
      "type": "tun",
      "tag": "tun-in",
      "interface_name": "tun0",
      "address": ["172.16.250.1/30"],
      "mtu": 1400,
      "auto_route": false,
      "strict_route": false,
      "sniff": true,
      "sniff_override_destination": true
    }
  ],
  "outbounds": [
    {
      "type": "urltest",
      "tag": "auto",
      "outbounds": ["vless-reality", "hysteria2"],
      "url": "https://www.gstatic.com/generate_204",
      "interval": "1m",
      "tolerance": 50
    },
    {
      "type": "vless",
      "tag": "vless-reality",
      "server": "${VPS_IP}",
      "server_port": ${VLESS_PORT},
      "uuid": "${VLESS_UUID}",
      "flow": "xtls-rprx-vision",
      "tls": {
        "enabled": true,
        "server_name": "${VLESS_SNI}",
        "utls": {
          "enabled": true,
          "fingerprint": "chrome"
        },
        "reality": {
          "enabled": true,
          "public_key": "${VLESS_PUBLIC_KEY}",
          "short_id": "${VLESS_SHORT_ID}"
        }
      }
    },
    {
      "type": "hysteria2",
      "tag": "hysteria2",
      "server": "${VPS_IP}",
      "server_port": ${HY2_PORT},
      "password": "${HY2_PASSWORD}",
      "tls": {
        "enabled": true,
        "server_name": "${HY2_SNI}",
        "alpn": ["h3"]
      },
      "up_mbps": ${HY2_UP},
      "down_mbps": ${HY2_DOWN}
    },
    {
      "type": "direct",
      "tag": "direct"
    },
    {
      "type": "block",
      "tag": "block"
    },
    {
      "type": "dns",
      "tag": "dns-out"
    }
  ],
  "route": {
    "rules": [
      {
        "protocol": "dns",
        "outbound": "dns-out"
      },
      {
        "ip_is_private": true,
        "outbound": "direct"
      }
    ],
    "auto_detect_interface": true,
    "final": "auto"
  }
}
EOF

    print_green "Конфиг создан!"
}

# Настройка маршрутизации
configure_routing() {
    print_green "Настройка маршрутизации..."
    
    # Таблица маршрутизации
    grep -q "99 vpn" /etc/iproute2/rt_tables || echo '99 vpn' >> /etc/iproute2/rt_tables
    
    # Правило для маркированного трафика
    if ! uci show network 2>/dev/null | grep -q mark0x1; then
        print_green "Создаю правило mark0x1..."
        uci add network rule
        uci set network.@rule[-1].name='mark0x1'
        uci set network.@rule[-1].mark='0x1'
        uci set network.@rule[-1].priority='100'
        uci set network.@rule[-1].lookup='vpn'
        uci commit network
    else
        print_green "Правило mark0x1 уже существует"
    fi
    
    # Hotplug скрипт для маршрута
    print_green "Создаю hotplug скрипт..."
    cat << 'EOF' > /etc/hotplug.d/iface/30-vpnroute
#!/bin/sh

sleep 10
ip route add table vpn default dev tun0
EOF
    
    cp /etc/hotplug.d/iface/30-vpnroute /etc/hotplug.d/net/30-vpnroute
}

# Настройка firewall
configure_firewall() {
    print_green "Настройка firewall..."
    
    # Зона для sing-box
    if uci show firewall 2>/dev/null | grep -q "@zone.*name='singbox'"; then
        print_green "Зона singbox уже существует"
    else
        print_green "Создаю зону singbox..."
        uci add firewall zone
        uci set firewall.@zone[-1].name='singbox'
        uci set firewall.@zone[-1].device='tun0'
        uci set firewall.@zone[-1].forward='ACCEPT'
        uci set firewall.@zone[-1].output='ACCEPT'
        uci set firewall.@zone[-1].input='ACCEPT'
        uci set firewall.@zone[-1].masq='1'
        uci set firewall.@zone[-1].mtu_fix='1'
        uci set firewall.@zone[-1].family='ipv4'
        uci commit firewall
    fi
    
    # Forwarding
    if uci show firewall 2>/dev/null | grep -q "@forwarding.*name='singbox-lan'"; then
        print_green "Forwarding уже настроен"
    else
        print_green "Настраиваю forwarding..."
        uci add firewall forwarding
        uci set firewall.@forwarding[-1].name='singbox-lan'
        uci set firewall.@forwarding[-1].dest='singbox'
        uci set firewall.@forwarding[-1].src='lan'
        uci set firewall.@forwarding[-1].family='ipv4'
        uci commit firewall
    fi
    
    # ipset для доменов
    if uci show firewall 2>/dev/null | grep -q "@ipset.*name='vpn_domains'"; then
        print_green "ipset vpn_domains уже существует"
    else
        print_green "Создаю ipset vpn_domains..."
        uci add firewall ipset
        uci set firewall.@ipset[-1].name='vpn_domains'
        uci set firewall.@ipset[-1].match='dst_net'
        uci commit firewall
    fi
    
    # Правило маркировки
    if uci show firewall 2>/dev/null | grep -q "@rule.*name='mark_domains'"; then
        print_green "Правило mark_domains уже существует"
    else
        print_green "Создаю правило mark_domains..."
        uci add firewall rule
        uci set firewall.@rule[-1].name='mark_domains'
        uci set firewall.@rule[-1].src='lan'
        uci set firewall.@rule[-1].dest='*'
        uci set firewall.@rule[-1].proto='all'
        uci set firewall.@rule[-1].ipset='vpn_domains'
        uci set firewall.@rule[-1].set_mark='0x1'
        uci set firewall.@rule[-1].target='MARK'
        uci set firewall.@rule[-1].family='ipv4'
        uci commit firewall
    fi
}

# Настройка dnsmasq confdir
configure_dnsmasq() {
    print_green "Настройка dnsmasq..."
    
    VERSION_ID=$(. /etc/os-release && echo $VERSION | awk -F. '{print $1}')
    
    if [ "$VERSION_ID" -ge 24 ]; then
        if uci get dhcp.@dnsmasq[0].confdir 2>/dev/null | grep -q /tmp/dnsmasq.d; then
            print_green "confdir уже настроен"
        else
            print_green "Устанавливаю confdir..."
            uci set dhcp.@dnsmasq[0].confdir='/tmp/dnsmasq.d'
            uci commit dhcp
        fi
    fi
}

# DNS resolver (Stubby)
configure_dns_resolver() {
    echo ""
    echo "Установить Stubby для шифрования DNS?"
    echo "Рекомендуется если провайдер подменяет DNS-запросы"
    echo ""
    echo "1) Да"
    echo "2) Нет (пропустить)"
    
    while true; do
        read -r -p "Выбор [1-2]: " DNS_CHOICE
        case $DNS_CHOICE in
            1)
                if opkg list-installed | grep -q stubby; then
                    print_green "Stubby уже установлен"
                else
                    print_green "Устанавливаю Stubby..."
                    opkg install stubby
                    
                    uci set dhcp.@dnsmasq[0].noresolv='1'
                    uci -q delete dhcp.@dnsmasq[0].server
                    uci add_list dhcp.@dnsmasq[0].server='127.0.0.1#5453'
                    uci commit dhcp
                fi
                break
                ;;
            2)
                print_green "Пропускаю установку Stubby"
                break
                ;;
            *)
                echo "Выбери 1 или 2"
                ;;
        esac
    done
}

# Скрипт загрузки доменов
create_getdomains_script() {
    echo ""
    echo "Выбери список доменов:"
    echo "1) Россия (внутри страны) - обход блокировок"
    echo "2) Россия (снаружи) - доступ к российским ресурсам"
    echo "3) Украина"
    
    while true; do
        read -r -p "Выбор [1-3]: " COUNTRY_CHOICE
        case $COUNTRY_CHOICE in
            1)
                DOMAINS_URL="https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Russia/inside-dnsmasq-nfset.lst"
                break
                ;;
            2)
                DOMAINS_URL="https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Russia/outside-dnsmasq-nfset.lst"
                break
                ;;
            3)
                DOMAINS_URL="https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Ukraine/inside-dnsmasq-nfset.lst"
                break
                ;;
            *)
                echo "Выбери 1, 2 или 3"
                ;;
        esac
    done
    
    print_green "Создаю скрипт /etc/init.d/getdomains..."
    
    cat << EOF > /etc/init.d/getdomains
#!/bin/sh /etc/rc.common

START=99

start () {
    DOMAINS=${DOMAINS_URL}

    count=0
    while true; do
        if curl -m 3 github.com >/dev/null 2>&1; then
            curl -f \$DOMAINS --output /tmp/dnsmasq.d/domains.lst
            break
        else
            echo "GitHub недоступен. Проверка интернета [\$count]"
            count=\$((count+1))
            sleep 5
        fi
    done

    if dnsmasq --conf-file=/tmp/dnsmasq.d/domains.lst --test 2>&1 | grep -q "syntax check OK"; then
        /etc/init.d/dnsmasq restart
    fi
}
EOF

    chmod +x /etc/init.d/getdomains
    /etc/init.d/getdomains enable
    
    # Cron для автообновления
    if crontab -l 2>/dev/null | grep -q getdomains; then
        print_green "Cron уже настроен"
    else
        print_green "Добавляю в cron..."
        (crontab -l 2>/dev/null; echo "0 */8 * * * /etc/init.d/getdomains start") | crontab -
        /etc/init.d/cron restart
    fi
}

# Финальный запуск
final_start() {
    print_green "Перезапуск сервисов..."
    
    /etc/init.d/firewall restart
    /etc/init.d/network restart
    /etc/init.d/sing-box restart
    /etc/init.d/getdomains start
    
    sleep 5
    
    # Проверка
    if ip link show tun0 >/dev/null 2>&1; then
        print_green "✓ Интерфейс tun0 поднят"
    else
        print_red "✗ Интерфейс tun0 не поднят. Проверь логи: logread | grep sing-box"
    fi
    
    echo ""
    print_green "=========================================="
    print_green "        УСТАНОВКА ЗАВЕРШЕНА!"
    print_green "=========================================="
    echo ""
    echo "Проверка: попробуй открыть заблокированный сайт"
    echo ""
    echo "Полезные команды:"
    echo "  logread | grep sing-box   - логи sing-box"
    echo "  service sing-box restart  - перезапуск"
    echo "  /etc/init.d/getdomains start - обновить домены"
    echo ""
}

# === MAIN ===

echo ""
print_blue "=========================================="
print_blue "  Domain Routing OpenWrt"
print_blue "  Sing-box: VLESS Reality + Hysteria 2"
print_blue "=========================================="
echo ""

print_red "Внимание: все изменения нельзя откатить автоматически!"
echo ""
read -r -p "Продолжить? [y/N]: " CONFIRM
case $CONFIRM in
    [yY]|[yY][eE][sS])
        ;;
    *)
        echo "Отменено"
        exit 0
        ;;
esac

check_system
check_repo
install_packages
configure_singbox
configure_routing
configure_firewall
configure_dnsmasq
configure_dns_resolver
create_getdomains_script
final_start
