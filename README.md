# PassWall2 + Zapret на OpenWrt 25.12

Роутер: чистый OpenWrt 25.12 (пакетный менеджер `apk`), нужно ≥25 МБ в `/overlay`.

> [!IMPORTANT]
> **Сначала PassWall2, потом Zapret.** Zapret-Manager качает архив с GitHub Releases,
> а `release-assets.githubusercontent.com` у российских провайдеров не открывается.
> Пакеты PassWall2 лежат на SourceForge и доступны — поэтому сначала поднимаем туннель,
> а Zapret ставим уже через него. Записи в `/etc/hosts` не помогают, не тратить время.

---

## 1. Установка PassWall2

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
```

`25.12` — ветка релиза, на 25.12.5 путь тот же. Ядро — именно **xray**: sing-box отваливается
от `minClientVer` на сервере.

> [!IMPORTANT]
> Вторая и третья команды обязательны, сам пакет их **не тянет**:
>
> - **kmod'ы** прописаны в Makefile через `select` в конфиге сборки, а не в `DEPENDS`.
>   Без них галки «Прокси для самого роутера» и «Прокси для клиентских устройств» серые,
>   а в журнале `missing basic dependency kmod-nft-socket`.
> - **`dnsmasq-full`** — штатный `dnsmasq` собран с `no-nftset`, а на nftset держится
>   `write_ipset_direct` из шага 5. Проверить: `dnsmasq --version | grep -o 'no-nftset\|nftset'`,
>   должно быть `nftset` без `no-`. Замена на пару секунд роняет DNS и DHCP.
>   Если apk ругнётся на конфликт:
>   ```sh
>   apk del dnsmasq && apk add dnsmasq-full && cp /root/dhcp.bak /etc/config/dhcp && /etc/init.d/dnsmasq restart
>   ```
>
> `geoview`, `v2ray-geoip`, `v2ray-geosite` приедут сами — они в жёстких зависимостях
> `luci-app-passwall2`, отказаться нельзя, это ~10 МБ.

---

## 2. Нода

**Services → PassWall 2 → Список узлов → Добавить узел по ссылке** → вставить `vless://…`.

Если подписка — **Подписки → Добавить**: название, URL, **User-Agent** оставить `v2rayN`
(иначе панель отдаст JSON вместо списка ссылок), при желании **Отправлять HWID** ✅ —
тогда роутер будет виден в статистике панели. Save & Apply, после чего **обязательно** нажать
**«Ручное обновление подписки»** — само оно не подтянется, узлов будет 0.

---

## 3. Временно: весь роутер через VPN

**Общие параметры**, вкладка **Основной** (не «Список узлов» — там только каталог):

- **Узел** — конкретный сервер из группы подписки. Не `Xray _shunt: [rulenode]`
  и не `Xray Socks: [Example]` — это заготовки из дефолтного конфига
- **Прокси для самого роутера** — ✅
- **Прокси для клиентских устройств** — ✅
- **Включить модуль** — ✅

> [!TIP]
> Узлы `Xray HY2` (Hysteria2) без пакета `hysteria` молча не работают — брать `Xray VLESS`.

Save & Apply, а затем **обязательно запустить службу из консоли**:

```sh
/etc/init.d/passwall2 enable; /etc/init.d/passwall2 restart
```

> [!CAUTION]
> Без этой команды ничего не заработает. LuCI по «Save & Apply» дёргает
> `/etc/init.d/passwall2 reload`, а `reload()` в init-скрипте — заглушка, печатающая
> «does not support configuration reloading». Признак: конфиг сохранён, галки стоят,
> но статус `Core: Служба остановлена` и в «Журналах выполнения» нет новых записей.

Проверить — должен вернуться IP ноды:

```sh
wget -q -O - https://ipinfo.io/ip; echo
```

---

## 4. Zapret

Теперь качается штатно:

```sh
sh <(wget -O - https://raw.githubusercontent.com/StressOzz/Zapret-Manager/main/Zapret-Manager.sh)
```

Установка — пункт `1`, стратегии — пункт `3`.

---

## 5. Боевая схема

**Список узлов → Добавить**, тип — **Shunt (разделение трафика)**:

- **По умолчанию** — **Прямое соединение**
- **Записывать результаты прямого DNS в IPSet** — ✅

> [!CAUTION]
> Вторая галка обязательна. Без неё PassWall2 гонит через xray **весь** трафик, и Zapret
> начинает обрабатывать поток xray вместо клиентского — ломается тихо, без ошибок.

Правила создаются на верхней вкладке **«Управление правилами»**, в самом низу страницы под
настройками geo-файлов — там список и кнопка **«Добавить»**. Не путать с вкладкой «Правила
разделения трафика» в «Общих параметрах»: там правила только привязываются к нодам.

Вкладки `CN | IR | RU` над списком — это **группы**. Правило добавляется в ту, что открыта,
и Shunt-узел применяет только правила своей группы (по умолчанию `RU`). Проще всего добавлять
на вкладке `RU` — узел уже настроен на неё, ничего переключать не придётся. Дефолтные
`Russia_Block` и `Russia` можно удалить.

> [!WARNING]
> Имя правила — это имя UCI-секции, поэтому **только буквы, цифры и подчёркивание**.
> С дефисом (`my-domains`) кнопка «Добавить» молча ничего не делает: страница перезагрузится,
> правило не появится. Пиши `my_domains`.

В самом правиле заполняется только **Домен** (и **IP**, если правило по подсетям). Остальное
оставить пустым: пустой «Протокол» — любой, пустая «Метка входящего соединения» — все инбаунды
(проверено в `util_xray.lua:1426`: пустое значение даёт `inboundTag = nil`), пустой Source —
все устройства. `invert` работает только в sing-box.

