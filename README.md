# PassWall2 + Zapret на OpenWrt 25.12

Точечная маршрутизация через VPN (PassWall2) плюс обход DPI (Zapret) на чистом роутере
с OpenWrt 25.12

Нужно: SSH на роутер, рабочий интернет, **≥25 МБ** в `/overlay`, vless ключ или ссылка на подписку.

> [!IMPORTANT]
> **Порядок: сначала PassWall2, потом Zapret.** Zapret-Manager качает архив с GitHub Releases,
> а `release-assets.githubusercontent.com` у российских провайдеров не открывается. Пакеты
> PassWall2 лежат на SourceForge и доступны — поэтому сначала туннель, Zapret через него.

> [!NOTE]
> Гайд строго под 25.12: пакетный менеджер **apk**, фаервол **fw4/nftables**.
> Podkop и NetShift не подходят принципиально — они завязаны на sing-box, который шлёт
> зашитую версию REALITY 1.8.1 и отсекается сервером по `minClientVer`. PassWall2 работает
> на xray-core, отдающем настоящую версию.

---

## 1. Установка

```sh
. /etc/openwrt_release
B="https://master.dl.sourceforge.net/project/openwrt-passwall-build"
wget -O /etc/apk/keys/passwall.pub "$B/apk.pub"
for f in passwall_packages passwall_luci passwall2; do
  echo "$B/releases/packages-25.12/$DISTRIB_ARCH/$f/packages.adb"
done >> /etc/apk/repositories.d/customfeeds.list
apk update
apk add luci-app-passwall2 luci-i18n-passwall2-ru xray-core tcping
apk add kmod-nft-socket kmod-nft-tproxy kmod-nft-nat
cp /etc/config/dhcp /root/dhcp.bak && apk add dnsmasq-full
/etc/init.d/rpcd restart
```

`25.12` — ветка релиза, на 25.12.5 путь тот же. Ядро — **xray**, не sing-box.

Три команды после основной установки обязательны, сам пакет их не тянет:

- **kmod'ы** — без них галки «Прокси для…» серые, в журнале `missing basic dependency`
- **`dnsmasq-full`** — штатный собран с `no-nftset`, а на nftset держится вся схема с Zapret.
  Проверить: `dnsmasq --version | grep -o 'no-nftset\|nftset'`, должно быть без `no-`.
  Если apk ругнётся на конфликт:
  `apk del dnsmasq && apk add dnsmasq-full && cp /root/dhcp.bak /etc/config/dhcp && /etc/init.d/dnsmasq restart`
- **`rpcd restart`** — иначе меню PassWall2 может не появиться в LuCI

`geoview`, `v2ray-geoip`, `v2ray-geosite` (~10 МБ) приедут сами — они в жёстких зависимостях.

---

## 2. Нода

**Services → PassWall 2 → Список узлов → Добавить узел по ссылке** → вставить `vless://…`.

Подписка: **Подписки → Добавить**, поле **User-Agent** оставить `v2rayN` (иначе панель отдаст
JSON вместо списка ссылок). Save & Apply, затем **обязательно** «Ручное обновление подписки» —
само не подтянется.

---

## 3. Временно: весь роутер через VPN

**Общие параметры → Основной**: Узел = конкретный сервер (не `_shunt` и не `Socks: Example`),
**Прокси для самого роутера** ✅, **Прокси для клиентских устройств** ✅, **Включить модуль** ✅.

Save & Apply, затем:

```sh
/etc/init.d/passwall2 enable; /etc/init.d/passwall2 restart
curl -s -m 10 https://ipinfo.io/ip; echo
```

Должен вернуться IP ноды. Узлы `Xray HY2` без пакета `hysteria` молча не работают.

---

## 4. Zapret

Теперь качается штатно:

```sh
sh <(wget -O - https://raw.githubusercontent.com/StressOzz/Zapret-Manager/main/Zapret-Manager.sh)
```

Установка — пункт `1`, стратегии — пункт `3`.

---

## 5. Боевая схема

**Список узлов → Добавить**, тип **Shunt (разделение трафика)**:
«По умолчанию» → **Прямое соединение**, «Записывать результаты прямого DNS в IPSet» ✅.

Правила создаются на вкладке **«Управление правилами»**, внизу страницы. Вкладки `CN|IR|RU` —
это группы, правило падает в открытую; проще добавлять на `RU`, узел уже настроен на неё.
В правиле заполняется только **Домен** (и **IP**, если по подсетям), остальное пустым.

Первым — правило `infra`, иначе следующее обновление упрётся в блокировку:

```text
domain:github.com
domain:githubusercontent.com
domain:githubassets.com
domain:openwrt.org
domain:sourceforge.net
```

