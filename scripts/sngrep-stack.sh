#!/usr/bin/env bash
# sngrep for Portainer / Compose stacks (run on the Docker host, not inside Portainer UI).
#
# Portainer stack name = first argument (Stacks → name column, e.g. "cliente-a").
# Network will be: {stack}_sip_net
#
# Usage:
#   ./scripts/sngrep-stack.sh              # list stacks
#   ./scripts/sngrep-stack.sh cliente-a
#   SIP_CAPTURE=all ./scripts/sngrep-stack.sh cliente-b
set -euo pipefail

IMAGE="${SIP_DEBUG_IMAGE:-docker_demo_pwt/sip-debug:latest}"

list_stacks() {
  echo "Stacks SIP en este host (nombre = stack en Portainer):" >&2
  docker network ls --format '{{.Name}}' | grep '_sip_net$' | sed 's/_sip_net$//' | sort \
    | while read -r name; do
        echo "  $name"
      done
  echo >&2
  echo "Uso: $0 <nombre_stack>" >&2
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  list_stacks
  exit 0
fi

if [ $# -eq 0 ]; then
  list_stacks
  exit 1
fi

STACK="$1"
shift
NET="${STACK}_sip_net"

if ! docker network inspect "$NET" >/dev/null 2>&1; then
  echo "Red no encontrada: $NET" >&2
  echo "¿El stack '$STACK' está corriendo en ESTE host?" >&2
  echo "(Portainer remoto → SSH al nodo Docker y ejecuta ahí.)" >&2
  echo >&2
  list_stacks
  exit 1
fi

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
  "$@" \
  "$IMAGE"
