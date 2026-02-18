# Domain Routing OpenWrt

Точечная маршрутизация по доменам на OpenWrt. Только заблокированные сайты идут через VPN, остальной трафик — напрямую.

Два варианта установки:

| | Passwall2 (новый) | Sing-box (старый) |
|---|---|---|
| VPN клиент | Passwall2 + Xray | Sing-box |
| Протоколы | VLESS XHTTP Reality + Hysteria 2 | VLESS Reality + Hysteria 2 |
| Управление | LuCI веб-интерфейс | SSH + конфиг файл |
| Список доменов | geosite:ru-blocked | itdoginfo (cron каждые 8ч) |
| Кастомные домены | PassWall2 → Rule Manage → Custom VPN Domains | LuCI: Services → VPN Domains |

---

## Вариант 1: Passwall2 (рекомендуется)

### Требования

- OpenWrt **23.05+** или **24.10+**
- VPS с VLESS XHTTP Reality и/или Hysteria 2
- Доступ к роутеру по SSH

### Установка

```bash
sh <(wget -O - https://raw.githubusercontent.com/BalgeetTjinder/domain-routing-openwrt/master/passwall2-install.sh)
```

### После установки

1. **Добавь VPN ноды** (один из способов):
   - `Node Subscribe` → Add → вставь URL подписки → Save & Apply → Manual subscription
   - `Node List` → Add the node via the link → вставь `vless://...` ссылку
   - `Node List` → Add → заполни вручную

2. **Настрой маршрутизацию:**
   - `Basic Settings` → Main Node = **Main-Shunt**
   - Нажми Edit у Main-Shunt:
     - `Russia_Block` → твоя VPN нода
     - `Custom VPN Domains` → твоя VPN нода
     - `Default` → Direct Connection
   - Save & Apply

3. **Включи:**
   - `Basic Settings` → Enable → Save & Apply

### Что устанавливается

- `luci-app-passwall2` — веб-интерфейс
- `xray-core` — VPN движок
- `geoview`, `v2ray-geosite`, `v2ray-geoip` — база доменов
- `dnsmasq-full` — DNS
- `hysteria` — клиент Hysteria2 (опционально)

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

LuCI: **Services → PassWall2 → Rule Manage → Custom VPN Domains → Domain List**

По одному домену на строку. Save & Apply → Passwall2 перезапустится.

### Полезные команды

```bash
/etc/init.d/passwall2 restart   # перезапуск
logread | grep passwall2        # логи (может segfault — известный баг OpenWrt)
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
logread | grep sing-box
service sing-box restart
/etc/init.d/getdomains start
sh <(wget -O - https://raw.githubusercontent.com/BalgeetTjinder/domain-routing-openwrt/master/getdomains-check.sh)
```

### Удаление

```bash
sh <(wget -O - https://raw.githubusercontent.com/BalgeetTjinder/domain-routing-openwrt/master/getdomains-uninstall.sh)
```

---

## Благодарности

Основано на [itdoginfo/domain-routing-openwrt](https://github.com/itdoginfo/domain-routing-openwrt)
