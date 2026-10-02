#!/system/bin/sh
# Portable LTE control for Surface devices with the Qualcomm Snapdragon X16 modem
# (USB 045e:09a5).  Self-contained: qmicli + glibc runtime + ethcli.jar ship in the
# app and are extracted next to this script.  Runs as root.
# usage: lte-ctl.sh {status|info|signal|modem|prepare|eth-on|eth-off|apply|validate-on|validate-off}
# env:   APN=...        carrier APN (default ctlte)
#        VALIDATE=1|0   repoint Android connectivity validation to reachable URLs
SD=$(cd "$(dirname "$0")" && pwd)
export XDG_RUNTIME_DIR="$SD"
LD="$SD/ld-linux-x86-64.so.2"
T=/data/local/tmp
IPF="$T/lte-ip.txt"
APN="${APN:-ctlte}"
VALIDATE="${VALIDATE:-0}"
VID="${VID:-045e}"
PID="${PID:-09a5}"

log(){ echo "$*"; }

# ---------- device discovery ----------
find_modem(){
  for d in /sys/bus/usb/devices/*/; do
    [ "$(cat "${d}idVendor" 2>/dev/null)" = "$VID" ] || continue
    [ "$(cat "${d}idProduct" 2>/dev/null)" = "$PID" ] || continue
    echo "${d%/}"; return 0
  done
  return 1
}
find_wdm(){ # $1 = modem dir (optional)
  for w in /sys/class/usbmisc/cdc-wdm*/; do
    [ -e "$w" ] || continue
    n=$(basename "$w")
    if [ -n "$1" ]; then
      dev=$(readlink -f "${w}device" 2>/dev/null)
      case "$dev" in *"/$1/"*) echo "$n"; return 0 ;; esac
    fi
  done
  for w in /sys/class/usbmisc/cdc-wdm*/; do [ -e "$w" ] && { basename "$w"; return 0; }; done
}
find_net(){ # $1 = modem dir (optional) -> cdc_ncm netdev belonging to the modem
  for n in /sys/class/net/*; do
    [ -e "$n/cdc_ncm" ] || continue
    if [ -n "$1" ]; then
      dev=$(readlink -f "$n/device" 2>/dev/null)
      case "$dev" in *"/$1/"*) echo "$(basename "$n")"; return 0 ;; esac
    fi
  done
  for n in /sys/class/net/*; do [ -e "$n/cdc_ncm" ] && { basename "$n"; return 0; }; done
}
# our LTE-mode interface (a cdc_ncm netdev renamed to eth*)
cur_eth(){
  for n in /sys/class/net/eth*; do
    [ -e "$n/cdc_ncm" ] && { basename "$n"; return 0; }
  done
  return 1
}
# first free ethN (matching Android's config_ethernet_iface_regex eth\d)
pick_eth(){
  for i in 0 1 2 3 4; do
    [ -e "/sys/class/net/eth$i" ] || { echo "eth$i"; return 0; }
  done
  echo eth0
}

MODEM=$(find_modem 2>/dev/null)
WDMN=$(find_wdm "$MODEM" 2>/dev/null); WDMN=${WDMN:-cdc-wdm0}
DEVPATH="/dev/$WDMN"
NETF=$T/lte-net
_n=$(find_net "$MODEM" 2>/dev/null)
case "$_n" in
  ""|eth*) ORIG=$(cat "$NETF" 2>/dev/null); ORIG=${ORIG:-wwan0} ;;
  *)       ORIG=$_n; echo "$ORIG" > "$NETF" ;;
esac
# current data netdev name: ethN when in LTE mode, else the original name
cur_net(){ E=$(cur_eth); if [ -n "$E" ]; then echo "$E"; else echo "$ORIG"; fi; }

# ---------- qmi ----------
qmi(){ "$LD" --library-path "$SD" "$SD/qmicli" -d "$DEVPATH" -p --device-open-mbim "$@" 2>&1; }
proxy_up(){ [ -S "$SD/mbim-proxy" ] || { "$LD" --library-path "$SD" "$SD/mbim-proxy" >/dev/null 2>&1 & sleep 2; }; }

buf_fix(){
  for dev in "$ORIG" "$(cur_eth)"; do
    d=/sys/class/net/$dev/cdc_ncm
    [ -e "$d/rx_max" ] || continue
    for v in 16383 16384; do
      echo $v > "$d/rx_max" 2>/dev/null
      echo $v > "$d/tx_max" 2>/dev/null
    done
  done
}

qmi_settings(){
  proxy_up
  qmi --dms-set-operating-mode=online >/dev/null 2>&1
  qmi --wds-start-network=apn=$APN,ip-type=4 --client-no-release-cid >/dev/null 2>&1
  sleep 2
  qmi --wds-get-current-settings
}

parse_settings(){
  IP=$(printf '%s\n' "$1" | sed -n 's/.*IPv4 address: *//p'         | head -1 | tr -d '\r')
  MASK=$(printf '%s\n' "$1" | sed -n 's/.*IPv4 subnet mask: *//p'   | head -1 | tr -d '\r')
  GW=$(printf '%s\n' "$1" | sed -n 's/.*IPv4 gateway address: *//p' | head -1 | tr -d '\r')
  DNS1=$(printf '%s\n' "$1" | sed -n 's/.*IPv4 primary DNS: *//p'   | head -1 | tr -d '\r')
  DNS2=$(printf '%s\n' "$1" | sed -n 's/.*IPv4 secondary DNS: *//p' | head -1 | tr -d '\r')
  PREFIXLEN=29
  case "$MASK" in
    255.255.255.252) PREFIXLEN=30 ;;
    255.255.255.248) PREFIXLEN=29 ;;
    255.255.255.240) PREFIXLEN=28 ;;
    255.255.255.0)   PREFIXLEN=24 ;;
  esac
}

