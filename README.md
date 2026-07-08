# docker_demo_pwt — Stack SIP Piwiit

Stack Docker Compose: **OpenSIPS** (carrierroute) + **PostgreSQL** + **FreeSWITCH** + **HAProxy** (WebSocket VoxTrigger) + exporters Prometheus.

## Requisitos

- Docker + Docker Compose v2
- BuildKit (`DOCKER_BUILDKIT=1`)
- `SIGNALWIRE_TOKEN`, `FREESWITCH_GIT_USER` y `FREESWITCH_GIT_TOKEN` en `.env` (build FreeSWITCH)
- Binarios exporter en `exporters/bin/` (copiados desde ansible-control)

## Arranque rápido

```bash
cp .env.example .env
# Editar .env: SIGNALWIRE_TOKEN, FREESWITCH_GIT_TOKEN

DOCKER_BUILDKIT=1 docker compose build
docker compose up -d
```

## Servicios

| Servicio | Puerto | Descripción |
|---|---|---|
| opensips | 5060/udp, 5070/udp | SBC — carrierroute activo |
| freeswitch | 5080/udp | Media/VoxTrigger |
| haproxy | 8080, 8405 | WebSocket + métricas |
| opensips_exporter | 9434 | Métricas OpenSIPS |
| freeswitch_exporter | 9282 | Métricas FreeSWITCH |
| postgres | interno | DB OpenSIPS |

## OpenSIPS

- Config: `opensips/opensips.cfg` (desde `pwt.opensips/opensips.cfg.inout`)
- Routing egress: `cr_route` en `TO_CARRIER`
- Routing ingress: `dispatcher` set 101 → `freeswitch:5080`

## Seeds Postgres

Aplicados por el entrypoint de OpenSIPS al arranque:

- `opensips/postgres-seed/02-seed-carrierroute.sql` (route_tree + dispatcher)
- ACL (`address`) generada desde `OPENSIPS_ADDRESS_IP`
- Rutas carrier generadas desde `CARRIER_ROUTES`

Ejemplo por stack en `.env`:

```env
CARRIER_ROUTES=prefix:123,split:1;prefix:321,split:1
OPENSIPS_CARRIER_REWRITE_HOST=freeswitch:5080
```

Formato: rutas separadas por `;`, campos por `,` (`prefix`, `split`, `host` opcional).

Levantar instancias aisladas:

```bash
docker compose --env-file .env.stack1 -p stack1 up -d
docker compose --env-file .env.stack2 -p stack2 up -d
```

Después de cambiar rutas, reinicia OpenSIPS:

```bash
docker compose --env-file .env.stack1 -p stack1 restart opensips
```

## Smoke tests

```bash
curl -s localhost:9434/metrics | head
curl -s localhost:9282/metrics | head
curl -s localhost:8405/metrics | head
docker compose exec postgres psql -U postgres -d opensips -c 'SELECT * FROM carrierroute;'
```

## Notas RTP

En red bridge, RTP puede requerir `FS_EXTERNAL_RTP_IP` con la IP pública del host para audio real.
El rango RTP ahora se puede parametrizar por instancia con `FS_RTP_START_PORT` y `FS_RTP_END_PORT`.

## Multi-instancia (misma IP pública)

- Define `OPENSIPS_SIP_PORT` y `OPENSIPS_ALT_SIP_PORT` por instancia.
- `PWT_SBC_PORT` se toma automáticamente de `OPENSIPS_SIP_PORT` para evitar desalineación.
- Define también `FS_RTP_START_PORT` y `FS_RTP_END_PORT` por instancia para evitar colisiones RTP.
- La ACL de permisos (`address` grp 1) se configura con `OPENSIPS_ADDRESS_IP` en formato CIDR, separado por coma (ej. `203.0.113.1/32,203.0.113.2/24`). Default: `0.0.0.0/0`.
- Las rutas carrier se configuran en `CARRIER_ROUTES` por stack (ej. `prefix:123,split:1;prefix:321,split:1`).

## Notas técnicas

- El schema Postgres se aplica desde `/usr/share/opensips/postgres/*.sql` en el primer arranque.
- FreeSWITCH clona `pwt.freeswitch_vxt` en build (`FREESWITCH_GIT_URL`, `FREESWITCH_GIT_BRANCH`, `FREESWITCH_GIT_USER`, `FREESWITCH_GIT_TOKEN`).

### Build FreeSWITCH

```bash
# Tokens y repo ya en .env
DOCKER_BUILDKIT=1 docker compose build freeswitch freeswitch_exporter
docker compose up -d freeswitch freeswitch_exporter
```

## Debug SIP (sngrep)

Vista **limpia** del flujo completo en la bridge Docker (sin duplicados de `lo`/docker-proxy):

```
cliente ──INVITE──► OpenSIPS :5060 ──INVITE──► FreeSWITCH :5080
         ◄──100/180───              ◄──100/180/480───
```

```bash
# Terminal 1
docker compose --profile debug run --rm -it sip-debug

# Terminal 2 — siempre vía OpenSIPS (:5060), no directo a :5080
sipsak -f sip-debug/invite-external.sip -s sip:5255512345678@127.0.0.1 -r 5060 -v
```

En sngrep verás **3 columnas**: cliente → `10.0.5.x` (OpenSIPS) → `10.0.5.y` (FreeSWITCH).

| Variable | Qué ves |
|----------|---------|
| `SIP_CAPTURE=clean` | **default** — bridge, `:5060` + `:5080`, flujo completo |
| `SIP_CAPTURE=all` | Todas las interfaces (duplicados) |

```bash
SIP_CAPTURE=all docker compose --profile debug run --rm -it sip-debug
```

Atajos sngrep: `q` salir · `F2` filtro · `F3` buscar · `F5` guardar pcap

Fallback texto plano: `TCPDUMP=1 docker compose --profile debug run --rm -it sip-debug`

## Pruebas SIP con sipsak

**OPTIONS** (ping):
```bash
sipsak -s sip:OPT@127.0.0.1 -r 5060 -T
```

**INVITE** — no uses `-I`: en sipsak 0.9.8.1 hace **SEGV** (bug del binario, no del stack). Usa modo *shoot* con archivo:

```bash
# Edita sip-debug/invite-external.sip (número, IP LAN en Via/Contact/SDP)
sipsak -f sip-debug/invite-external.sip -s sip:5255512345678@127.0.0.1 -r 5060 -v
```

Flujo verificado: OpenSIPS `100` → FreeSWITCH responde (ej. `480` si el dialplan no enruta ese número).
