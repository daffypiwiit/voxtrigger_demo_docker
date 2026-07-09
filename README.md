# docker_demo_pwt — Stack SIP Piwiit

Stack Docker Compose: **OpenSIPS** (carrierroute) + **PostgreSQL** + **FreeSWITCH** + **HAProxy** (WebSocket VoxTrigger) + exporters Prometheus.

## Requisitos

- Docker + Docker Compose v2
- BuildKit (`DOCKER_BUILDKIT=1`)
- Build FreeSWITCH: `SIGNALWIRE_TOKEN`, `FREESWITCH_GIT_USER`, `FREESWITCH_GIT_TOKEN` en `.env`
- Exporters: binarios en `exporters/bin/` (copiados desde ansible-control)

## Archivos clave

| Archivo | Uso |
|---|---|
| `docker-compose.yml` | Desarrollo local — build + run |
| `docker-compose.portainer.yml` | Portainer — solo imágenes pre-build, sin `build:` |
| `.env.example` | Plantilla local (incluye tokens de build) |
| `.env.cliente-a.example` | Variables runtime stack `cliente-a` |
| `.env.cliente-b.example` | Variables runtime stack `cliente-b` |
| `scripts/sngrep-stack.sh` | sngrep por nombre de stack (Portainer / multi-stack) |

---

## Arranque local (CLI)

```bash
cp .env.example .env
# Editar: SIGNALWIRE_TOKEN, FREESWITCH_GIT_TOKEN, FREESWITCH_GIT_USER

# Copiar exporters (si aplica)
# cp opensips_exporter freeswitch_exporter → exporters/bin/

DOCKER_BUILDKIT=1 docker compose build
docker compose up -d
```

---

## Portainer (recomendado)

Portainer CE no construye bien imágenes con `build:` + contexto Git. Flujo híbrido:

### 1. Build en el host Docker (una vez o cuando cambie código)

```bash
git clone https://github.com/daffypiwiit/voxtrigger_demo_docker.git
cd voxtrigger_demo_docker
cp .env.example .env   # tokens de build

DOCKER_BUILDKIT=1 docker compose build
docker images | grep voxtrigger_demo_docker
```

Imágenes esperadas:

- `voxtrigger_demo_docker-opensips:latest`
- `voxtrigger_demo_docker-freeswitch:latest`
- `voxtrigger_demo_docker-haproxy:latest`
- `voxtrigger_demo_docker-opensips_exporter:latest`
- `voxtrigger_demo_docker-freeswitch_exporter:latest`

### 2. Deploy en Portainer

| Campo | Valor |
|---|---|
| Stack name | `cliente-a`, `cliente-b`, etc. (define red `{nombre}_sip_net`) |
| Git repository | este repo |
| Compose path | `docker-compose.portainer.yml` |
| Environment variables | cargar `.env.cliente-a.example` o `.env.cliente-b.example` |

**No** hace falta `SIGNALWIRE_TOKEN` ni `FREESWITCH_GIT_TOKEN` en Portainer si las imágenes ya están construidas.

### 3. Actualizar solo variables (sin rebuild)

Cambios en Portainer → Environment variables → **Update stack** / redeploy:

- `CARRIER_ROUTES`, `OPENSIPS_SIP_PORT`, `HAPROXY_BACKEND_SERVERS`
- `FS_EXTERNAL_RTP_IP`, `MEDIA_OUT`, `VXT_ANSWER_DETECT`, etc.

Tras cambiar rutas carrier o ACL, **reinicia OpenSIPS**:

```bash
docker restart cliente-a-opensips-1
```

---

## Cuándo hacer rebuild vs redeploy

| Cambio | Acción |
|---|---|
| Variables `.env` runtime (puertos, rutas, RTP, VoxTrigger) | **Redeploy / restart** en Portainer. Rebuild **no** |
| `CARRIER_ROUTES`, `SRC_IP_WHITELIST` | Redeploy + **`docker restart …-opensips-1`** |
| `opensips/`, `haproxy/`, Dockerfiles, `opensips.cfg` | **`docker compose build`** + redeploy Portainer |
| Repo Bitbucket FreeSWITCH (`pwt.freeswitch_vxt`) | **`docker compose build freeswitch`** + redeploy |
| Tokens SignalWire / Bitbucket (solo build) | Rebuild **freeswitch** |
| `exporters/bin/` | Rebuild **opensips_exporter** / **freeswitch_exporter** |
| `sip-debug/` | `docker build -t docker_demo_pwt/sip-debug:latest ./sip-debug` |
| `docker-compose.portainer.yml` (puertos, servicios) | Redeploy stack (sin rebuild imágenes) |

