# PassWall2 + Zapret на OpenWrt 25.12

Настройка **PassWall2** (маршрутизация трафика через VPN) и **Zapret** (обход DPI) на чистом роутере с **OpenWrt 25.12**.

Заменяет связку Zapret + Podkop. Почему — см. [«Почему PassWall2, а не Podkop»](#-почему-passwall2-а-не-podkop).

> [!IMPORTANT]
> **Порядок важен: сначала PassWall2, потом Zapret.**
>
> С 27.08.2026 у ряда провайдеров (в первую очередь Ростелеком) заблокированы по IP четыре
> Fastly-адреса `185.199.108–111.133` — это `raw.githubusercontent.com`,
> `release-assets.githubusercontent.com` и весь `*.githubusercontent.com`. Пинг не проходит,
> TCP уходит в таймаут. Zapret тут **не поможет**: это не DPI, а блокировка маршрута —
> обходить нечего, пакеты просто не доходят. Записи в `hosts` тоже бесполезны, потому что
> заблокированы сами адреса.
>
> Zapret-Manager качает архив с GitHub Releases → без VPN установка не проходит.
> Поэтому первым поднимаем туннель, а Zapret ставим уже через него.
>
> Пакеты PassWall2 лежат на SourceForge (`216.105.38.12`, своя сеть) — под блокировку
> не попадают.

> [!NOTE]
> Гайд написан строго под **25.12**: пакетный менеджер **apk** (opkg в 25.12 больше нет),
> фаервол **fw4/nftables**. На 24.10 и старше команды не подойдут.

---

## 🔧 Предварительные условия

- Роутер на **OpenWrt 25.12**
- Доступ по **SSH** к роутеру
- Интернет работает **на самом роутере**
- Свободно в `/overlay` — **не менее 15 МБ**
- Ссылка на VPN-ноду (`vless://…`) или URL подписки — **под рукой заранее**

```sh
. /etc/openwrt_release; echo "$DISTRIB_RELEASE / $DISTRIB_ARCH"; apk --version; df -h /overlay
```

Ожидаем `25.12.x`, свою архитектуру и `apk-tools 3.x`.

<details>
<summary>Мои роутеры — для сверки</summary>

| роутер | архитектура | `/overlay` всего |
|---|---|---|
| Cudy WR3000E v1 (mediatek/filogic) | `aarch64_cortex-a53` | 44 МБ |

</details>

---

## 🩺 Шаг 0. Проверка связности

Выясняем, что вообще доступно с роутера. Три команды:

```sh
wget -q -O /dev/null "https://master.dl.sourceforge.net/project/openwrt-passwall-build/apk.pub" && echo "sourceforge OK" || echo "sourceforge BLOCKED"
wget -q -O /dev/null "https://downloads.openwrt.org/releases/" && echo "openwrt OK" || echo "openwrt BLOCKED"
wget -q -T 5 -O /dev/null "https://raw.githubusercontent.com/StressOzz/Zapret-Manager/main/Zapret-Manager.sh" && echo "github OK" || echo "github BLOCKED"
```

| результат | что делать |
|---|---|
| `sourceforge OK` | идём дальше, PassWall2 поставится |
| `openwrt BLOCKED` | сначала [шаг 1](#-шаг-1-зеркало-openwrt-если-нужно) |
| `github BLOCKED` | ожидаемо, лечится туннелем на [шаге 5](#-шаг-5-временно-весь-роутер-через-vpn) |
| `sourceforge BLOCKED` | плохо: качать пакеты на ПК под VPN и заливать `scp` вручную |

---

## 🪞 Шаг 1. Зеркало OpenWrt (если нужно)

Только если шаг 0 дал `openwrt BLOCKED`. Зависимости PassWall2 (`kmod-nft-tproxy`, `unzip`
и прочее) тянутся из штатного фида, поэтому он должен работать.

Проверенные под 25.12 зеркала:

```sh
for m in mirror-03.infra.openwrt.org ftp.snt.utwente.nl/pub/software/openwrt mirror.sjtu.edu.cn/openwrt; do
  printf '%s ' "$m"; wget -q -T 5 -O /dev/null "https://$m/releases/" && echo OK || echo FAIL
done
```

Переключиться на первое, которое ответило `OK`:

```sh
cp /etc/apk/repositories.d/distfeeds.list /etc/apk/repositories.d/distfeeds.list.bak
sed -i 's|https://downloads.openwrt.org/|https://mirror-03.infra.openwrt.org/|' /etc/apk/repositories.d/distfeeds.list
apk update
```

Вернуть обратно, когда блокировка спадёт:

```sh
mv /etc/apk/repositories.d/distfeeds.list.bak /etc/apk/repositories.d/distfeeds.list; apk update
```

---

## 📦 Шаг 2. Репозиторий PassWall2

В фидах OpenWrt пакета нет — подключаем репозиторий проекта.
Релиз фиксирован (`25.12`), архитектура подставится сама.

```sh
. /etc/openwrt_release
B="https://master.dl.sourceforge.net/project/openwrt-passwall-build"
R="25.12"
A="$DISTRIB_ARCH"
```

> [!TIP]
> `R` — это **ветка** релиза, а не точная версия. На 25.12.5 путь всё равно `packages-25.12`.

Проверить, что под вашу архитектуру пакеты собраны:

```sh
wget -q -O /dev/null "$B/releases/packages-$R/$A/passwall2/packages.adb" && echo "репозиторий есть" || echo "СБОРОК НЕТ"
```

> [!WARNING]
> «СБОРОК НЕТ» — под эту архитектуру пакетов не собрано.
> Что вообще есть: https://sourceforge.net/projects/openwrt-passwall-build/files/releases/packages-25.12/

Ключ подписи и фиды:

```sh
wget -O /etc/apk/keys/passwall.pub "$B/apk.pub"
for f in passwall_packages passwall_luci passwall2; do
  echo "$B/releases/packages-$R/$A/$f/packages.adb"
done >> /etc/apk/repositories.d/customfeeds.list
apk update
```

Проверить, что фиды подхватились:

```sh
apk search xray-core
```

Должен найтись `xray-core-26.7.28` или новее. Пусто — смотреть вывод `apk update` на ошибки.

---

## ⬇️ Шаг 3. Установка PassWall2

Сначала посмотреть, сколько это займёт — команда ничего не меняет:

```sh
apk add --simulate luci-app-passwall2 luci-i18n-passwall2-ru xray-core tcping
```

Сравнить со свободным местом из `df -h /overlay`. Если влезает — ставим:

```sh
apk add luci-app-passwall2 luci-i18n-passwall2-ru xray-core tcping
```

| пакет | зачем |
|---|---|
| `luci-app-passwall2` | сам PassWall2 + веб-интерфейс |
| `luci-i18n-passwall2-ru` | русский перевод интерфейса |
| `xray-core` | **ядро**. Именно xray, не sing-box — см. [почему](#-почему-passwall2-а-не-podkop) |
| `tcping` | проверка доступности нод из интерфейса |

> [!IMPORTANT]
> **`geoview`, `v2ray-geoip`, `v2ray-geosite` не ставить** — это +10 МБ ради готовых
> geo-списков (`geosite:google`, `geoip:cn`). При маршрутизации по своим доменам и подсетям
> они не нужны. Поставить можно в любой момент позже.

После установки: LuCI → **Службы → PassWall2**.

---

## 🌐 Шаг 4. Добавление ноды

### Вариант А: одна ссылка

**Службы → PassWall2 → Список узлов → Добавить** → вставить ссылку `vless://…`.

### Вариант Б: подписка

**Службы → PassWall2 → Подписки → Добавить**, вставить URL подписки.

> [!WARNING]
> Панель должна отдать **base64-список ссылок**, а не JSON-конфиг: PassWall2 парсит только
> ссылки. Формат панели выбирают по `User-Agent`, поэтому заполнить в настройках подписки
> поле **User-Agent** (например `v2rayN`). Список узлов пустой после обновления —
> прилетел не тот формат.

Правила маршрутизации из подписки **не импортируются** — PassWall2 собирает конфиг xray сам,
из подписки берутся только параметры серверов.

Проверить ноду: в списке узлов нажать проверку задержки (работает через `tcping`).

---

## 🔓 Шаг 5. Временно: весь роутер через VPN

Это временный режим, нужный ровно для того, чтобы поставить Zapret и всё остальное с GitHub.

**PassWall2 → Основные настройки**, вкладка **Main**:

| параметр | значение |
|---|---|
| Включить | ✅ |
| **Основной узел** | ваша VPN-нода (пока **не** Shunt) |
| **Прокси для самого роутера** | ✅ **включить** |

> [!NOTE]
> «Прокси для самого роутера» (`localhost_proxy`) — то, чего принципиально не умеет
> Podkop/NetShift: PassWall2 вешает свои цепочки ещё и на `output`, поэтому через туннель
> идёт трафик самого роутера, а не только клиентов. Именно на этом держится вся схема.

Сохранить и применить. Проверить, что роутер вышел через ноду:

```sh
wget -q -O - https://ipinfo.io/ip; echo
```

Должен показать IP ноды. Показывает домашний — туннель не поднялся, дальше идти нет смысла.

---

## 🧨 Шаг 6. Установка Zapret

Теперь GitHub доступен через туннель, и установщик отработает штатно.

```sh
sh <(wget -O - https://raw.githubusercontent.com/StressOzz/Zapret-Manager/main/Zapret-Manager.sh)
```

Появится меню: установка Zapret — пункт **`1`**. Стратегии — пункт **`3`**.

Проект: https://github.com/StressOzz/Zapret-Manager

<details>
<summary>Если Zapret всё-таки не качается</summary>

Значит туннель не покрывает загрузку. Запасные пути, по убыванию удобства:

**Через прокси-режим самого скрипта.** У Zapret-Manager есть фолбэк на `gh-proxy.org`,
включается сам, если недоступен `raw.githubusercontent.com`. Имитируем недоступность:

```sh
wget -O /tmp/zms.sh https://raw.githubusercontent.com/StressOzz/Zapret-Manager/main/Zapret-Manager.sh
printf '#zmproxy\n127.0.0.1 raw.githubusercontent.com\n' >> /etc/hosts
/etc/init.d/dnsmasq restart
sh /tmp/zms.sh
```

Скрипт напишет «недоступен — используем прокси». **После установки откатить:**

```sh
sed -i '/#zmproxy/,+1d' /etc/hosts; /etc/init.d/dnsmasq restart
```

**Руками из файла.** Скачать zip на ПК под VPN
(`github.com/remittor/zapret-openwrt/releases`), залить и поставить:

```sh
mkdir -p /tmp/zapret_temp
# с ПК: scp zapret_v*_<арх>.zip root@192.168.1.1:/tmp/zapret_temp/
cd /tmp/zapret_temp && apk add unzip && unzip -o zapret_v*.zip
for p in apk/zapret*; do case "$p" in *luci*) continue;; esac; apk add --allow-untrusted "$p"; done
for p in apk/luci*; do apk add --allow-untrusted "$p"; done
```

Стратегии потом через меню скрипта (пункт `3`).

> [!WARNING]
> Пункт `0` → `11) githubusercontent.com` (записи в `hosts`) при блокировке по IP
> **не работает** — заблокированы сами адреса `185.199.108–111.133`, а других у этих
> доменов нет. Не тратить на него время.

</details>

---

## 🚦 Шаг 7. Боевая схема разделения трафика

Переключаемся с временного «всё через VPN» на нормальный режим: в туннель — только нужное,
остальное напрямую, чтобы им занимался Zapret.

### 7.1. Создать Shunt-узел

**Список узлов → Добавить**, тип узла — **Shunt (разделение трафика)**.

| параметр | значение |
|---|---|
| **По умолчанию** | **Прямое соединение** |
| **Записывать результаты прямого DNS в IPSet** | ✅ **включить** |

> [!CAUTION]
> Галка «Записывать результаты прямого DNS в IPSet» — **обязательная**, если рядом Zapret.
>
> Без неё PassWall2 заворачивает в xray **весь** TCP-трафик и уже сам решает, что пустить
> напрямую. Формально работает, но наружу выходит поток процесса xray, а не клиента —
> Zapret обрабатывает не то, и вдобавок весь домашний трафик упирается в одно ядро.
>
> С галкой IP-адреса «прямых» доменов пишутся в nftables-набор `psw2_<узел>_white`,
> а он в цепочке стоит **раньше** правила перехвата и делает `return`. Прямой трафик уходит
> в WAN обычным форвардом — ровно так, как Zapret ждёт.

### 7.2. Создать правила

**PassWall2 → Правила разделения трафика → Добавить**. Одно правило — одна группа сервисов.

**Обязательное правило — инфраструктура.** Иначе следующее обновление Zapret, списков или
пакетов снова упрётся в блокировку:

| поле | значение |
|---|---|
| Примечание | `infra` |
| Домены | см. ниже |

```text
domain:github.com
domain:githubusercontent.com
domain:githubassets.com
domain:openwrt.org
domain:sourceforge.net
```

Правило для своих доменов:

```text
domain:example.com     # сам домен и все поддомены (рекомендуется)
full:example.com       # только точное совпадение
example.com            # подстрока: попадёт и example.com.ru
regexp:\.goo.*\.com$   # регулярное выражение
geosite:google         # готовый список (нужен пакет v2ray-geosite)
```

Правило для подсетей (Telegram и прочее, что ходит по IP без доменов):

| поле | значение |
|---|---|
| Примечание | `telegram` |
| IP | подсети, по одной в строке |

```text
91.108.4.0/22
91.108.8.0/21
91.108.16.0/21
91.108.56.0/22
149.154.160.0/20
185.76.151.0/24
```

> [!TIP]
> Правила с **IP** отрабатывают на уровне nftables, ещё до захода в xray — быстрее доменных.
> Всё, что известно подсетями, задавать подсетями.

### 7.3. Привязать правила к ноде

Вернуться в настройки Shunt-узла — там появились строки, по одной на каждое правило.
Напротив нужных выбрать VPN-ноду, напротив остальных оставить **Прямое соединение**.

### 7.4. Переключиться на Shunt

**PassWall2 → Основные настройки**:

| параметр | значение |
|---|---|
| **Основной узел** | созданный Shunt-узел |
| **Прокси для самого роутера** | ✅ оставить включённым |

Вкладка **DNS**:

| параметр | значение |
|---|---|
| **Прямой DNS** | `77.88.8.8` (или DNS провайдера) |
| **Прокси-DNS** | `1.1.1.1` |
| **FakeDNS** | ✅ включить |

> [!TIP]
> **FakeDNS** включить: домены, идущие в прокси, разрешаются на выходной ноде, а не локально.
> Это обходит гео-DNS — когда сервис из России отдаёт один IP, а из-за границы другой,
> рабочий. Прямых доменов FakeDNS не касается, связку с Zapret не ломает.

Сохранить и применить.

---

## ✅ Шаг 8. Проверка

Обе службы на месте и не пересекаются:

```sh
nft list tables | grep -E 'passwall2|zapret'
```

«Прямой» набор наполняется, ядро запущено:

```sh
nft list sets inet passwall2 | grep white
pgrep -a xray
```

Инфраструктура ходит через туннель — команда должна вернуть IP ноды:

```sh
wget -q -O - https://ipinfo.io/ip; echo
```

С клиента в LAN:

1. Сайт **из** списка → IP на https://ipinfo.io должен быть IP ноды.
2. Сайт **не из** списка → IP должен быть домашний.
3. Обход DPI: https://hyperion-cs.github.io/dpi-checkers/ru/tcp-16-20/ → **Start**.

Логи: **Службы → PassWall2 → Журнал**.

> [!WARNING]
> Если одна из стратегий **Zapret** не работает на **ПК с Windows**, выполнить в **PowerShell**:
>
> ```powershell
> netsh int tcp set global timestamps=enabled
> ```

---

## 🔄 Обновление

```sh
apk update && apk upgrade
```

Отдельно ядро — от версии xray зависит совместимость с сервером:

```sh
apk add -u xray-core
apk list -I xray-core
```

Zapret — через меню скрипта, пункт `1` (переустановит поверх).

---

## 💾 Если не хватает места

`xray-core` — ~11 МБ в упаковке. Варианты:

1. **Снести предыдущее решение.** Вместе с Podkop или NetShift уходит `sing-box` (~42 МБ):
   ```sh
   apk del luci-app-netshift netshift sing-box
   ```
   ```sh
   apk del luci-app-podkop podkop sing-box
   ```
2. **Не ставить geo-пакеты** — см. предупреждение в шаге 3.
3. **Extroot на USB**, если у роутера есть порт.

> [!CAUTION]
> Снос `sing-box` **до** установки xray убирает путь отката на самом роутере: вернуть старое
> получится только с рабочим интернетом или перепрошивкой. Делать, находясь рядом с роутером.

---

## 🗑 Удаление

```sh
/etc/init.d/passwall2 stop
apk del luci-app-passwall2 luci-i18n-passwall2-ru xray-core tcping
rm -f /etc/config/passwall2 /etc/config/passwall2_server
sed -i '/openwrt-passwall-build/d' /etc/apk/repositories.d/customfeeds.list
rm -f /etc/apk/keys/passwall.pub
/etc/init.d/dnsmasq restart
```

---

## ❓ Почему PassWall2, а не Podkop

**Podkop и NetShift намертво завязаны на `sing-box`** — выбора ядра там нет.
А sing-box отправляет серверу REALITY **зашитую константу версии `1.8.1`**
(`common/tls/reality_client.go`) независимо от собственной версии.

С июля 2026 Xray-сервер по умолчанию отсекает клиентов старее `26.3.27`
([коммит af7eb68](https://github.com/XTLS/Xray-core/commit/af7eb68028)): у старых ядер
устаревший TLS-отпечаток, по которому DPI вычисляет сервер целиком. Обновление sing-box
не спасает — это константа, а не отчёт о версии.

Итог: как только на сервере убирают `minClientVer: "0.0.0"`, любой роутер на sing-box
перестаёт работать — причём **молча**: REALITY уводит отвергнутого клиента на маскировочный
сайт, и выглядит это как «подключено, но интернета нет».

PassWall2 работает на **xray-core**, который отдаёт настоящую версию. Плюс:

- ядро выбирается явно, обновляется отдельно от прошивки;
- **проксируется трафик самого роутера** — без этого установка чего-либо с GitHub сейчас
  невозможна;
- правила по источнику (телевизор — в один VPN, ноутбук — в другой);
- цепочки прокси, балансировка, подписки;
- проект живой — десятки коммитов в месяц против одного у Podkop.

Минусы, честно:

- интерфейс сложнее и переведён не целиком, часть подсказок на английском;
- по умолчанию перехватывает весь трафик — нужна галка из [шага 7.1](#71-создать-shunt-узел);
- проект китайский, дефолты и готовые списки заточены под Китай — свои списки вести самому.

---

## 📎 Краткие команды

```sh
# 0. Проверка связности
wget -q -O /dev/null "https://master.dl.sourceforge.net/project/openwrt-passwall-build/apk.pub" && echo "sourceforge OK" || echo "sourceforge BLOCKED"
wget -q -O /dev/null "https://downloads.openwrt.org/releases/" && echo "openwrt OK" || echo "openwrt BLOCKED"

# 1. Зеркало OpenWrt, если нужно
sed -i 's|https://downloads.openwrt.org/|https://mirror-03.infra.openwrt.org/|' /etc/apk/repositories.d/distfeeds.list; apk update

# 2. Репозиторий PassWall2
. /etc/openwrt_release
B="https://master.dl.sourceforge.net/project/openwrt-passwall-build"
R="25.12"; A="$DISTRIB_ARCH"
wget -O /etc/apk/keys/passwall.pub "$B/apk.pub"
for f in passwall_packages passwall_luci passwall2; do
  echo "$B/releases/packages-$R/$A/$f/packages.adb"
done >> /etc/apk/repositories.d/customfeeds.list
apk update

# 3. Установка PassWall2
apk add luci-app-passwall2 luci-i18n-passwall2-ru xray-core tcping

# 4-5. Нода + «Прокси для самого роутера» — через LuCI, затем проверка:
wget -q -O - https://ipinfo.io/ip; echo

# 6. Zapret (уже через туннель)
sh <(wget -O - https://raw.githubusercontent.com/StressOzz/Zapret-Manager/main/Zapret-Manager.sh)

# 8. Проверка
df -h /overlay
nft list tables | grep -E 'passwall2|zapret'
pgrep -a xray
```

---

## 🔗 Ссылки

- PassWall2: https://github.com/Openwrt-Passwall/openwrt-passwall2
- Сборки под 25.12: https://sourceforge.net/projects/openwrt-passwall-build/files/releases/packages-25.12/
- Zapret-Manager: https://github.com/StressOzz/Zapret-Manager
- Архивы Zapret: https://github.com/remittor/zapret-openwrt/releases
- Проверка DPI: https://hyperion-cs.github.io/dpi-checkers/ru/tcp-16-20/
- Блокировка githubusercontent 27.08.2026: https://github.com/StressOzz/Zapret-Manager/issues/1023
