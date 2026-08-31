# Ручная установка и разбор проблем

Подробная версия [основного гайда](README.md): что делает `install.sh` по шагам, как поставить всё руками и что делать, когда не работает.

Нужно: SSH на роутер, рабочий интернет, **≥25 МБ** в `/overlay`, ссылка на ноду или подписка.

> [!IMPORTANT]
> **Порядок: сначала PassWall2, потом Zapret.** Zapret-Manager качает архив с GitHub Releases, а `release-assets.githubusercontent.com` у некоторых российских провайдеров не открывается. Пакеты PassWall2 лежат на SourceForge и доступны — поэтому сначала туннель, Zapret через него.

> [!NOTE]
> Гайд строго под 25.12: пакетный менеджер **apk**, фаервол **fw4/nftables**

> [!TIP]
> После **любого** изменения настроек или правил PassWall2 надо перезапустить вручную: **System → Startup → passwall2 → Restart** либо `/etc/init.d/passwall2 restart`. Save & Apply сохраняет конфиг, но службу не трогает — у неё нет procd-триггера, а `ucitrack` в 25.12 больше не используется. Сам `reload` в init-скрипте с версии 26.8.27 уже делает полный restart, но вызвать его некому.

> [!CAUTION]
> Рестарт PassWall2 на несколько секунд роняет туннель и рвёт все активные соединения. Если настраиваете роутер удалённо через этот же туннель — вы отрежете себя. Планируйте рестарт последним шагом либо поднимите VPN-клиент прямо на компьютере.

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
- **`dnsmasq-full`** — штатный собран с `no-nftset`, а на nftset держится вся схема с Zapret. Проверить: `dnsmasq --version | grep -o 'no-nftset\|nftset'`, должно быть без `no-`. Если apk ругнётся на конфликт: `apk del dnsmasq && apk add dnsmasq-full && cp /root/dhcp.bak /etc/config/dhcp && /etc/init.d/dnsmasq restart`
- **`rpcd restart`** — иначе меню PassWall2 может не появиться в LuCI

`geoview`, `v2ray-geoip`, `v2ray-geosite` (~10 МБ) приедут сами — они в жёстких зависимостях.

---

## 2. Нода

**Services → PassWall 2 → Список узлов → Добавить узел по ссылке** → вставить `vless://…`.

Подписка: **Подписки → Добавить**, поле **User-Agent** оставить `v2rayN` (иначе панель отдаст JSON вместо списка ссылок). Save & Apply, затем **обязательно** «Ручное обновление подписки» — само не подтянется.

---

## 3. Временно: весь роутер через VPN

**Общие параметры → Основной**: Узел = конкретный сервер (не `_shunt` и не `Socks: Example`), **Прокси для самого роутера** ✅, **Прокси для клиентских устройств** ✅, **Включить модуль** ✅.

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

**Список узлов → Добавить**, тип **Shunt (разделение трафика)**: «По умолчанию» → **Прямое соединение**, «Записывать результаты прямого DNS в IPSet» ✅.

Правила создаются на вкладке **«Управление правилами»**, внизу страницы. Вкладки `CN|IR|RU` — это группы, правило падает в открытую; проще добавлять на `RU`, узел уже настроен на неё. В правиле заполняется только **Домен** (и **IP**, если по подсетям), остальное пустым.

Готовый базовый набор — [rules/common.txt](rules/common.txt). Блок `geoip:` из него идёт в отдельное поле **IP**, остальное в **Домен**. GitHub и SourceForge в наборе обязательны, иначе следующее обновление упрётся в блокировку:

```text
domain:github.com
domain:githubusercontent.com
domain:githubassets.com
domain:openwrt.org
domain:sourceforge.net
```

Дальше свои домены — **обязательно с префиксом `domain:`**. Голый `x.ai` это поиск подстроки, поймает и `matrix.ai`. Комментарии через `#`. Готовые списки можно подключать категориями (`geosite:telegram`, `geoip:telegram` в поле IP) — состав смотреть на вкладке «Просмотр Geo».

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

## 6. Свой DNS

Без этого шага часть сайтов не откроется даже с рабочим Zapret. Российские провайдеры подменяют DNS-ответы для заблокированных сайтов: `www.instagram.com` вместо реального адреса отдаётся как `127.0.0.1`. Соединение тогда не создаётся вовсе, и обходить DPI попросту нечего.

PassWall2 резолвит **прямые** домены системным резолвером роутера, то есть DNS провайдера. Поля для прямого DNS в `luci-app-passwall2 26.8.27` нет — в UI только «Стратегия прямого запроса», адрес не настраивается. Поэтому чиним не в PassWall2.

**Проверка, есть ли подмена:**

