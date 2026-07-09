#!/bin/bash
set -euo pipefail

SNGREPRC=/etc/sngrep/sngreprc
SIP_NETWORK="${SIP_NETWORK:-docker_demo_pwt_sip_net}"
COMPOSE_PROJECT="${COMPOSE_PROJECT:-${SIP_NETWORK%_sip_net}}"
SIP_CAPTURE="${SIP_CAPTURE:-clean}"

opensips_container_ref() {
  if [ -n "${OPENSIPS_CONTAINER_ID:-}" ]; then
    echo "$OPENSIPS_CONTAINER_ID"
    return
  fi
  local id
  id=$(curl -sf --unix-socket /var/run/docker.sock \
    "http://localhost/containers/json?all=1&filters=%7B%22label%22%3A%5B%22com.docker.compose.project%3D${COMPOSE_PROJECT}%22%2C%22com.docker.compose.service%3Dopensips%22%5D%7D" \
    2>/dev/null | sed -n 's/.*"Id":"\([^"]*\)".*/\1/p' | head -1)
  if [ -n "$id" ]; then
    echo "$id"
    return
  fi
  curl -sf --unix-socket /var/run/docker.sock \
    "http://localhost/containers/json?all=1&filters=%7B%22name%22%3A%5B%22${COMPOSE_PROJECT}-opensips%22%5D%7D" \
    2>/dev/null | sed -n 's/.*"Id":"\([^"]*\)".*/\1/p' | head -1
}

container_env() {
  local ref="$1" key="$2"
  [ -n "$ref" ] || return 0
  curl -sf --unix-socket /var/run/docker.sock \
    "http://localhost/containers/${ref}/json" 2>/dev/null \
    | grep -oE "\"${key}=[^\"]+\"" \
    | head -1 \
    | sed "s/^\"${key}=//;s/\"$//"
}

freeswitch_container_ref() {
  if [ -n "${FREESWITCH_CONTAINER_ID:-}" ]; then
    echo "$FREESWITCH_CONTAINER_ID"
    return
  fi
  curl -sf --unix-socket /var/run/docker.sock \
    "http://localhost/containers/json?all=1&filters=%7B%22label%22%3A%5B%22com.docker.compose.project%3D${COMPOSE_PROJECT}%22%2C%22com.docker.compose.service%3Dfreeswitch%22%5D%7D" \
    2>/dev/null | sed -n 's/.*"Id":"\([^"]*\)".*/\1/p' | head -1
}

container_ip() {
  local ref="$1"
  [ -n "$ref" ] || return 0
  curl -sf --unix-socket /var/run/docker.sock \
    "http://localhost/containers/${ref}/json" 2>/dev/null \
    | sed -n 's/.*"IPAddress":"\([0-9.]*\)".*/\1/p' \
    | head -1
}

stack_sip_ports() {
  local os_ref fs_ref

  if [ -n "${SIP_PORTS:-}" ]; then
    IFS=',' read -r -a SIP_PORT_LIST <<< "$SIP_PORTS"
    SIP_PORT="${SIP_PORT_LIST[0]}"
    ALT_SIP_PORT="${SIP_PORT_LIST[1]:-${SIP_PORT_LIST[0]}}"
    FS_PORT="${SIP_PORT_LIST[2]:-5080}"
    return
  fi

  SIP_PORT="${SIP_PORT:-}"
  ALT_SIP_PORT="${ALT_SIP_PORT:-}"
  FS_PORT="${FS_PORT:-5080}"

  os_ref=$(opensips_container_ref || true)
  [ -n "$SIP_PORT" ] || SIP_PORT=$(container_env "$os_ref" OPENSIPS_SIP_PORT)
  [ -n "$ALT_SIP_PORT" ] || ALT_SIP_PORT=$(container_env "$os_ref" OPENSIPS_ALT_SIP_PORT)
  SIP_PORT="${SIP_PORT:-5060}"
  ALT_SIP_PORT="${ALT_SIP_PORT:-5070}"

  fs_ref=$(freeswitch_container_ref || true)
  local fs_sbc
  fs_sbc=$(container_env "$fs_ref" PWT_SBC_PORT)
  # ponytail: FS listens on 5080 internally; host-mapped SIP uses OPENSIPS_SIP_PORT
  FS_PORT=5080
}

port_filter_clause() {
  local -a ports=("$@")
  local clause="" p
  for p in "${ports[@]}"; do
    [ -n "$p" ] || continue
    if [ -n "$clause" ]; then
      clause="${clause} or port ${p}"
    else
      clause="port ${p}"
    fi
  done
  echo "$clause"
}

resolve_capture() {
  local os_ref fs_ref os_ip fs_ip filter_ports clause
  stack_sip_ports

  os_ref=$(opensips_container_ref || true)
  fs_ref=$(freeswitch_container_ref || true)
  os_ip=$(container_ip "$os_ref" || true)
  fs_ip=$(container_ip "$fs_ref" || true)

  case "$SIP_CAPTURE" in
    clean|bridge)
      IFACE="${SIP_IFACE:-$(bridge_iface)}"
      filter_ports=("$SIP_PORT" "$FS_PORT")
      clause=$(port_filter_clause "${filter_ports[@]}")
      FILTER="(udp or tcp) and (${clause})"
      echo "=== SIP en ${IFACE} (${COMPOSE_PROJECT} / ${SIP_NETWORK}) ===" >&2
      echo "  filtro: ${FILTER}" >&2
      echo "  cliente → OpenSIPS${os_ip:+ ($os_ip)} :${SIP_PORT}" >&2
      echo "  OpenSIPS → FreeSWITCH${fs_ip:+ ($fs_ip)} :${FS_PORT}" >&2
      echo "  Prueba: sipsak ... -r ${SIP_PORT}" >&2
      ;;
    all)
      IFACE=any
      filter_ports=("$SIP_PORT" "$ALT_SIP_PORT" "$FS_PORT")
      clause=$(port_filter_clause "${filter_ports[@]}")
      FILTER="(udp or tcp) and (${clause})"
      echo "all interfaces — filtro: ${FILTER}" >&2
      ;;
    *)
      echo "SIP_CAPTURE: clean | all" >&2
      exit 1
      ;;
  esac
}

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
