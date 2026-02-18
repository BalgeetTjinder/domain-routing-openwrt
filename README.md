# Domain Routing OpenWrt

Точечная маршрутизация по доменам на OpenWrt. Только заблокированные сайты идут через VPN, остальной трафик — напрямую.

Два варианта установки:

| | Passwall2 (новый) | Sing-box (старый) |
|---|---|---|
| VPN клиент | Passwall2 + Xray | Sing-box |
| Протоколы | VLESS XHTTP Reality + Hysteria 2 | VLESS Reality + Hysteria 2 |
| Балансировка | Auto-Balancer (leastPing) | urltest |
| Управление | LuCI веб-интерфейс | SSH + конфиг файл |
| Список доменов | geosite:ru-blocked (runetfreedom, авто-обновление) | itdoginfo (cron каждые 8ч) |
| Кастомные домены | PassWall2 → Rule Manage → Custom VPN Domains | LuCI: Services → VPN Domains |

---

## Вариант 1: Passwall2 (рекомендуется)

### Требования

- OpenWrt **23.05+** или **24.10+** (SNAPSHOT тоже поддерживается)
- VPS с VLESS XHTTP Reality и/или Hysteria 2
- Доступ к роутеру по SSH

### Установка

```bash
sh <(wget -O - https://raw.githubusercontent.com/BalgeetTjinder/domain-routing-openwrt/master/passwall2-install.sh)
```

### После установки

1. **Добавь VPN ноды** (один из способов):
   - `Node Subscribe` → Add → вставь URL подписки → Save & Apply → Manual subscription
   - `Node List` → Add the node via the link → вставь `vless://...` или `hy2://...` ссылку
   - `Node List` → Add → заполни вручную

2. **Добавь ноды в балансировщик:**
   - Открой **Auto-Balancer** → добавь свои VLESS и Hysteria2 ноды
   - Стратегия leastPing — автоматически выбирает самый быстрый протокол

3. **Включи:**
   - `Basic Settings` → Enable → Save & Apply

Маршрутизация уже преднастроена скриптом:
- `Russia_Block` (geosite:ru-blocked + geoip:ru-blocked) → Auto-Balancer → VPN
- `Custom VPN Domains` → Auto-Balancer → VPN
- Всё остальное → Direct (без VPN)

### Что устанавливается

- `luci-app-passwall2` — LuCI веб-интерфейс
- `xray-core` — основной VPN движок (VLESS, Reality, XHTTP)
- `hysteria` — клиент Hysteria2
- `geoview` — конвертер geo в rulesets для sing-box
- `v2ray-geosite`, `v2ray-geoip` — заменяются на [runetfreedom](https://github.com/runetfreedom/russia-v2ray-rules-dat) данные
- `dnsmasq-full` — DNS с поддержкой nftset
- `kmod-nft-socket`, `kmod-nft-tproxy` — модули для прозрачного прокси

### Как работает

```
Запрос к youtube.com
        ↓
Passwall2 → Main-Shunt проверяет домен
        ↓
Домен в geosite:ru-blocked? → Auto-Balancer → лучший из VLESS/Hysteria2 → VPS
        ↓
Домен в Custom VPN Domains? → Auto-Balancer → VPS
        ↓
Нет → прямое соединение (Direct)
```

### Кастомные домены

LuCI: **Services → PassWall2 → Rule Manage → Custom VPN Domains → Domain List**

По одному домену на строку. Save & Apply → PassWall2 перезапустится.

### Geodata

Источник: [runetfreedom/russia-v2ray-rules-dat](https://github.com/runetfreedom/russia-v2ray-rules-dat)

Доступные категории: `geosite:ru-blocked`, `geoip:ru-blocked`, `geosite:refilter`, `geosite:category-ads-all` и другие.

Файлы обновляются автоматически каждые 6 часов через cron. Ручное обновление:

```bash
/usr/bin/passwall2-update-geodata
```

### Полезные команды

```bash
/etc/init.d/passwall2 restart      # перезапуск
/etc/init.d/passwall2 stop         # остановка
logread | grep passwall2           # логи
/usr/bin/passwall2-update-geodata  # обновить geodata вручную
```

### Удаление

Полная очистка (сервис, пакеты, конфиги, runtime, geodata, feeds, LuCI cache):

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
