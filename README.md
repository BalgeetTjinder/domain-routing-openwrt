# Domain Routing OpenWRT

Ansible роль для настройки роутера на OpenWrt для точечной маршрутизации по доменам через Sing-box (VLESS Reality / Hysteria 2).

## Возможности

- **VLESS + Reality** — максимальная устойчивость к блокировкам, маскировка под легитимный HTTPS
- **Hysteria 2** — быстрый протокол на QUIC/UDP с алгоритмом Brutal против throttling
- **Маршрутизация по доменам** — только заблокированные домены идут через VPN
- **DNS шифрование** — Stubby или DNSCrypt

## Требования

- OpenWrt 23.05+ или 24.10+
- Ansible 2.10+
- Настроенный VPN сервер (S-UI / Sing-box)

## Установка

```bash
ansible-galaxy role install itdoginfo.domain_routing_openwrt
```

## Примеры playbook

### VLESS + Reality (рекомендуется)

```yaml
- hosts: 192.168.1.1
  remote_user: root

  roles:
    - itdoginfo.domain_routing_openwrt

  vars:
    tunnel: singbox
    singbox_protocol: vless-reality
    dns_encrypt: stubby
    country: russia-inside

    vless_server: "79.137.195.239"
    vless_port: 443
    vless_uuid: "your-uuid"
    vless_sni: "www.microsoft.com"
    vless_fingerprint: "chrome"
    vless_public_key: "your-public-key"
    vless_short_id: "your-short-id"
```

### Hysteria 2

```yaml
- hosts: 192.168.1.1
  remote_user: root

  roles:
    - itdoginfo.domain_routing_openwrt

  vars:
    tunnel: singbox
    singbox_protocol: hysteria2
    dns_encrypt: stubby
    country: russia-inside

    hysteria2_server: "79.137.195.239"
    hysteria2_port: 8443
    hysteria2_password: "your-password"
    hysteria2_sni: "dev.milostyle.online"
    hysteria2_up_mbps: 100
    hysteria2_down_mbps: 100
```

### Оба протокола (с возможностью переключения)

```yaml
- hosts: 192.168.1.1
  remote_user: root

  roles:
    - itdoginfo.domain_routing_openwrt

  vars:
    tunnel: singbox
    singbox_protocol: multi
    dns_encrypt: stubby
    country: russia-inside

    # VLESS + Reality
    vless_enabled: true
    vless_server: "79.137.195.239"
    vless_port: 443
    vless_uuid: "your-uuid"
    vless_sni: "www.microsoft.com"
    vless_fingerprint: "chrome"
    vless_public_key: "your-public-key"
    vless_short_id: "your-short-id"

    # Hysteria 2
    hysteria2_enabled: true
    hysteria2_server: "79.137.195.239"
    hysteria2_port: 8443
    hysteria2_password: "your-password"
    hysteria2_sni: "dev.milostyle.online"
    hysteria2_up_mbps: 100
    hysteria2_down_mbps: 100
```

## Inventory

```ini
[openwrt]
192.168.1.1
```

## Переменные

### Основные

| Переменная | Описание | По умолчанию |
|------------|----------|--------------|
| `tunnel` | Тип туннеля | `singbox` |
| `singbox_protocol` | Протокол: `vless-reality`, `hysteria2`, `multi` | `multi` |
| `dns_encrypt` | DNS шифрование: `stubby`, `dnscrypt`, `false` | `stubby` |
| `country` | Список доменов: `russia-inside`, `russia-outside`, `ukraine` | `russia-inside` |

### VLESS + Reality

| Переменная | Описание |
|------------|----------|
| `vless_server` | IP адрес VPN сервера |
| `vless_port` | Порт (обычно 443) |
| `vless_uuid` | UUID клиента |
| `vless_sni` | SNI для маскировки |
| `vless_fingerprint` | Fingerprint (chrome, firefox, safari) |
| `vless_public_key` | Публичный ключ Reality |
| `vless_short_id` | Short ID |

### Hysteria 2

| Переменная | Описание |
|------------|----------|
| `hysteria2_server` | IP адрес VPN сервера |
| `hysteria2_port` | Порт (обычно 8443) |
| `hysteria2_password` | Пароль |
| `hysteria2_sni` | Домен для TLS |
| `hysteria2_up_mbps` | Upload скорость для Brutal |
| `hysteria2_down_mbps` | Download скорость для Brutal |

## После установки

```bash
service network restart
service getdomains start
```

## Проверка

```bash
wget -O - https://raw.githubusercontent.com/itdoginfo/domain-routing-openwrt/master/getdomains-check.sh | sh
```
