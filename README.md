# Списки доменов для PassWall2

Каждый файл — готовое содержимое одного правила PassWall2. Копируется целиком:
строки с `#` PassWall2 считает комментариями.

## После любого изменения правил

```sh
/etc/init.d/passwall2 restart
```

LuCI службу не перечитывает — `reload` в её init-скрипте заглушка. Без этой команды
Save & Apply сохранит конфиг, но работать будет старый.

Если домен **переехал** из прямых в проксируемые — ещё и почистить nft-набор,
иначе старые адреса (живут 365 дней) продолжат обходить туннель:

```sh
nft flush set inet passwall2 psw2_rulenode_white; /etc/init.d/dnsmasq restart; /etc/init.d/passwall2 restart
```

## Какие правила на каком роутере

| файл | правило | Ярослав | брат | остальные |
|---|---|:---:|:---:|:---:|
| `common.txt` | `common` | ✅ | ✅ | ✅ |
| `claude.txt` | `claude` | ✅ | ✅ | ✅ |
| `google_ai.txt` | `google_ai` | ✅ | по желанию | по желанию |
| `doxfie-personal.txt` | `personal` | ✅ | — | — |
| `evgen-personal.txt` | `personal` | — | ✅ | — |
| `telegram-fallback.txt` | — | только если пропадут geo-категории | | |

`claude` вынесен отдельно намеренно: так его можно направить на свою ноду, не трогая
остальной трафик. У Ярослава — на финскую, `common` — на немецкую.

`common.txt` и `telegram-fallback.txt` содержат **два блока**: домены в поле «Домен»,
подсети в поле «IP».

## Правила именования

Имя правила — это имя UCI-секции, поэтому только **буквы, цифры и подчёркивание**.
С дефисом кнопка «Добавить» молча не срабатывает.

Домены — с префиксом **`domain:`** («сам домен и все поддомены»). Без префикса это поиск
подстроки: голый `x.ai` поймает и `matrix.ai`, и `linux.ai`.

## Как добавить домен

1. Дописать `domain:example.com` в нужный файл
2. LuCI: **Управление правилами** → вкладка `RU` → `Edit` → заменить поле «Домен» → **Save & Apply**
3. Перезапустить службу — см. блок в начале
4. Убедиться, что новые правила в живом конфиге:
   ```sh
   grep -rl 'geosite:telegram' /tmp/etc/passwall2/ 2>/dev/null
   ```
   Пусто — конфиг не пересобрался.

## Geo-категории вместо списков

Проверять наличие и состав — вкладка **«Просмотр Geo»**, поле «Запрос GeoIP/Geosite».
Первое поле работает наоборот: вводишь домен, получаешь категории, в которые он входит.

Используется сейчас: `geosite:telegram` + `geoip:telegram`. Проверено 29.08.2026 —
состав совпадает с itdoginfo, а geoip даже полнее (есть `95.161.64.0/20` и IPv6).

Также используются `geosite:openai`, `geosite:spotify`, `geosite:whatsapp`.

Две категории **неполные**, рядом с ними нужны ручные строки:

| категория | чего не хватает |
|---|---|
| `geosite:openai` | `domain:cdn.auth0.com` — логин |
| `geosite:whatsapp` | `domain:whatsapp.fbsbx.com` — CDN для медиа |

Проверено 29.08.2026, что брать НЕ надо:

| категория | почему нет |
|---|---|
| `geosite:github` | тянет `github.io` (все GitHub Pages) и `npmjs.com/org`. Ручные 5 строк точнее, `githubusercontent.com` уже покрывает `release-assets` |
| `geosite:docker` | тянет весь `docker.com`/`docker.io`, нужен только `auth.docker.io` |
| `geosite:google` | весь Google целиком, для `google_ai` замены не существует |

Менять есть смысл там, где список длинный и живёт своей жизнью. Для коротких кураторских
наборов (Claude — 3 домена, Figma — 1) geosite добавляет зависимость без выигрыша.

## На что обратить внимание

- **IPv6 у Telegram.** В `geoip:telegram` есть v6-диапазоны, но PassWall2 перехватывает
  только IPv4. Клиент, ушедший к Telegram по IPv6, пойдёт мимо туннеля — а Telegram в РФ
  ограничен. Лечится либо «IPv6 TProxy» в «Дополнительных настройках», либо `unreachable`
  маршрутами на эти диапазоны, чтобы клиенты откатывались на IPv4.
- **`ipinfo.io` в `common`** идёт через туннель — проверять им «прямой» IP нельзя,
  для этого `ifconfig.me/ip`.
- **`s3.us-west-2.amazonaws.com` в `evgen-personal`** — общий бакет AWS, в туннель уйдёт
  не только принтер Bambu.
- **`as-filter-upgrade.huan.tv` в `doxfie-personal`** — только доменом. Гео-DNS: из России уводит
  на `ru-filter-upgrade.huan.tv`, где TLS падает.

## Откуда взято

- `common` и оба personal — из подкоповских списков (`D:\DoxfieVPN\Podkop\podkop-domains`)
- `google_ai`, `telegram-fallback` — [itdoginfo/allow-domains](https://github.com/itdoginfo/allow-domains), `Services/`
- GitHub-блок в `common` — появился из-за блокировки `release-assets.githubusercontent.com`
