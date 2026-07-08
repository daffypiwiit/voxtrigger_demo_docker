#!/bin/bash
set -euo pipefail
CFG=/tmp/haproxy.cfg
TEMPLATE=/usr/local/etc/haproxy/haproxy.cfg.template
{
  grep -v '__BACKEND_SERVERS__' "$TEMPLATE"
  IFS=',' read -ra SERVERS <<< "${HAPROXY_BACKEND_SERVERS:-127.0.0.1:8080}"
  for i in "${!SERVERS[@]}"; do
    echo "    server srv${i} ${SERVERS[$i]} check"
  done
} > "$CFG"
exec haproxy -f "$CFG" -db
