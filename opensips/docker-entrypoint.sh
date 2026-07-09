#!/bin/bash
set -euo pipefail

DB_HOST="${OPENSIPS_DB_HOST:-postgres}"
DB_PASS="${POSTGRES_PASSWORD:-changeme}"
OPENSIPS_SIP_PORT="${OPENSIPS_SIP_PORT:-5060}"
OPENSIPS_ALT_SIP_PORT="${OPENSIPS_ALT_SIP_PORT:-5070}"
OPENSIPS_ADDRESS_IP="${OPENSIPS_ADDRESS_IP:-0.0.0.0/0}"
CARRIER_ROUTES="${CARRIER_ROUTES:-prefix:23,split:2,host:pbx-lab.piwiit.com:5080}"
DISPATCHER_DESTINATIONS="${DISPATCHER_DESTINATIONS:-sip:freeswitch:5080}"
SQL_DIR=/usr/share/opensips/postgres

sql_escape() {
  printf '%s' "$1" | sed "s/'/''/g"
}

parse_cidr() {
  local entry="$1"
  entry="$(echo "$entry" | xargs)"
  if [[ "$entry" == */* ]]; then
    printf '%s %s\n' "${entry%/*}" "${entry##*/}"
  elif [ "$entry" = "0.0.0.0" ]; then
    printf '%s %s\n' "0.0.0.0" "0"
  else
    printf '%s %s\n' "$entry" "32"
  fi
}

generate_address_seed() {
  local -a entries
  local entry ip mask rows=() id=1 i

  IFS=',' read -r -a entries <<< "${OPENSIPS_ADDRESS_IP}"

  for i in "${!entries[@]}"; do
    entry="$(echo "${entries[$i]}" | xargs)"
    [ -n "$entry" ] || continue

    read -r ip mask <<< "$(parse_cidr "$entry")"
    rows+=("    ($id, 1, '$(sql_escape "$ip")', ${mask}, 0, 'any', '', '')")
    id=$((id + 1))
  done

  if [ "${#rows[@]}" -eq 0 ]; then
    echo "No OPENSIPS_ADDRESS_IP entries configured" >&2
    exit 1
  fi

  {
    echo "INSERT INTO public.address (id, grp, ip, mask, port, proto, pattern, context_info) VALUES"
    for i in "${!rows[@]}"; do
      if [ "$i" -lt $((${#rows[@]} - 1)) ]; then
        echo "${rows[$i]},"
      else
        echo "${rows[$i]}"
      fi
    done
    echo "ON CONFLICT DO NOTHING;"
  }
}

parse_route_fields() {
  local entry="$1"
  local pair key val prefix="" split="" host=""

  IFS=',' read -r -a pairs <<< "$entry"
  for pair in "${pairs[@]}"; do
    pair="$(echo "$pair" | xargs)"
    [ -n "$pair" ] || continue
    key="${pair%%:*}"
    val="${pair#*:}"
    case "$key" in
      prefix) prefix="$val" ;;
      split) split="$val" ;;
      host) host="$val" ;;
    esac
  done

  if [ -z "$prefix" ]; then
    echo "CARRIER_ROUTES entry missing prefix: $entry" >&2
    exit 1
  fi
  if [ -z "$split" ]; then
    echo "CARRIER_ROUTES entry missing split: $entry" >&2
    exit 1
  fi
  if [ -z "$host" ]; then
    echo "CARRIER_ROUTES entry missing host: $entry" >&2
    exit 1
  fi

  printf '%s %s %s\n' "$prefix" "$split" "$host"
}

generate_dispatcher_seed() {
  local dests="${DISPATCHER_DESTINATIONS}"
  local -a entries
  local entry rows=() id=1 i

  IFS=',' read -r -a entries <<< "$dests"
  for entry in "${entries[@]}"; do
    entry="$(echo "$entry" | xargs)"
    [ -n "$entry" ] || continue
    rows+=("    ($id, 101, '$(sql_escape "$entry")', NULL, 0, 0, 1, 0, '', 'dispatcher_${id}')")
    id=$((id + 1))
  done

  if [ "${#rows[@]}" -eq 0 ]; then
    echo "No DISPATCHER_DESTINATIONS entries configured" >&2
    exit 1
  fi

  {
    echo "INSERT INTO public.dispatcher (id, setid, destination, socket, state, probe_mode, weight, priority, attrs, description) VALUES"
    for i in "${!rows[@]}"; do
      if [ "$i" -lt $((${#rows[@]} - 1)) ]; then
        echo "${rows[$i]},"
      else
        echo "${rows[$i]}"
      fi
    done
    echo "ON CONFLICT (id) DO UPDATE SET"
    echo "  destination = EXCLUDED.destination,"
    echo "  description = EXCLUDED.description;"
  }
}

generate_carrier_route_seed() {
  local routes="${CARRIER_ROUTES}"
  local entry prefix split host rows=() id=1

  routes="${routes//;/$'\n'}"
  while IFS= read -r entry; do
    entry="$(echo "$entry" | xargs)"
    [ -n "$entry" ] || continue

    read -r prefix split host <<< "$(parse_route_fields "$entry")"
    rows+=("    ($id, 1, 1, '$(sql_escape "$prefix")', 0, 0, 0.5, ${split}, '$(sql_escape "$host")', '', '', 'route_${prefix}')")
    id=$((id + 1))
  done <<< "$routes"

  if [ "${#rows[@]}" -eq 0 ]; then
    echo "No CARRIER_ROUTES entries configured" >&2
    exit 1
  fi

  {
    echo "INSERT INTO public.carrierroute (id, carrier, domain, scan_prefix, flags, mask, prob, strip, rewrite_host, rewrite_prefix, rewrite_suffix, description) VALUES"
    for i in "${!rows[@]}"; do
      if [ "$i" -lt $((${#rows[@]} - 1)) ]; then
        echo "${rows[$i]},"
      else
        echo "${rows[$i]}"
      fi
    done
    echo "ON CONFLICT (id) DO UPDATE SET"
    echo "  scan_prefix = EXCLUDED.scan_prefix,"
    echo "  strip = EXCLUDED.strip,"
    echo "  rewrite_host = EXCLUDED.rewrite_host,"
    echo "  description = EXCLUDED.description;"
  }
}

sed -i "s|CHANGEME|${DB_PASS}|g" /etc/opensips/opensips.cfg
sed -i "s|@localhost/|@${DB_HOST}/|g" /etc/opensips/opensips.cfg
sed -i "s|CHANGEME|${DB_PASS}|g" /etc/opensips/opensips-cli.cfg
sed -i "s|@postgres|@${DB_HOST}|g" /etc/opensips/opensips-cli.cfg
sed -i "s|^socket=udp:0.0.0.0:[0-9]\\+|socket=udp:0.0.0.0:${OPENSIPS_SIP_PORT}|" /etc/opensips/opensips.cfg
sed -i "0,/^socket=udp:0.0.0.0:${OPENSIPS_SIP_PORT}$/! s|^socket=udp:0.0.0.0:[0-9]\\+|socket=udp:0.0.0.0:${OPENSIPS_ALT_SIP_PORT}|" /etc/opensips/opensips.cfg

echo "Waiting for PostgreSQL at ${DB_HOST}..."
until pg_isready -h "${DB_HOST}" -U postgres; do sleep 2; done
export PGPASSWORD="${DB_PASS}"

DB_EXISTS=$(psql -h "${DB_HOST}" -U postgres -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='opensips'" || echo 0)
if [ "${DB_EXISTS}" != "1" ]; then
  psql -h "${DB_HOST}" -U postgres -d postgres -c "CREATE DATABASE opensips;"
fi

HAS_VERSION=$(psql -h "${DB_HOST}" -U postgres -d opensips -tAc "SELECT to_regclass('public.version')" 2>/dev/null || true)
if [ -z "${HAS_VERSION}" ]; then
  echo "Applying OpenSIPS base schema..."
  for f in standard-create.sql acc-create.sql permissions-create.sql dispatcher-create.sql carrierroute-create.sql; do
    echo "  -> $f"
    psql -h "${DB_HOST}" -U postgres -d opensips -v ON_ERROR_STOP=0 -f "${SQL_DIR}/${f}"
  done
fi

SEED_DIR=/tmp/opensips-seed
rm -rf "$SEED_DIR"
mkdir -p "$SEED_DIR"
cp /opt/opensips-seed/*.sql "$SEED_DIR/"
generate_address_seed > "$SEED_DIR/00-address.generated.sql"
generate_carrier_route_seed > "$SEED_DIR/01-carrier-routes.generated.sql"
generate_dispatcher_seed > "$SEED_DIR/02-dispatcher.generated.sql"

for seed in "$SEED_DIR"/*.sql; do
  [ -f "$seed" ] || continue
  echo "Applying seed $(basename "$seed")..."
  psql -h "${DB_HOST}" -U postgres -d opensips -v ON_ERROR_STOP=0 -f "$seed"
done

exec opensips -f /etc/opensips/opensips.cfg -F
