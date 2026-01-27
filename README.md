# Domain Routing OpenWrt

Точечная маршрутизация по доменам на OpenWrt через **Sing-box** (VLESS Reality + Hysteria 2).

Только заблокированные сайты идут через VPN, остальной трафик — напрямую.

## Требования

- OpenWrt **23.05+** или **24.10+**
- VPS с настроенным [S-UI](https://github.com/alireza0/s-ui) (VLESS Reality + Hysteria 2)
- Доступ к роутеру по SSH

## Установка

Подключись к роутеру по SSH и выполни:

```bash
sh <(wget -O - https://raw.githubusercontent.com/BalgeetTjinder/domain-routing-openwrt/master/getdomains-install.sh)
```

Скрипт спросит:
- IP адрес VPS
- Данные VLESS Reality (UUID, Public Key, Short ID)
- Данные Hysteria 2 (пароль, домен)

## Что устанавливается

- `sing-box` — VPN клиент
- `dnsmasq-full` — DNS с поддержкой nfset
- `stubby` — шифрование DNS (опционально)

## Как работает

```
Запрос к youtube.com
        ↓
dnsmasq резолвит → IP добавляется в vpn_domains
        ↓
Firewall маркирует пакеты к этим IP
        ↓
Маркированные пакеты → tun0 → Sing-box → VPS
```

## Автопереключение протоколов

Sing-box автоматически выбирает лучший протокол:
- Проверяет latency каждую минуту
- Переключается если один из протоколов "проседает"

## Полезные команды

```bash
# Логи sing-box
logread | grep sing-box

# Перезапуск
service sing-box restart

# Обновить список доменов
/etc/init.d/getdomains start

# Проверка конфигурации
sh <(wget -O - https://raw.githubusercontent.com/BalgeetTjinder/domain-routing-openwrt/master/getdomains-check.sh)
```

## Удаление

```bash
sh <(wget -O - https://raw.githubusercontent.com/BalgeetTjinder/domain-routing-openwrt/master/getdomains-uninstall.sh)
```

## Благодарности

Основано на [itdoginfo/domain-routing-openwrt](https://github.com/itdoginfo/domain-routing-openwrt)
