# Zapret + PassWall2 на OpenWrt 25.12

Настройка **Zapret** (обход DPI) и **PassWall2** (маршрутизация трафика через VPN)
на чистом роутере с **OpenWrt 25.12**.

> [!NOTE]
> Гайд написан строго под **25.12**: пакетный менеджер **apk** (opkg в 25.12 больше нет),
> фаервол **fw4/nftables**. На 24.10 и старше команды не подойдут.

---

## 🔧 Предварительные условия

- Роутер на **OpenWrt 25.12**
- Доступ по **SSH** к роутеру
- Интернет работает **на самом роутере**
- Свободно в `/overlay` — **не менее 15 МБ**

Проверить, что версия та и место есть:

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

> [!WARNING]
> Если одна из стратегий **Zapret** не работает на **ПК с Windows**, выполнить в **PowerShell**:
>
> ```powershell
> netsh int tcp set global timestamps=enabled
> ```

---

## 🧨 Шаг 1. Установка Zapret

Ставим **первым**, до PassWall2.

```sh
sh <(wget -O - https://raw.githubusercontent.com/StressOzz/Zapret-Manager/main/Zapret-Manager.sh)
```

Появится меню: выбрать пункт цифрой, нажать **Enter**, следовать подсказкам.

Проект: https://github.com/StressOzz/Zapret-Manager