```bash
# Rebuild completo
DOCKER_BUILDKIT=1 docker compose build

# Rebuild parcial
DOCKER_BUILDKIT=1 docker compose build opensips haproxy
DOCKER_BUILDKIT=1 docker compose build freeswitch freeswitch_exporter
docker build -t docker_demo_pwt/sip-debug:latest ./sip-debug
```

---

## Servicios y puertos expuestos

Solo se publican al **host** los servicios de borde. El resto es red interna `sip_net`.

| Servicio | Expuesto al host | Interno (`sip_net`) |
|---|---|---|
| opensips | `OPENSIPS_SIP_PORT` / `OPENSIPS_ALT_SIP_PORT` (udp/tcp) | `:5060`, `:5070` (configurable) |
| freeswitch | — | `:5080` SIP, `:8021` ESL |
| haproxy | — | `:8080` WebSocket VoxTrigger |
| opensips_exporter | `OPENSIPS_EXPORTER_PORT` (default 9434) | `:9434` |
| freeswitch_exporter | `FREESWITCH_EXPORTER_PORT` (default 9282) | `:9282` |
| postgres | — | `:5432` |

FreeSWITCH y HAProxy se alcanzan por hostname Docker: `freeswitch`, `haproxy`.

---

## Multi-stack (misma IP pública)

Cada stack en Portainer = proyecto Compose aislado (red, volúmenes, contenedores propios).  
**Los puertos del host deben ser únicos** por stack.

Plantillas: `.env.cliente-a.example`, `.env.cliente-b.example`

| Variable | cliente-a | cliente-b |
|---|---|---|
| Stack name (Portainer) | `cliente-a` | `cliente-b` |
| `OPENSIPS_SIP_PORT` | 5060 | 5160 |
| `OPENSIPS_ALT_SIP_PORT` | 5070 | 5170 |
| `OPENSIPS_EXPORTER_PORT` | 9434 | 9435 |
| `FREESWITCH_EXPORTER_PORT` | 9282 | 9283 |
| `FS_RTP_START_PORT` / `FS_RTP_END_PORT` | 16384–24576 | 24577–32768 |
| `CARRIER_ROUTES` | ver `.env` | ver `.env` |
| `POSTGRES_PASSWORD` | distinto por stack | distinto por stack |

CLI equivalente:

```bash
docker compose -f docker-compose.portainer.yml --env-file .env.cliente-a.example -p cliente-a up -d
docker compose -f docker-compose.portainer.yml --env-file .env.cliente-b.example -p cliente-b up -d
```

### Postgres: contraseña y volumen

`POSTGRES_PASSWORD` solo aplica en el **primer** arranque del volumen `pgdata`. Si cambias la contraseña después:

- Borra el volumen del stack y redeploy limpio, **o**
- `ALTER USER postgres PASSWORD '…'` dentro del contenedor postgres

---

## OpenSIPS — routing

- **Ingress** (cliente → VoxTrigger): `dispatcher` set 101 → `sip:freeswitch:5080`
- **Egress** (servicio → carrier/PBX): `cr_route` en `TO_CARRIER` → `CARRIER_ROUTES`

### Formato `CARRIER_ROUTES`

Cada ruta **obliga** tres campos: `prefix`, `split`, `host`. Rutas separadas por `;`:

```env
# Una ruta — PBX externo
CARRIER_ROUTES=prefix:52,split:2,host:pbx-lab.piwiit.com:5080

# Varias rutas (cada una con prefix, split, host)
CARRIER_ROUTES=prefix:123,split:1,host:pbx-lab.piwiit.com:5080;prefix:321,split:1,host:otro-pbx.example.com:5080
```

Si falta `prefix`, `split` o `host`, el entrypoint de OpenSIPS **falla al arrancar**.

Verificar rutas cargadas:

```bash
docker exec -it cliente-a-opensips-1 opensips-cli -x mi cr_dump_routes
```

### Egress a dominio público

