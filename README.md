# PassWall2 + Zapret на OpenWrt

Гайд по настройке **PassWall2** и **Zapret** на роутере с OpenWrt: точечная маршрутизация через VPN плюс обход DPI.

---

## 🔧 Предварительные условия

- Роутер на **OpenWrt 25.12** или новее (пакетный менеджер **apk**)
- Доступ по **SSH** к роутеру
- Интернет работает **на самом роутере**
- Свободно **≥25 МБ** в `/overlay`
- Ссылка на подписку или на ноду (`vless://…`)

> [!IMPORTANT]
> **Порядок важен: сначала PassWall2, потом Zapret.** Zapret-Manager качает архив с GitHub Releases, а `release-assets.githubusercontent.com` у части российских провайдеров не открывается. Пакеты PassWall2 лежат на SourceForge и доступны всегда — поэтому сначала туннель, Zapret через него.

---

## 🌉 Установка PassWall2

Скрипт ставит PassWall2 со всеми зависимостями, поднимает DoH-резолвер и готовит базовую конфигурацию. Подписку и правила он не трогает — их добавите сами.

```sh
sh <(wget -O - https://raw.githubusercontent.com/doxfie-guides/openwrt-zapret-passwall2-guide/main/install.sh)
```

Что делает:

- подключает репозиторий PassWall2, ставит `luci-app-passwall2`, `xray-core` и нужные `kmod`-ы
- при необходимости меняет `dnsmasq` на `dnsmasq-full` — штатный собран без `nftset`, а на нём держится связка с Zapret
- ставит `https-dns-proxy` и поднимает три инстанса DoH. **Без своего DNS часть сайтов не откроется даже с рабочим Zapret**: провайдеры подменяют ответы, и соединение просто не создаётся
- прописывает DoH в WAN и создаёт Shunt-узел с «По умолчанию → Прямое соединение»
- проверяет, что DNS и интернет живы

После него роутер работает как обычно, весь трафик идёт напрямую.

---

## 🖐 Настройка руками

Скрипт не знает вашу подписку, поэтому два шага остаются в веб-интерфейсе.

**1. Подписка.** LuCI → **Services → PassWall 2 → Подписки → Добавить**. Поле **User-Agent** оставить `v2rayN`, иначе панель отдаст JSON вместо списка ссылок. Save & Apply, затем **обязательно** «Ручное обновление подписки» — само не подтянется.

Одиночную ноду можно добавить через **Список узлов → Добавить узел по ссылке**.

**2. Правила.** Вкладка **«Управление правилами»**, внизу страницы. Готовый базовый набор — [rules/common.txt](rules/common.txt): GitHub, Telegram, WhatsApp, OpenAI, Spotify и прочее. В поле **Домен** идёт всё, кроме блока `geoip:`, — он вставляется в отдельное поле **IP**.

GitHub и SourceForge в наборе не случайны: без них следующее обновление упрётся в блокировку.

Домены **обязательно с префиксом `domain:`** — голый `x.ai` это поиск подстроки, поймает и `matrix.ai`. Имя правила только из букв, цифр и подчёркиваний: с дефисом кнопка «Добавить» молча не сработает.

**3. Привязка.** **Общие параметры → Правила разделения трафика** → напротив правил выбрать ноду, затем Save & Apply.

Перезапускать вручную не нужно: скрипт перерегистрирует `ucitrack`, и Save & Apply сам дёргает PassWall2. Проверить, что триггер на месте:

```sh
ubus call service list '{"name":"ucitrack","verbose":true}' | grep -c passwall2
```

Ноль означает, что триггера нет — тогда `/etc/init.d/ucitrack restart` один раз, и дальше всё автоматически.

> [!NOTE]
> Если ставили PassWall2 руками, без скрипта, этот рестарт `ucitrack` обязателен. Триггеры регистрируются только при его старте, а на момент загрузки роутера PassWall2 ещё не было — поэтому Save & Apply молча ничего не перезапускает. Отсюда же частый совет «после любого изменения делайте restart вручную»: он лечит симптом, а не причину.
>
> Ручной перезапуск, если понадобится: **System → Startup → passwall2 → Restart** или `/etc/init.d/passwall2 restart`. Перезапускать нужно именно `passwall2` — соседний `passwall2_server` это режим «роутер как VPN-сервер», к клиентской части он отношения не имеет.

---

## 🧨 Установка Zapret

Теперь, когда туннель поднят, Zapret-Manager качается штатно:

```sh
sh <(wget -O - https://raw.githubusercontent.com/StressOzz/Zapret-Manager/main/Zapret-Manager.sh)
```

В меню: пункт **1** — установка, пункт **3** — стратегии.

Полное описание проекта: https://github.com/StressOzz/Zapret-Manager

> [!WARNING]
> Если стратегия Zapret не работает на **ПК с Windows**, выполните в **PowerShell**:
>
> ```powershell
> netsh int tcp set global timestamps=enabled
> ```

---

## 🧪 Проверка

```sh
curl -s -m 10 https://ifconfig.me/ip; echo "  <- прямой, ждём домашний IP"
curl -s -m 10 https://ipinfo.io/ip; echo "  <- проксируемый, ждём IP ноды"
```

`ipinfo.io` должен быть в проксируемом правиле, `ifconfig.me` — нет.

DPI-блокировки: https://hyperion-cs.github.io/dpi-checkers/ru/tcp-16-20/ — нажать **Start**. Удобно запускать до и после настройки, чтобы сравнить.

---

## 🔄 Обновление

**Ядро и списки Geo** — прямо в PassWall2, вкладка **«Обновление компонентов»**: там обновляются `xray-core`, `geoip` и `geosite`. После замены ядра PassWall2 перезапустится сам.

**Сам PassWall2 и остальные пакеты** — через **System → Software**: сначала `Update lists`, затем обновить нужные. По SSH то же самое:

```sh
apk update && apk upgrade
```

**Zapret** — через меню Zapret-Manager, той же командой, что и установка.

---

## 📎 Краткие команды

```sh
# 1. PassWall2 + DoH-резолвер
sh <(wget -O - https://raw.githubusercontent.com/doxfie-guides/openwrt-zapret-passwall2-guide/main/install.sh)

# 2. Zapret (после того, как поднят туннель)
sh <(wget -O - https://raw.githubusercontent.com/StressOzz/Zapret-Manager/main/Zapret-Manager.sh)

# перечитать настройки PassWall2
/etc/init.d/passwall2 restart
```

---

## 🩺 Если что-то не работает

Ручная установка по шагам и разбор частых симптомов: **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)**

Если сайт не открывается, а другие Zapret чинит, то чаще всего дело в стратегии: ТСПУ обновляется, и подобранная раньше стратегия перестаёт пробивать — нужно подобрать другую в меню Zapret-Manager. Реже виноват DNS, но с поднятым DoH-резолвером это уже маловероятно. Отличить просто: `nslookup <домен> 127.0.0.1` — если адрес реальный, DNS ни при чём.

---

## 🔗 Ссылки

- [PassWall2](https://github.com/Openwrt-Passwall/openwrt-passwall2) · [сборки](https://sourceforge.net/projects/openwrt-passwall-build/files/releases/)
- [Zapret-Manager](https://github.com/StressOzz/Zapret-Manager) · [архивы Zapret](https://github.com/remittor/zapret-openwrt/releases)
- [https-dns-proxy](https://github.com/aarond10/https_dns_proxy)
- [Проверка DPI](https://hyperion-cs.github.io/dpi-checkers/ru/tcp-16-20/)
