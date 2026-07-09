#!/usr/bin/env bash
# sngrep for Portainer / Compose stacks (run on the Docker host).
#
# Argument = Portainer stack name OR compose project (often the same, not always).
# Resolves the real sip_net via Docker labels / container names.
#
# Usage:
#   ./scripts/sngrep-stack.sh              # list stacks
#   ./scripts/sngrep-stack.sh demo1
set -euo pipefail

IMAGE="${SIP_DEBUG_IMAGE:-docker_demo_pwt/sip-debug:latest}"

opensips_cid_for_project() {
  local project="$1"
  docker ps -q \
    --filter "label=com.docker.compose.project=${project}" \
    --filter "label=com.docker.compose.service=opensips" 2>/dev/null | head -1
}

opensips_cid_for_query() {
  local query="$1" cid

  cid=$(opensips_cid_for_project "$query")
  [ -n "$cid" ] && { echo "$cid"; return; }

  cid=$(docker ps -q --filter "network=${query}_sip_net" \
    --filter "label=com.docker.compose.service=opensips" 2>/dev/null | head -1)
  [ -n "$cid" ] && { echo "$cid"; return; }

  # Portainer / Compose container names: demo1-opensips-1, demo1_opensips_1, ...
  cid=$(docker ps -aq --filter "name=opensips" --format '{{.ID}} {{.Names}}' 2>/dev/null \
    | awk -v q="$query" '$2 ~ "^" q "[-_].*opensips" || $2 ~ "^/" q "[-_].*opensips" { print $1; exit }')
  [ -n "$cid" ] && { echo "$cid"; return; }

  cid=$(docker ps -aq --format '{{.ID}} {{.Names}}' 2>/dev/null \
    | awk -v q="$query" 'tolower($2) ~ tolower(q) && tolower($2) ~ /opensips/ { print $1; exit }')
  echo "$cid"
}

sip_network_for_cid() {
  local cid="$1"
  docker inspect "$cid" --format '{{range $k,$v := .NetworkSettings.Networks}}{{println $k}}{{end}}' \
    | grep '_sip_net$' | head -1
}

container_env_from_cid() {
  local cid="$1" key="$2"
  docker inspect "$cid" --format '{{range .Config.Env}}{{println .}}{{end}}' \
    | sed -n "s/^${key}=//p" | head -1
}

resolve_stack() {
  local query="$1" cid project net

  cid=$(opensips_cid_for_query "$query")
  if [ -z "$cid" ]; then
    return 1
  fi

  project=$(docker inspect "$cid" --format '{{index .Config.Labels "com.docker.compose.project"}}')
  net=$(sip_network_for_cid "$cid")
  if [ -z "$net" ]; then
    echo "opensips encontrado pero sin red *_sip_net (id=$cid)" >&2
    return 1
  fi

  printf '%s|%s|%s\n' "$project" "$net" "$cid"
}

list_stacks() {
  echo "Stacks SIP en este host:" >&2
  local seen="" cid project net name
  while read -r cid; do
    [ -n "$cid" ] || continue
    project=$(docker inspect "$cid" --format '{{index .Config.Labels "com.docker.compose.project"}}')
    net=$(sip_network_for_cid "$cid")
    name=$(docker inspect "$cid" --format '{{.Name}}' | sed 's|^/||')
    sip_port=$(container_env_from_cid "$cid" OPENSIPS_SIP_PORT)
    sip_port="${sip_port:-5060}"
    case " $seen " in *" $project "*) continue ;; esac
    seen="$seen $project"
    echo "  $project  (red: ${net:-?}, sip: :${sip_port}, opensips: $name)" >&2
  done < <(docker ps -q --filter "label=com.docker.compose.service=opensips" 2>/dev/null)

  if [ -z "$seen" ]; then
    echo "  (ninguno — ¿stack corriendo con servicio opensips?)" >&2
  fi
  echo >&2
  echo "Uso: $0 <nombre_stack_o_proyecto>" >&2
  echo "Ej:  $0 demo1   $0 voxtrigger_demo_docker" >&2
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  list_stacks
  exit 0
fi

if [ $# -eq 0 ]; then
  list_stacks
  exit 1
fi

QUERY="$1"
shift

RESOLVED=$(resolve_stack "$QUERY") || {
  echo "Stack no encontrado: $QUERY" >&2
  echo "(Busca por nombre Portainer, compose project o prefijo del contenedor opensips.)" >&2
  echo >&2
  list_stacks
  exit 1
}

PROJECT=$(echo "$RESOLVED" | cut -d'|' -f1)
NET=$(echo "$RESOLVED" | cut -d'|' -f2)
OPENSIPS_CID=$(echo "$RESOLVED" | cut -d'|' -f3)

SIP_PORT=$(container_env_from_cid "$OPENSIPS_CID" OPENSIPS_SIP_PORT)
ALT_SIP_PORT=$(container_env_from_cid "$OPENSIPS_CID" OPENSIPS_ALT_SIP_PORT)
SIP_PORT="${SIP_PORT:-5060}"
ALT_SIP_PORT="${ALT_SIP_PORT:-5070}"

echo "Stack: $PROJECT  red: $NET  sip: :${SIP_PORT}/:${ALT_SIP_PORT}" >&2

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "Imagen no encontrada: $IMAGE" >&2
  echo "Build: docker build -t $IMAGE ./sip-debug" >&2
  exit 1
fi

exec docker run --rm -it \
  --network host \
  --cap-add NET_ADMIN \
  --cap-add NET_RAW \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  -e "SIP_NETWORK=${NET}" \
  -e "COMPOSE_PROJECT=${PROJECT}" \
  -e "OPENSIPS_CONTAINER_ID=${OPENSIPS_CID}" \
  -e "SIP_PORT=${SIP_PORT}" \
  -e "ALT_SIP_PORT=${ALT_SIP_PORT}" \
  "$@" \
  "$IMAGE"
