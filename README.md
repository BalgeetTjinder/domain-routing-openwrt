# Domain Routing OpenWrt

Точечная маршрутизация по доменам на OpenWrt. Только заблокированные сайты идут через VPN, остальной трафик — напрямую.

Два варианта установки:

| | Passwall2 (новый) | Sing-box (старый) |
|---|---|---|
| VPN клиент | Passwall2 + Xray | Sing-box |
| Протоколы | VLESS XHTTP Reality + Hysteria 2 | VLESS Reality + Hysteria 2 |
| Управление | LuCI веб-интерфейс | SSH + конфиг файл |
| Список доменов | geosite:ru-blocked (авто-обновление) | itdoginfo (cron каждые 8ч) |
| Кастомные домены | PassWall2 → Rule → Custom VPN Domains | LuCI: Services → VPN Domains |

---

## Вариант 1: Passwall2 (рекомендуется)

### Требования

- OpenWrt **23.05+** или **24.10+**
- VPS с VLESS XHTTP Reality + Hysteria 2
- Доступ к роутеру по SSH

### Установка

```bash
sh <(wget -O - https://raw.githubusercontent.com/BalgeetTjinder/domain-routing-openwrt/master/passwall2-install.sh)
```

После установки:

1. LuCI → Services → PassWall2 → Node List
2. Отредактируй ноду **VLESS-XHTTP-Reality** — заполни данные VPS (Address, UUID, Public Key, Short Id)
3. (Опционально) Отредактируй ноду **Hysteria2** — заполни данные (Address, Password, SNI)
4. Basic Settings → Main Node = **Main-Shunt** → Enable → Save & Apply

### Что устанавливается

- `luci-app-passwall2` — веб-интерфейс управления VPN
- `xray-core` — VPN движок (VLESS XHTTP Reality)
- `geoview`, `v2ray-geosite`, `v2ray-geoip` — база доменов
- `dnsmasq-full` — DNS

### Как работает

```
Запрос к youtube.com
        ↓
Passwall2 (Xray Shunt) проверяет домен
        ↓
Домен в geosite:ru-blocked? → Xray → VPS
        ↓
Нет → прямое соединение
```

### Кастомные домены

Открой в LuCI: **Services → PassWall2 → Rule → Custom VPN Domains → Domain List**

Добавь домены (по одному на строку). Save & Apply → Passwall2 перезапустится.

### Полезные команды

```bash
# Логи
logread | grep passwall2

# Перезапуск
/etc/init.d/passwall2 restart

# Статус
/etc/init.d/passwall2 status
```

### Удаление

```bash
sh <(wget -O - https://raw.githubusercontent.com/BalgeetTjinder/domain-routing-openwrt/master/passwall2-uninstall.sh)
```

---

## Вариант 2: Sing-box (legacy)

### Требования

- OpenWrt **23.05+** или **24.10+**
- VPS с настроенным [S-UI](https://github.com/alireza0/s-ui) (VLESS Reality + Hysteria 2)
- Доступ к роутеру по SSH

### Установка

```bash
sh <(wget -O - https://raw.githubusercontent.com/BalgeetTjinder/domain-routing-openwrt/master/getdomains-install.sh)
```

### Полезные команды

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

### Удаление

```bash
sh <(wget -O - https://raw.githubusercontent.com/BalgeetTjinder/domain-routing-openwrt/master/getdomains-uninstall.sh)
```

---

## Благодарности

Основано на [itdoginfo/domain-routing-openwrt](https://github.com/itdoginfo/domain-routing-openwrt)
