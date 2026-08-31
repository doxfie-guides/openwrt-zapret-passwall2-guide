#!/bin/sh
# PassWall2 + DoH-резолвер на OpenWrt 25.12 (apk)
# https://github.com/doxfie-guides/openwrt-zapret-passwall2-guide

set -e

DOH_PRIMARY="https://cloudflare-dns.com/dns-query"
DOH_SECONDARY="https://1.1.1.1/dns-query"
DOH_BOOTSTRAP="1.1.1.1,1.0.0.1,2606:4700:4700::1111,2606:4700:4700::1001"
DOH_SYS_ADDR="127.0.0.53"
DNS_FALLBACK="94.140.14.14"
FEED_BASE="https://master.dl.sourceforge.net/project/openwrt-passwall-build"
SHUNT="rulenode"

step() { echo; echo "[$1] $2"; }
die()  { echo; echo "ОШИБКА: $*" >&2; exit 1; }

# --- 0. Проверки -------------------------------------------------------------

[ "$(id -u)" = 0 ] || die "нужен root"
command -v apk >/dev/null 2>&1 || die "нет apk — скрипт только для OpenWrt 25.12+"
[ -f /etc/openwrt_release ] || die "это не OpenWrt"

. /etc/openwrt_release
BRANCH=$(echo "$DISTRIB_RELEASE" | cut -d. -f1,2)
case "$BRANCH" in
  25.12|26.*) : ;;
  *) die "скрипт рассчитан на 25.12+, у вас $DISTRIB_RELEASE" ;;
esac

FREE=$(df -k /overlay 2>/dev/null | awk 'NR==2{print int($4/1024)}')
[ -n "$FREE" ] || FREE=0
[ "$FREE" -ge 25 ] || die "в /overlay свободно ${FREE} МБ, нужно не меньше 25"

echo "OpenWrt $DISTRIB_RELEASE ($DISTRIB_ARCH), свободно ${FREE} МБ"

# --- 1. Репозиторий ----------------------------------------------------------

step 1/6 "Репозиторий PassWall2"
wget -q -O /etc/apk/keys/passwall.pub "$FEED_BASE/apk.pub" || die "не скачался ключ репозитория"
FEEDS=/etc/apk/repositories.d/customfeeds.list
touch "$FEEDS"
for f in passwall_packages passwall_luci passwall2; do
  URL="$FEED_BASE/releases/packages-$BRANCH/$DISTRIB_ARCH/$f/packages.adb"
  grep -qxF "$URL" "$FEEDS" || echo "$URL" >> "$FEEDS"
done
apk update >/dev/null 2>&1 || die "apk update не прошёл — проверьте интернет на роутере"

# --- 2. Пакеты ---------------------------------------------------------------

step 2/6 "Пакеты PassWall2"
apk add luci-app-passwall2 luci-i18n-passwall2-ru xray-core tcping >/dev/null
apk add kmod-nft-socket kmod-nft-tproxy kmod-nft-nat >/dev/null

if dnsmasq --version 2>/dev/null | grep -q no-nftset; then
  echo "  штатный dnsmasq собран без nftset — ставим dnsmasq-full"
  # apk кладёт свой /etc/config/dhcp, поэтому текущий сохраняем и возвращаем
  cp /etc/config/dhcp /tmp/dhcp.keep 2>/dev/null || true
  apk del dnsmasq >/dev/null 2>&1 || true
  apk add dnsmasq-full >/dev/null
  [ -f /tmp/dhcp.keep ] && mv /tmp/dhcp.keep /etc/config/dhcp
  /etc/init.d/dnsmasq restart >/dev/null 2>&1 || true
fi
/etc/init.d/rpcd restart >/dev/null 2>&1 || true

# --- 3. DoH-резолвер ---------------------------------------------------------

step 3/6 "DoH-резолвер"
apk add https-dns-proxy luci-app-https-dns-proxy >/dev/null

uci set https-dns-proxy.config.dnsmasq_config_update='0'
uci set https-dns-proxy.config.force_dns='0'

# [0] и [1] обслуживают прямой резолв PassWall2. Порты строго дефолтные:
# PassWall2 сам вписывает 127.0.0.1#5053 / #5054 в dns_default_direct.conf,
# и если увести прокси на другие порты, прямой резолв тихо сломается.
uci set https-dns-proxy.@https-dns-proxy[0].resolver_url="$DOH_PRIMARY"
uci set https-dns-proxy.@https-dns-proxy[0].bootstrap_dns="$DOH_BOOTSTRAP"
uci set https-dns-proxy.@https-dns-proxy[0].listen_addr='127.0.0.1'
uci set https-dns-proxy.@https-dns-proxy[0].listen_port='5053'
uci set https-dns-proxy.@https-dns-proxy[1].resolver_url="$DOH_SECONDARY"
uci set https-dns-proxy.@https-dns-proxy[1].bootstrap_dns="$DOH_BOOTSTRAP"
uci set https-dns-proxy.@https-dns-proxy[1].listen_addr='127.0.0.1'
uci set https-dns-proxy.@https-dns-proxy[1].listen_port='5054'

# [2] — системный резолвер роутера, на обычном порту
IDX=$(uci show https-dns-proxy 2>/dev/null | sed -n "s/.*@https-dns-proxy\[\([0-9]*\)\]\.listen_addr='$DOH_SYS_ADDR'/\1/p" | head -1)
if [ -z "$IDX" ]; then
  uci add https-dns-proxy https-dns-proxy >/dev/null
  IDX=$(uci show https-dns-proxy | grep -c '@https-dns-proxy\[[0-9]*\]=')
  IDX=$((IDX - 1))