prepare(){
  buf_fix
  S=$(qmi_settings)
  if ! echo "$S" | grep -q 'IPv4 address'; then
    if [ -n "$MODEM" ] && [ -e "$MODEM/authorized" ]; then
      log "retry: re-enumerating modem"
      echo 0 > "$MODEM/authorized" 2>/dev/null
      sleep 2
      echo 1 > "$MODEM/authorized" 2>/dev/null
      sleep 8
      MODEM=$(find_modem); WDMN=$(find_wdm "$MODEM"); WDMN=${WDMN:-cdc-wdm0}
      DEVPATH="/dev/$WDMN"
      _n=$(find_net "$MODEM" 2>/dev/null)
      case "$_n" in ""|eth*) ;; *) ORIG=$_n; echo "$ORIG" > "$NETF" ;; esac
      buf_fix
      S=$(qmi_settings)
    fi
  fi
  if ! echo "$S" | grep -q 'IPv4 address'; then
    log "ERR: no IPv4 from modem; qmi output:"; echo "$S" | head -20 | sed 's/^/[qmi] /'
    return 1
  fi
  parse_settings "$S"
  { echo "iface=eth"; echo "ip=$IP"; echo "prefix=$PREFIXLEN"; echo "gw=$GW"; echo "dns1=$DNS1"; echo "dns2=$DNS2"; } > "$IPF"
  log "ready: $IP/$PREFIXLEN gw $GW dns $DNS1,$DNS2"
}

apply_static(){ # $1 = interface name
  IF="$1"; [ -n "$IF" ] || IF=$(cur_eth)
  g(){ sed -n "s/^$1=//p" "$IPF" | head -1 | tr -d '\r'; }
  CLASSPATH="$SD/ethcli.jar" app_process /system/bin com.ltegopher.EthCli "$IF" \
      "$(g ip)" "$(g prefix)" "$(g gw)" "$(g dns1)" "$(g dns2)"
}

validate_on(){
  settings put global captive_portal_http_url            http://connect.rom.miui.com/generate_204
  settings put global captive_portal_https_url           https://connect.rom.miui.com/generate_204
  settings put global captive_portal_fallback_url        http://connect.rom.miui.com/generate_204
  settings put global captive_portal_other_fallback_urls http://connect.rom.miui.com/generate_204
  settings put global captive_portal_use_https           1
}
validate_off(){
  settings delete global captive_portal_http_url 2>/dev/null
  settings delete global captive_portal_https_url 2>/dev/null
  settings delete global captive_portal_fallback_url 2>/dev/null
  settings delete global captive_portal_other_fallback_urls 2>/dev/null
  settings delete global captive_portal_use_https 2>/dev/null
}