Первым — обязательное правило `infra`, иначе следующее обновление упрётся в блокировку:

```text
domain:github.com
domain:githubusercontent.com
domain:githubassets.com
domain:openwrt.org
domain:sourceforge.net
```

Дальше свои правила. Домены писать **только с префиксом `domain:`** — он значит «домен и все
поддомены». Голый `x.ai` — это поиск подстроки, поймает и `matrix.ai`, и `linux.ai`.
Комментарии — через `#`.

> [!WARNING]
> Списка доменов по URL, как в podkop, в passwall2 **нет** — домены хранятся текстом в UCI.
> Строки `rule-set:remote:…srs` (лежат закомментированными в дефолтном правиле `Ru`) на xray
> не работают: `util_xray.lua` их молча пропускает, `.srs` — формат sing-box.
> `geosite:ru-blocked` работает, но требует `geosite.dat` от runetfreedom — **73.7 МБ**
> плюс geoip 18.7 МБ, на этом железе не влезет.
> Какие категории есть в штатном `geosite.dat` — смотреть на вкладке **«Просмотр Geo»**.

Что ходит по IP (Telegram) — подсетями в поле **IP**, так быстрее:

```text
91.108.4.0/22
91.108.8.0/21
91.108.16.0/21
91.108.56.0/22
149.154.160.0/20
185.76.151.0/24
```

Дальше **Общие параметры → Правила разделения трафика** (вкладка видна, только когда выбранный
Узел — Shunt). Там:

- **Группа правил шунтирования** → `RU`, после чего появятся твои правила
- напротив них — VPN-нода (у каждого правила своя, если нужно)
- **«По умолчанию»** → **Прямое соединение** (изначально `(Not set)`, это надо поменять)
- **Порядок разрешения имён** → `AsIs` (вместо `IPOnDemand`: меньше лишних резолвов, когда
  маршрутизация по доменам)
- **Включить анализ данных GeoIP** → снять, если в правилах нет `geoip:`
- **FakeDNS Включить модуль** → ✅ — это **мастер-переключатель**, отдельный от галок в столбце
  FakeDNS напротив правил. Без него столбец не работает
- **Записывать результаты прямого DNS в IPSet** → ✅ (у заготовки `rulenode` уже стоит)
- **Цепочка прокси** → «Отключено». Это выход через две ноды подряд, нужен редко

Затем **Общие параметры → Основной** → **Узел** = Shunt-узел, обе галки «Прокси для…»
оставить включёнными.

```sh
/etc/init.d/passwall2 restart
```

> [!CAUTION]
> Перезапускать **после каждого** изменения настроек, а не только при первом запуске — LuCI
> конфиг не перечитывает. Симптом: поменял что-то, а поведение прежнее.

---

## 6. Проверка

```sh
curl -s -m 10 https://ifconfig.me/ip; echo " <- прямой, ждём домашний"
curl -s -m 10 https://ipinfo.io/ip; echo " <- проксируемый, ждём IP ноды"
```

`ipinfo.io` должен быть в проксируемом правиле, `ifconfig.me` — нет. Оба одинаковые — разделение
не работает. (`wget -O -` тут не годится: `ifconfig.me` отдаёт ему HTML-страницу.)

FakeDNS работает, если проксируемый домен резолвится в подставной адрес:

```sh
nslookup claude.ai 127.0.0.1 | tail -3
```

Ждём `198.18.x.x`. Реальный адрес — значит FakeDNS не применился.

Проверка на утечку IPv6 (PassWall2 по умолчанию перехватывает только IPv4):

```sh
curl -s -m 10 -6 https://ipinfo.io/ip; echo " <- пусто = утечки нет"
```

Вернулся домашний IPv6 — проксируемый домен уходит мимо туннеля, включать «IPv6 TProxy»
в «Дополнительных настройках». С включённым FakeDNS такого обычно не бывает: подставной адрес
выдаётся только в IPv4, и клиент вынужден идти по нему.

Логи — **Службы → PassWall2 → Журналы выполнения**.

---

## Если что-то не встало

- **Перенёс домен из «прямых» в проксируемые, а он всё равно идёт напрямую.** Его старые адреса
  залипли в nft-наборе `psw2_<узел>_white` — у элементов там таймаут **365 дней**. Найти и снести:
  ```sh
  nft list sets inet passwall2 | grep white
  nft flush set inet passwall2 psw2_rulenode_white; /etc/init.d/dnsmasq restart; /etc/init.d/passwall2 restart
  ```
  То же самое делает кнопка **«Очистить NFTSet»** на вкладке DNS.
- **Нет пакетов под архитектуру** — проверить, что собрано:
  https://sourceforge.net/projects/openwrt-passwall-build/files/releases/packages-25.12/
- **`apk update` не видит штатный фид** (лёг `downloads.openwrt.org`) — сменить зеркало:
  ```sh
  sed -i 's|https://downloads.openwrt.org/|https://mirror-03.infra.openwrt.org/|' /etc/apk/repositories.d/distfeeds.list; apk update
  ```
- **Не хватает места** — снести старое решение вместе с sing-box (~42 МБ):
  ```sh
  apk del luci-app-netshift netshift sing-box
  ```
- **Zapret не качается даже через туннель** — скачать zip с
  https://github.com/remittor/zapret-openwrt/releases на ПК, залить в `/tmp/zapret_temp` и:
  ```sh
  cd /tmp/zapret_temp && apk add unzip && unzip -o zapret_v*.zip
  for p in apk/zapret*; do case "$p" in *luci*) continue;; esac; apk add --allow-untrusted "$p"; done
  for p in apk/luci*; do apk add --allow-untrusted "$p"; done
  ```