```sh
nslookup www.instagram.com $(sed -n 's/^nameserver //p' /tmp/resolv.conf.d/resolv.conf.auto | head -1)
```

`127.0.0.1`, `0.0.0.0` или `::1` в ответе — подмена. Реальный адрес выглядит как `57.144.222.34`.

**Лечение — свой DoH-резолвер:**

```sh
apk add https-dns-proxy luci-app-https-dns-proxy
uci set https-dns-proxy.config.dnsmasq_config_update='0'
uci set https-dns-proxy.config.force_dns='0'
uci set https-dns-proxy.@https-dns-proxy[1].resolver_url='https://1.1.1.1/dns-query'
uci set https-dns-proxy.@https-dns-proxy[1].bootstrap_dns='1.1.1.1,1.0.0.1,2606:4700:4700::1111,2606:4700:4700::1001'
uci commit https-dns-proxy
/etc/init.d/https-dns-proxy enable
/etc/init.d/https-dns-proxy restart
```

Пакет поднимает два инстанса на `127.0.0.1:5053` и `:5054`. Второй по умолчанию — Google, и он на российских линиях отдаёт заблокированный адрес Instagram, поэтому команда выше переводит его тоже на Cloudflare.

> [!WARNING]
> **Порты `5053`/`5054` менять нельзя.** PassWall2 при рестарте сам находит `https-dns-proxy` и прописывает его в свой прямой резолвер (`dns_default_direct.conf`) именно как `server=127.0.0.1#5053` и `#5054` — по дефолтным портам. Посадите прокси на свои — и PassWall2 после ближайшего рестарта будет спрашивать пустоту, а прямой резолв тихо сломается.

Две галки в первых строках отключают вмешательство `https-dns-proxy` в dnsmasq и в правила перехвата DNS — этим уже управляет PassWall2, а два хозяина у одного dnsmasq конфликтуют.

**Системный резолвер роутера** (обновления, ntp, сам Zapret-Manager) живёт отдельно и всё ещё смотрит на провайдера. Ему нужен третий инстанс на обычном порту:

```sh
uci add https-dns-proxy https-dns-proxy
uci set https-dns-proxy.@https-dns-proxy[2].resolver_url='https://cloudflare-dns.com/dns-query'
uci set https-dns-proxy.@https-dns-proxy[2].bootstrap_dns='1.1.1.1,1.0.0.1,2606:4700:4700::1111,2606:4700:4700::1001'
uci set https-dns-proxy.@https-dns-proxy[2].listen_addr='127.0.0.53'
uci set https-dns-proxy.@https-dns-proxy[2].listen_port='53'
uci commit https-dns-proxy
/etc/init.d/https-dns-proxy restart
netstat -lnup | grep https-dns
```

Ждём три строки: `127.0.0.1:5053`, `127.0.0.1:5054`, `127.0.0.53:53`.

Дальше **Network → Interfaces → WAN → Дополнительные настройки**: снять **«Use DNS servers advertised by peer»**, в **«Use custom DNS servers»** вписать `127.0.0.53`. Вторым адресом можно добавить `94.140.14.14` — аварийный фолбэк на случай, если DoH недоступен.

Проверять резолв надо на трёх уровнях, они независимы:

```sh
nslookup -port=2003 www.instagram.com 127.0.0.1   # прямой резолвер PassWall2
nslookup www.instagram.com 127.0.0.1              # то, что видят клиенты
nslookup www.instagram.com 127.0.0.53             # системный резолвер роутера
```

Везде должен быть реальный адрес.

> [!NOTE]
> Публичные DNS по обычному UDP на многих российских линиях просто не отвечают — `8.8.8.8`, `9.9.9.9`, `77.88.8.8`, OpenDNS, NextDNS уходят в таймаут. Поэтому и нужен именно DoH: он идёт по 443/TCP и проходит там, где plain-DNS зарезан.

---

## 7. Проверка

```sh
curl -s -m 10 https://ifconfig.me/ip; echo " <- прямой, ждём домашний"
curl -s -m 10 https://ipinfo.io/ip; echo " <- проксируемый, ждём IP ноды"
nslookup claude.ai 127.0.0.1 | tail -3
```

`ipinfo.io` должен быть в проксируемом правиле, `ifconfig.me` — нет. Третья команда проверяет FakeDNS: ждём `198.18.x.x`.

DPI: https://hyperion-cs.github.io/dpi-checkers/ru/tcp-16-20/

---

## Грабли