eth_on(){
  E=$(cur_eth)
  if [ -n "$E" ]; then [ -f "$IPF" ] && apply_static "$E"; log "already in LTE mode"; return 0; fi
  N=$(cur_net)
  EX=$(ip -o -4 addr show "$N" 2>/dev/null | sed -n 's/.*inet \([0-9.]*\/[0-9]*\).*/\1/p' | head -1)
  ALIVE=0
  if [ -n "$EX" ]; then
    DT=$(sed -n 's/^dns1=//p' "$IPF" 2>/dev/null | head -1)
    [ -n "$DT" ] && ping -I "$N" -c 1 -W 2 "$DT" >/dev/null 2>&1 && ALIVE=1
  fi
  if [ "$ALIVE" = 1 ]; then log "reuse live session $EX"; else log "session not alive - establishing"; prepare || return 1; fi
  ETHT=$(pick_eth)
  ip link set "$ORIG" down 2>/dev/null
  ip netns del ltemv 2>/dev/null
  ip netns add ltemv 2>/dev/null
  ip link set "$ORIG" netns ltemv 2>/dev/null
  ip netns exec ltemv ip link set "$ORIG" name "$ETHT" 2>/dev/null
  ip netns exec ltemv ip link set "$ETHT" netns 1 2>/dev/null
  ip link set "$ETHT" up 2>/dev/null
  sleep 3
  apply_static "$ETHT"
  [ "$VALIDATE" = 1 ] && validate_on
  cmd wifi set-wifi-enabled disabled 2>/dev/null
  svc wifi disable 2>/dev/null
  log "LTE mode ON ($ETHT up, wifi disabled)"
}

eth_off(){
  E=$(cur_eth)
  if [ -n "$E" ]; then
    ip link set "$E" down 2>/dev/null
    ip link set "$E" name "$ORIG" 2>/dev/null
  fi
  ip link set "$ORIG" up 2>/dev/null
  cmd wifi set-wifi-enabled enabled 2>/dev/null
  svc wifi enable 2>/dev/null
  log "Ethernet disconnected; $ORIG restored; wifi enabled"
}

status(){
  E=$(cur_eth); MODE=wifi; [ -n "$E" ] && MODE=eth
  if ip -o link show wlan0 2>/dev/null | grep -q "state UP" && ip -o -4 addr show wlan0 2>/dev/null | grep -q "inet "; then
    WIFI=connected
  else
    WIFI=disconnected
  fi
  IFC=$(cur_net)
  ADD=$(ip -o -4 addr show "$IFC" 2>/dev/null | sed -n 's/.*inet \([0-9.]*\/[0-9]*\).*/\1/p' | head -1)
  DEFIF=$(ip route get 1.1.1.1 2>/dev/null | sed -n 's/.* dev \([^ ]*\).*/\1/p' | head -1)
  [ -n "$ADD" ] || ADD="-"; [ -n "$DEFIF" ] || DEFIF="-"
  printf '{"mode":"%s","wifi":"%s","default":"%s","iface":"%s","addr":"%s","apn":"%s"}\n' \
     "$MODE" "$WIFI" "$DEFIF" "$IFC" "$ADD" "$APN"
}

# human-readable basic info for the app UI
info(){
  echo "modem=${MODEM:-none}"
  echo "wdm=$DEVPATH"
  echo "net=$(cur_net)"
  echo "orig=$ORIG"
  echo "eth=$(cur_eth)"
  echo "apn=$APN"
  echo "wifi=$( (ip -o -4 addr show wlan0 2>/dev/null | grep -q 'inet ') && echo connected || echo disconnected )"
  echo "default=$(ip route get 1.1.1.1 2>/dev/null | sed -n 's/.* dev \([^ ]*\).*/\1/p' | head -1)"
  echo "wlan_ip=$(ip -o -4 addr show wlan0 2>/dev/null | sed -n 's/.*inet \([0-9.]*\/[0-9]*\).*/\1/p' | head -1)"
  echo "wwan_ip=$(ip -o -4 addr show "$(cur_net)" 2>/dev/null | sed -n 's/.*inet \([0-9.]*\/[0-9]*\).*/\1/p' | head -1)"
}

signal(){
  proxy_up
  i=0; OUT=""
  while [ $i -lt 3 ]; do
    OUT=$(qmi --nas-get-signal-info)
    echo "$OUT" | grep -q "RSRP:" && break
    i=$((i+1)); sleep 2
  done
  echo "$OUT"
  qmi --nas-get-serving-system | sed -n '1,14p'
}

modem(){
  proxy_up
  echo "== operating mode =="; qmi --dms-get-operating-mode
  echo "== serving system =="; qmi --nas-get-serving-system | sed -n '1,14p'
  echo "== signal ==";         qmi --nas-get-signal-info
}

case "$1" in
  status)   status ;;
  info)     info ;;
  signal)   signal ;;
  modem)    modem ;;
  prepare)  prepare ;;
  eth-on)   eth_on ;;
  eth-off)  eth_off ;;
  apply)    apply_static "$2" ;;
  validate-on)  validate_on ;;
  validate-off) validate_off ;;
  *) echo "usage: $0 {status|info|signal|modem|prepare|eth-on|eth-off|apply|validate-on|validate-off}" ;;
esac