fi
uci set https-dns-proxy.@https-dns-proxy[$IDX].resolver_url="$DOH_PRIMARY"
uci set https-dns-proxy.@https-dns-proxy[$IDX].bootstrap_dns="$DOH_BOOTSTRAP"
uci set https-dns-proxy.@https-dns-proxy[$IDX].listen_addr="$DOH_SYS_ADDR"
uci set https-dns-proxy.@https-dns-proxy[$IDX].listen_port='53'

uci commit https-dns-proxy
/etc/init.d/https-dns-proxy enable >/dev/null 2>&1 || true
/etc/init.d/https-dns-proxy restart
sleep 4

for a in "127.0.0.1:5053" "127.0.0.1:5054" "$DOH_SYS_ADDR:53"; do
  netstat -lnup 2>/dev/null | grep -q "$a" || die "https-dns-proxy не слушает $a (смотрите: logread -e https-dns-proxy)"
done
echo "  слушает 127.0.0.1:5053, 127.0.0.1:5054, $DOH_SYS_ADDR:53"

# --- 4. WAN DNS --------------------------------------------------------------

step 4/6 "DNS на WAN"
WAN=$(uci show network 2>/dev/null | sed -n "s/^network\.\([a-z0-9_]*\)\.proto='pppoe'/\1/p" | head -1)
[ -n "$WAN" ] || WAN=$(uci show network 2>/dev/null | sed -n "s/^network\.\([a-z0-9_]*\)\.proto='dhcp'/\1/p" | grep -v '^lan$' | head -1)
[ -n "$WAN" ] || WAN=wan
uci set network.$WAN.peerdns='0'
uci -q delete network.$WAN.dns
uci add_list network.$WAN.dns="$DOH_SYS_ADDR"
uci add_list network.$WAN.dns="$DNS_FALLBACK"
uci commit network
# без ifup: реконнект WAN оборвал бы связь, поэтому resolv.conf правится напрямую,
# а uci-значение вступит в силу само при следующем подъёме интерфейса
mkdir -p /tmp/resolv.conf.d
printf '# Interface %s\nnameserver %s\nnameserver %s\n' "$WAN" "$DOH_SYS_ADDR" "$DNS_FALLBACK" \
  > /tmp/resolv.conf.d/resolv.conf.auto
echo "  $WAN -> $DOH_SYS_ADDR, запасной $DNS_FALLBACK"

# --- 5. Заготовка PassWall2 --------------------------------------------------

step 5/6 "Базовая настройка PassWall2"
if [ "$(uci -q get passwall2.$SHUNT)" != "nodes" ]; then
  uci set passwall2.$SHUNT=nodes
  uci set passwall2.$SHUNT.remarks="$SHUNT"
fi
uci set passwall2.$SHUNT.type='Xray'
uci set passwall2.$SHUNT.protocol='_shunt'
uci set passwall2.$SHUNT.default_node='_direct'
uci set passwall2.$SHUNT.PrivateIP='_direct'
uci set passwall2.$SHUNT.domainStrategy='AsIs'
uci set passwall2.$SHUNT.domainMatcher='hybrid'
uci set passwall2.$SHUNT.write_ipset_direct='1'
uci set passwall2.$SHUNT.fakedns='1'
uci set passwall2.$SHUNT.enable_geoview_ip='0'
uci set passwall2.$SHUNT.shunt_group='RU'

uci set passwall2.@global[0].enabled='1'
uci set passwall2.@global[0].node="$SHUNT"
uci set passwall2.@global[0].localhost_proxy='1'
uci set passwall2.@global[0].client_proxy='1'
uci commit passwall2

/etc/init.d/passwall2 enable >/dev/null 2>&1 || true
/etc/init.d/passwall2 restart
sleep 8

# --- 6. Проверка -------------------------------------------------------------

step 6/6 "Проверка"
FAIL=0
check_dns() {
  IP=$(nslookup example.com "$1" 2>/dev/null | sed -n '/Name:/,$p' | grep -m1 -oE '[0-9]{1,3}(\.[0-9]{1,3}){3}' || true)
  if [ -n "$IP" ]; then echo "  DNS $2: ok"; else echo "  DNS $2: НЕ РАБОТАЕТ"; FAIL=1; fi
}
check_dns 127.0.0.1 "для клиентов"
check_dns "$DOH_SYS_ADDR" "системный"

CODE=$(curl -s -o /dev/null -m 15 -w '%{http_code}' https://www.google.com/generate_204 2>/dev/null || true)
if [ "$CODE" = 204 ]; then echo "  интернет: ok"; else echo "  интернет: НЕ РАБОТАЕТ (код '$CODE')"; FAIL=1; fi

echo
if [ "$FAIL" = 0 ]; then
  echo "===================================================================="
  echo " Готово. PassWall2 установлен, весь трафик пока идёт напрямую."
  echo
  echo " Дальше руками:"
  echo "  1. LuCI - Services - PassWall 2 - Подписки: добавить подписку,"
  echo "     User-Agent оставить v2rayN, затем «Ручное обновление подписки»"
  echo "  2. Управление правилами: создать правила"
  echo "     (имя правила только из букв, цифр и подчёркиваний)"
  echo "  3. Общие параметры - Правила разделения трафика:"
  echo "     напротив правил выбрать ноду, «По умолчанию» = Прямое соединение"
  echo "  4. Перезапустить PassWall2: System - Startup - passwall2 - Restart"
  echo "     (или /etc/init.d/passwall2 restart)"
  echo "  5. Zapret:"
  echo "     sh <(wget -O - https://raw.githubusercontent.com/StressOzz/Zapret-Manager/main/Zapret-Manager.sh)"
  echo "===================================================================="
else
  echo "Что-то не поднялось. Логи:"
  echo "  logread -e https-dns-proxy"
  echo "  logread | grep passwall2"
  exit 1
fi