Дальше свои домены — **обязательно с префиксом `domain:`**. Голый `x.ai` это поиск подстроки,
поймает и `matrix.ai`. Комментарии через `#`. Готовые списки можно подключать категориями
(`geosite:telegram`, `geoip:telegram` в поле IP) — состав смотреть на вкладке «Просмотр Geo».

Затем **Общие параметры → Правила разделения трафика** (видна, только когда Узел — Shunt):

| параметр | значение |
|---|---|
| Группа правил шунтирования | `RU` |
| напротив правил | VPN-нода |
| **По умолчанию** | **Прямое соединение** (изначально `(Not set)`) |
| Порядок разрешения имён | `AsIs` |
| **FakeDNS Включить модуль** | ✅ мастер-галка, отдельно от столбца FakeDNS у правил |
| Включить анализ данных GeoIP | снять, если нет правил с `geoip:` |
| Цепочка прокси | Отключено |

И **Основной** → Узел = Shunt-узел.

```sh
/etc/init.d/passwall2 restart
```

---

## 6. Проверка

```sh
curl -s -m 10 https://ifconfig.me/ip; echo " <- прямой, ждём домашний"
curl -s -m 10 https://ipinfo.io/ip; echo " <- проксируемый, ждём IP ноды"
nslookup claude.ai 127.0.0.1 | tail -3
```

`ipinfo.io` должен быть в проксируемом правиле, `ifconfig.me` — нет. Третья команда проверяет
FakeDNS: ждём `198.18.x.x`.

DPI: https://hyperion-cs.github.io/dpi-checkers/ru/tcp-16-20/

---

## Грабли

| симптом | причина и лечение |
|---|---|
| Настройки сохранены, но `Core: Служба остановлена`, в журнале пусто | LuCI зовёт `reload`, а это заглушка. **`/etc/init.d/passwall2 restart` после любого изменения** |
| Кнопка «Добавить» у правила молча не срабатывает | в имени дефис. Имя правила = имя UCI-секции, только `[A-Za-z0-9_]` |
| Перенёс домен в проксируемые, а он идёт напрямую | старые адреса залипли в nft-наборе (таймаут 365 дней): `nft flush set inet passwall2 psw2_<узел>_white` + рестарт dnsmasq и passwall2. То же делает кнопка «Очистить NFTSet» |
| FakeDNS не отдаёт `198.18.x.x` | не включён мастер-переключатель, галки в столбце у правил без него не работают |
| Проксируемый домен уходит мимо туннеля по IPv6 | PassWall2 перехватывает только v4. Проверить: `curl -s -m 10 -6 https://ipinfo.io/ip` — пусто хорошо. Лечится «IPv6 TProxy» в «Дополнительных настройках» |
| В браузере не работает то, что работает из консоли | включён DoH («Secure DNS» в Chrome) — браузер ходит мимо dnsmasq. Выключить |
| Zapret обрабатывает не тот трафик | не стоит «Записывать результаты прямого DNS в IPSet». Без неё в xray заходит **весь** TCP, и наружу идёт поток xray, а не клиента |
| `apk update` не видит штатный фид | лёг `downloads.openwrt.org`: `sed -i 's\|https://downloads.openwrt.org/\|https://mirror-03.infra.openwrt.org/\|' /etc/apk/repositories.d/distfeeds.list` |
| Не хватает места | снести старое решение вместе с sing-box (~42 МБ): `apk del luci-app-netshift netshift sing-box` |
| Zapret не качается даже через туннель | скачать zip с [remittor/zapret-openwrt](https://github.com/remittor/zapret-openwrt/releases) на ПК, залить в `/tmp/zapret_temp`, распаковать и `apk add --allow-untrusted apk/*.apk` (сначала `zapret*`, потом `luci*`) |

Логи: `/tmp/log/passwall2.log`, `logread | grep passwall2`, либо вкладка «Журналы выполнения».

RAM: официальный минимум PassWall2 — **256 МБ**. На роутерах с 256 МБ и меньше работает,
но запаса нет: не ставить geo-пакеты сверх нужного и не включать «анализ данных GeoIP».

---

## Ссылки

- [PassWall2](https://github.com/Openwrt-Passwall/openwrt-passwall2) ·
  [сборки под 25.12](https://sourceforge.net/projects/openwrt-passwall-build/files/releases/packages-25.12/)
- [Zapret-Manager](https://github.com/StressOzz/Zapret-Manager) ·
  [архивы Zapret](https://github.com/remittor/zapret-openwrt/releases)
- [Проверка DPI](https://hyperion-cs.github.io/dpi-checkers/ru/tcp-16-20/)