> [!NOTE]
> Zapret живёт в nftables-таблице `inet zapret`, PassWall2 — в `inet passwall2`, фаервол —
> в `inet fw4`. Друг друга они не трогают, но нужна одна галка в PassWall2, иначе Zapret
> тихо перестанет делать своё дело — см. [шаг 5.1](#51-создать-shunt-узел).

---

## 📦 Шаг 2. Подключение репозитория PassWall2

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

Должен найтись `xray-core-26.7.28` или новее. Если пусто — фиды не подключились,
смотреть вывод `apk update` на ошибки подписи.

---

## ⬇️ Шаг 3. Установка PassWall2

Сначала посмотреть, сколько это займёт — команда ничего не меняет:

```sh
apk add --simulate luci-app-passwall2 luci-i18n-passwall2-ru xray-core tcping
```

Сравнить итоговый размер со свободным местом из `df -h /overlay`. Если влезает — ставим:

```sh
apk add luci-app-passwall2 luci-i18n-passwall2-ru xray-core tcping
```

| пакет | зачем |
|---|---|
| `luci-app-passwall2` | сам PassWall2 + веб-интерфейс |
| `luci-i18n-passwall2-ru` | русский перевод интерфейса |
| `xray-core` | **ядро**. Именно xray, не sing-box — см. [почему](#-почему-passwall2-а-не-podkop) |
| `tcping` | проверка доступности нод из интерфейса |

Зависимости (`kmod-nft-tproxy`, `lua`, `ip-full` и прочее) apk подтянет из штатного фида сам.

> [!IMPORTANT]
> **`geoview`, `v2ray-geoip`, `v2ray-geosite` не ставить** — это +10 МБ ради готовых
> geo-списков (`geosite:google`, `geoip:cn`). При маршрутизации по своим доменам и подсетям
> они не нужны. Поставить можно в любой момент позже.

После установки: LuCI → **Службы → PassWall2**.

---

## 🌐 Шаг 4. Добавление ноды (VPN-сервера)

### Вариант А: одна ссылка

**Службы → PassWall2 → Список узлов → Добавить** → вставить ссылку `vless://…`.

### Вариант Б: подписка (если серверов несколько)

**Службы → PassWall2 → Подписки → Добавить**, вставить URL подписки.

> [!WARNING]
> Панель должна отдать **base64-список ссылок**, а не JSON-конфиг: PassWall2 парсит только
> ссылки. Формат панели выбирают по `User-Agent`, поэтому в настройках подписки заполнить
> поле **User-Agent** (например `v2rayN`). Список узлов пустой после обновления подписки —
> прилетел не тот формат.

Правила маршрутизации из подписки **не импортируются** — PassWall2 собирает конфиг xray
сам, из подписки берутся только параметры серверов. Свои правила из шага 5 ничего не перетрут.

Проверить ноду: в списке узлов нажать проверку задержки (работает через `tcping`).

---

## 🚦 Шаг 5. Разделение трафика (Shunt)

Ядро настройки: гнать в VPN **только нужное**, всё остальное отдавать напрямую,
чтобы им занимался Zapret.

### 5.1. Создать Shunt-узел

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

### 5.2. Создать правила

**PassWall2 → Правила разделения трафика → Добавить**. Одно правило — одна группа сервисов.

Правило для доменов:

| поле | значение |
|---|---|
| Примечание | `my-domains` |
| Домены | список, по одному в строке |

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

### 5.3. Привязать правила к ноде

Вернуться в настройки Shunt-узла — там появились строки, по одной на каждое правило.
Напротив нужных выбрать VPN-ноду, напротив остальных оставить **Прямое соединение**.

### 5.4. Включить

**PassWall2 → Основные настройки**:

| параметр | значение |
|---|---|
| **Основной узел** | созданный Shunt-узел |
| Включить | ✅ |

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

## ✅ Шаг 6. Проверка

Обе службы на месте и не пересекаются:

```sh
nft list tables | grep -E 'passwall2|zapret'
```

«Прямой» набор наполняется:

```sh
nft list sets inet passwall2 | grep white
```

Ядро запущено:

```sh
pgrep -a xray
```

С клиента в LAN:

1. Открыть сайт **из** списка → проверить IP на https://ipinfo.io — должен быть IP ноды.
2. Открыть сайт **не из** списка → IP должен быть домашний.
3. Проверить обход DPI: https://hyperion-cs.github.io/dpi-checkers/ru/tcp-16-20/ → **Start**.

Логи: **Службы → PassWall2 → Журнал**.

---

## 🔄 Обновление

```sh
apk update && apk upgrade
```

Отдельно ядро — обновлять стоит, от версии xray зависит совместимость с сервером:

```sh
apk add -u xray-core
```

Проверить, что версия сменилась:

```sh
apk list -I xray-core
```

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
- правила по источнику (телевизор — в один VPN, ноутбук — в другой);
- цепочки прокси, балансировка, подписки;
- проект живой — десятки коммитов в месяц против одного у Podkop.

Минусы, честно:

- интерфейс сложнее и переведён не целиком, часть подсказок на английском;
- по умолчанию перехватывает весь трафик — нужна галка из [шага 5.1](#51-создать-shunt-узел);
- проект китайский, дефолты и готовые списки заточены под Китай — свои списки вести самому.

---

## 📎 Краткие команды

```sh
# Zapret
sh <(wget -O - https://raw.githubusercontent.com/StressOzz/Zapret-Manager/main/Zapret-Manager.sh)

# Репозиторий PassWall2
. /etc/openwrt_release
B="https://master.dl.sourceforge.net/project/openwrt-passwall-build"
R="25.12"; A="$DISTRIB_ARCH"
wget -O /etc/apk/keys/passwall.pub "$B/apk.pub"
for f in passwall_packages passwall_luci passwall2; do
  echo "$B/releases/packages-$R/$A/$f/packages.adb"
done >> /etc/apk/repositories.d/customfeeds.list
apk update

# Установка PassWall2
apk add luci-app-passwall2 luci-i18n-passwall2-ru xray-core tcping

# Проверка
df -h /overlay
nft list tables | grep -E 'passwall2|zapret'
pgrep -a xray
```

---

## 🔗 Ссылки

- PassWall2: https://github.com/Openwrt-Passwall/openwrt-passwall2
- Сборки под 25.12: https://sourceforge.net/projects/openwrt-passwall-build/files/releases/packages-25.12/
- Zapret-Manager: https://github.com/StressOzz/Zapret-Manager
- Проверка DPI: https://hyperion-cs.github.io/dpi-checkers/ru/tcp-16-20/
