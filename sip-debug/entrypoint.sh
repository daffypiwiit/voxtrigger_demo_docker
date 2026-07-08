#!/bin/bash
set -euo pipefail

SNGREPRC=/etc/sngrep/sngreprc
SIP_NETWORK="${SIP_NETWORK:-docker_demo_pwt_sip_net}"
SIP_CAPTURE="${SIP_CAPTURE:-clean}"

bridge_iface() {
  local id
  id=$(curl -sf --unix-socket /var/run/docker.sock \
    "http://localhost/networks" \
    | tr '{' '\n' \
    | grep "\"Name\":\"${SIP_NETWORK}\"" \
    | head -1 \
    | sed -n 's/.*"Id":"\([^"]*\)".*/\1/p')
  if [ -z "$id" ]; then
    echo "sip_net not found: ${SIP_NETWORK}" >&2
    exit 1
  fi
  echo "br-${id:0:12}"
}

container_ip() {
  local proj="${SIP_NETWORK%_sip_net}"
  local name="${proj}-${1}-1"
  curl -sf --unix-socket /var/run/docker.sock \
    "http://localhost/containers/${name}/json" 2>/dev/null \
    | sed -n 's/.*"IPAddress":"\([0-9.]*\)".*/\1/p' \
    | head -1
}

resolve_capture() {
  case "$SIP_CAPTURE" in
    clean|bridge)
      IFACE="${SIP_IFACE:-$(bridge_iface)}"
      FILTER='(udp or tcp) and (port 5060 or port 5080)'
      local os_ip fs_ip
      os_ip=$(container_ip opensips || true)
      fs_ip=$(container_ip freeswitch || true)
      echo "=== SIP limpio en ${IFACE} ===" >&2
      echo "  cliente → OpenSIPS${os_ip:+ ($os_ip)} :5060" >&2
      echo "  OpenSIPS → FreeSWITCH${fs_ip:+ ($fs_ip)} :5080" >&2
      echo "  Prueba: sipsak -f sip-debug/invite-external.sip ... -r 5060" >&2
      ;;
    all)
      IFACE=any
      FILTER='(udp or tcp) and (port 5060 or port 5070 or port 5080)'
      echo "all interfaces — duplicados posibles (lo + bridge + veth)" >&2
      ;;
    *)
      echo "SIP_CAPTURE: clean | all" >&2
      exit 1
      ;;
  esac
}

run_sngrep() {
  local ui=()
  resolve_capture
  if [ ! -t 1 ] || [ ! -t 0 ]; then
    echo "Sin TTY: modo consola (-N). Usa -it para la UI ncurses." >&2
    ui=(-N)
  else
    echo "sngrep — q salir | F2 filtro | F3 buscar | F5 guardar pcap" >&2
  fi
  exec sngrep "${ui[@]}" -d "$IFACE" -f "$SNGREPRC" "" "$FILTER"
}

run_tcpdump() {
  resolve_capture
  echo "tcpdump on ${IFACE} — Ctrl+C para salir" >&2
  exec tcpdump -i "$IFACE" -n -l -s 0 -A "$FILTER"
}

if [ "${TCPDUMP:-0}" = 1 ]; then
  run_tcpdump
fi

run_sngrep
