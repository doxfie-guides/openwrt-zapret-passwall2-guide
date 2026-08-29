# PassWall2 + Zapret на OpenWrt 25.12

Роутер: чистый OpenWrt 25.12 (пакетный менеджер `apk`), нужно ≥15 МБ в `/overlay`.

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
```

`25.12` — ветка релиза, на 25.12.5 путь тот же. Ядро — именно **xray**: sing-box отваливается
от `minClientVer` на сервере.

> [!TIP]
> `geoview`, `v2ray-geoip`, `v2ray-geosite` не ставить — +10 МБ ради китайских geo-списков,
> при маршрутизации по своим доменам не нужны.

---

## 2. Нода

**Службы → PassWall2 → Список узлов → Добавить** → вставить `vless://…`.

Если подписка — **Подписки → Добавить**, и заполнить поле **User-Agent** (`v2rayN`),
иначе панель отдаст JSON вместо списка ссылок и узлов не появится.

---

## 3. Временно: весь роутер через VPN

**Основные настройки**, вкладка **Main**:

- Включить — ✅
- **Основной узел** — сама нода (пока не Shunt)
- **Прокси для самого роутера** — ✅

Применить и проверить — должен вернуться IP ноды:

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

**Правила разделения трафика → Добавить.** Обязательное правило `infra`, иначе следующее
обновление снова упрётся в блокировку:

```text
domain:github.com
domain:githubusercontent.com
domain:githubassets.com
domain:openwrt.org
domain:sourceforge.net
```

Дальше свои правила: домены — `domain:example.com`, а что ходит по IP (Telegram) — подсетями
в поле **IP**, так быстрее:

```text
91.108.4.0/22
91.108.8.0/21
91.108.16.0/21
91.108.56.0/22
149.154.160.0/20
185.76.151.0/24
```

В настройках Shunt-узла напротив нужных правил выбрать ноду, остальные оставить **Прямое
соединение**.

Затем **Основные настройки** → **Основной узел** = Shunt-узел, «Прокси для самого роутера»
оставить включённым. Вкладка **DNS**: прямой `77.88.8.8`, прокси `1.1.1.1`, **FakeDNS** ✅.

---

## 6. Проверка

```sh
nft list tables | grep -E 'passwall2|zapret'
wget -q -O - https://ipinfo.io/ip; echo
```

С клиента: сайт из списка → IP ноды, сайт не из списка → домашний IP.
DPI: https://hyperion-cs.github.io/dpi-checkers/ru/tcp-16-20/

Логи — **Службы → PassWall2 → Журнал**.

---

## Если что-то не встало

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