Si `rewrite_host` es un FQDN externo, OpenSIPS debe **resolverlo desde el contenedor**:

```bash
docker exec -it cliente-a-opensips-1 getent hosts pbx-lab.piwiit.com
```

Si falla DNS → SIP **476 Unresolvable destination**. Soluciones:

- DNS público real (A/AAAA) accesible desde el contenedor
- `extra_hosts` en compose apuntando al PBX
- `host:IP:5080` en `CARRIER_ROUTES` si no hay DNS

Seeds aplicados al arrancar OpenSIPS (entrypoint):

- Schema base OpenSIPS en Postgres
- `opensips/postgres-seed/02-seed-carrierroute.sql` (route_tree + dispatcher)
- ACL (`address`) desde `SRC_IP_WHITELIST`
- `carrierroute` desde `CARRIER_ROUTES`

---

## Logs OpenSIPS

```bash
docker logs -f cliente-a-opensips-1
```

En Portainer: contenedor `opensips` → **Logs**.

`opensips.cfg` usa syslog (`stderror_enabled=no`). Los `xlog` de llamadas pueden no aparecer en `docker logs`; ahí se ven arranque, seeds y errores del entrypoint. Para debug SIP en vivo usar sngrep (abajo).

---

## Smoke tests

```bash
# Métricas (puerto según stack)
curl -s localhost:9434/metrics | head
curl -s localhost:9282/metrics | head

# DB rutas
docker exec -it cliente-a-postgres-1 psql -U postgres -d opensips -c 'SELECT * FROM carrierroute;'
```

---

## Debug SIP (sngrep)

### Por stack (Portainer / multi-stack)

Build imagen debug (una vez o tras cambios en `sip-debug/`):

```bash
docker build -t docker_demo_pwt/sip-debug:latest ./sip-debug
```

```bash
./scripts/sngrep-stack.sh              # lista stacks + puerto SIP
./scripts/sngrep-stack.sh cliente-a
./scripts/sngrep-stack.sh cliente-b

# Salidas a PBX externo (no pasa por bridge interna)
SIP_CAPTURE=all ./scripts/sngrep-stack.sh cliente-a

# tcpdump
TCPDUMP=1 ./scripts/sngrep-stack.sh cliente-a
```

El script detecta puertos `OPENSIPS_SIP_PORT` del contenedor OpenSIPS del stack.

### Flujo interno (ingress → FreeSWITCH)

```
cliente ──INVITE──► OpenSIPS :5060 ──INVITE──► FreeSWITCH :5080
         ◄──100/180───              ◄──100/180/480───
```

### Compose local (profile debug)

```bash
docker compose --profile debug run --rm -it sip-debug
```

| Variable | Efecto |
|---|---|
| `SIP_CAPTURE=clean` | Bridge del stack — `:SIP_PORT` + `:5080` |
| `SIP_CAPTURE=all` | Todas las interfaces (tráfico externo, duplicados) |

Atajos sngrep: `q` salir · `F2` filtro · `F3` buscar · `F5` guardar pcap

---

## Pruebas SIP con sipsak

Usar el **puerto SIP del stack** (`OPENSIPS_SIP_PORT`):

```bash
# cliente-a → 5060
sipsak -s sip:OPT@127.0.0.1 -r 5060 -T
sipsak -f sip-debug/invite-external.sip -s sip:5255512345678@127.0.0.1 -r 5060 -v

# cliente-b → 5160
sipsak -f sip-debug/invite-external.sip -s sip:5255512345678@127.0.0.1 -r 5160 -v
```

**INVITE:** no uses `-I` (SEGV en sipsak 0.9.8.1). Usa `-f` con archivo.

Siempre vía OpenSIPS, no directo a `:5080`.

---

## Notas RTP

En red bridge, audio real puede requerir `FS_EXTERNAL_RTP_IP` con la IP pública del host.  
Parametrizar rango RTP por stack: `FS_RTP_START_PORT`, `FS_RTP_END_PORT`.

---

## Notas técnicas

- FreeSWITCH clona `pwt.freeswitch_vxt` en build (`FREESWITCH_GIT_*`).
- `PWT_SBC_PORT` en FreeSWITCH se alinea con `OPENSIPS_SIP_PORT` del stack.
- Hostnames internos fijos por stack: `opensips`, `haproxy`, `freeswitch`, `postgres`.