| симптом | причина и лечение |
|---|---|
| Настройки сохранены, но `Core: Служба остановлена`, в журнале пусто | служба не перезапускалась: Save & Apply её не трогает. **System → Startup → passwall2 → Restart** или `/etc/init.d/passwall2 restart` |
| Кнопка «Добавить» у правила молча не срабатывает | в имени дефис. Имя правила = имя UCI-секции, только `[A-Za-z0-9_]` |
| Перенёс домен в проксируемые, а он идёт напрямую | старые адреса залипли в nft-наборе (таймаут 365 дней): `nft flush set inet passwall2 psw2_<узел>_white` + рестарт dnsmasq и passwall2. То же делает кнопка «Очистить NFTSet» |
| FakeDNS не отдаёт `198.18.x.x` | не включён мастер-переключатель, галки в столбце у правил без него не работают |
| Подозрение на утечку по IPv6 | PassWall2 перехватывает только v4, но при включённом FakeDNS утечки нет: для проксируемых доменов AAAA не выдаётся, клиент идёт по v4. Проверить обе стороны: `nslookup -type=AAAA ipinfo.io 127.0.0.1` (проксируемый — должно быть пусто) и `nslookup -type=AAAA ya.ru 127.0.0.1` (прямой — AAAA должны быть, иначе v6 прибит целиком). Барьер не действует на устройства с зашитым DoH — они спрашивают DNS мимо роутера |
| В браузере не работает то, что работает из консоли | включён DoH («Secure DNS» в Chrome) — браузер ходит мимо dnsmasq. Выключить |
| Zapret обрабатывает не тот трафик | не стоит «Записывать результаты прямого DNS в IPSet». Без неё в xray заходит **весь** TCP, и наружу идёт поток xray, а не клиента |
| Сайт не открывается, хотя Zapret работает и другие сайты чинит | сначала DNS, а не стратегия. `nslookup <домен> 127.0.0.1` — если `127.0.0.1`/`0.0.0.0`, это подмена провайдером, см. [раздел 6](#6-свой-dns) |
| DNS чинён, адрес реальный, но сайт всё равно молчит | блок по IP, а не по имени. Проверить: `curl -sS -o /dev/null -m 10 -w "%{http_code}
" --resolve <домен>:443:<IP> https://<домен>/`. Если один адрес молчит, а другие того же сайта отвечают 200 — адрес забанен, **Zapret тут бессилен принципиально**: дурение DPI не оживляет дроп по адресу назначения. Лечится только другим адресом (другой резолвер) или заворотом домена в туннель |
| После настройки DoH прямой резолв сломался | у `https-dns-proxy` сменили порты. PassWall2 ждёт его строго на `127.0.0.1:5053/5054` — вернуть дефолт |
| Инстанс `https-dns-proxy` не поднимается | в журнале `c-ares needed more IO event handler, than the number of provided nameservers: 2` — в `bootstrap_dns` два адреса. Указать все четыре (2×IPv4 + 2×IPv6) |
| Сайт работает на телефоне, но не на ПК (или наоборот) | часть блокировок только по IPv4. Проверить обе стороны: `curl -4` и `curl -6`. Если v6 отвечает, а v4 нет — устройства с рабочим IPv6 не заметят проблемы |
| `apk update` не видит штатный фид | лёг `downloads.openwrt.org`: `sed -i 's\|https://downloads.openwrt.org/\|https://mirror-03.infra.openwrt.org/\|' /etc/apk/repositories.d/distfeeds.list` |
| Не хватает места | снести старое решение вместе с sing-box (~42 МБ): `apk del luci-app-netshift netshift sing-box` |
| Zapret не качается даже через туннель | скачать zip с [remittor/zapret-openwrt](https://github.com/remittor/zapret-openwrt/releases) на ПК, залить в `/tmp/zapret_temp`, распаковать и `apk add --allow-untrusted apk/*.apk` (сначала `zapret*`, потом `luci*`) |

Логи: `/tmp/log/passwall2.log`, `logread | grep passwall2`, либо вкладка «Журналы выполнения».

RAM: официальный минимум PassWall2 — **256 МБ**. На роутерах с 256 МБ и меньше работает, но запаса нет: не ставить geo-пакеты сверх нужного и не включать «анализ данных GeoIP».

---

## Ссылки

- [PassWall2](https://github.com/Openwrt-Passwall/openwrt-passwall2) · [сборки под 25.12](https://sourceforge.net/projects/openwrt-passwall-build/files/releases/packages-25.12/)
- [Zapret-Manager](https://github.com/StressOzz/Zapret-Manager) · [архивы Zapret](https://github.com/remittor/zapret-openwrt/releases)
- [https-dns-proxy](https://github.com/aarond10/https_dns_proxy) · [список DoH-резолверов](https://github.com/curl/curl/wiki/DNS-over-HTTPS)
- [Проверка DPI](https://hyperion-cs.github.io/dpi-checkers/ru/tcp-16-20/)
