# Windmill on Proxmox

Target: a dedicated Debian 13.6 (`trixie`) VM with 2 vCPU, 4 GiB RAM,
32 GiB disk, and a working network. Windmill has its own minimal Traefik
instance, following the existing homelab Traefik configuration. Only Traefik
publishes host ports: TCP/80 for redirects and TCP/443 for HTTPS.

Before installation:

1. Create a Cloudflare DNS record for `<REDACTED>` pointing to the
   public IP.
2. Ensure the home network can reach the VM on TCP/80 and TCP/443.
3. Create a Cloudflare API token restricted to your domain's zone with
   **Zone / DNS / Edit** and **Zone / Zone / Read**.

## Complete installation

Run from a root shell immediately after the initial `apt update`. The block asks
for the ACME email and Cloudflare token without placing them in shell history.

```bash
set -euo pipefail

apt install -y ca-certificates curl openssl

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

ARCH="$(dpkg --print-architecture)"
cat > /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: trixie
Components: stable
Architectures: ${ARCH}
Signed-By: /etc/apt/keyrings/docker.asc
EOF

apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker

install -d -m 0700 /opt/windmill/env
cd /opt/windmill

POSTGRES_PASSWORD="$(openssl rand -hex 32)"
read -rp "Cloudflare account email: " CF_API_EMAIL
read -rsp "Cloudflare DNS API token: " CF_DNS_API_TOKEN
echo

cat > .env <<EOF
WM_IMAGE=ghcr.io/windmill-labs/windmill:main
CF_API_EMAIL=${CF_API_EMAIL}
CF_DNS_API_TOKEN=${CF_DNS_API_TOKEN}
EOF

cat > env/postgres.env <<EOF
POSTGRES_DB=windmill
POSTGRES_USER=windmill
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
EOF

cat > env/server.env <<EOF
DATABASE_URL=postgresql://windmill:${POSTGRES_PASSWORD}@postgres-windmill:5432/windmill?sslmode=disable
MODE=server
EOF

cat > env/worker.env <<EOF
DATABASE_URL=postgresql://windmill:${POSTGRES_PASSWORD}@postgres-windmill:5432/windmill?sslmode=disable
MODE=worker
WORKER_GROUP=default
FAVOR_UNSHARE_PID=true
EOF

chmod 600 .env env/postgres.env env/server.env env/worker.env
unset POSTGRES_PASSWORD CF_API_EMAIL CF_DNS_API_TOKEN

cat > docker-compose.yml <<'COMPOSE'
name: windmill

networks:
  windmill:
    driver: bridge
  proxy:
    driver: bridge

volumes:
  postgres_data:
  worker_cache:
  worker_logs:
  traefik_acme:

services:
  traefik:
    image: traefik:v3
    container_name: windmill-traefik
    hostname: windmill-traefik
    restart: unless-stopped
    networks:
      - proxy
    ports:
      - "80:80"
      - "443:443"
    env_file: .env
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - traefik_acme:/acme
    command:
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.web.http.redirections.entrypoint.to=websecure"
      - "--entrypoints.web.http.redirections.entrypoint.scheme=https"
      - "--entrypoints.websecure.address=:443"
      - "--certificatesresolvers.cloudflare.acme.dnschallenge=true"
      - "--certificatesresolvers.cloudflare.acme.dnschallenge.provider=cloudflare"
      - "--certificatesresolvers.cloudflare.acme.email=${CF_API_EMAIL}"
      - "--certificatesresolvers.cloudflare.acme.storage=/acme/acme.json"
      - "--log.level=INFO"
      - "--accesslog=true"

  postgres-windmill:
    image: postgres:18-alpine
    container_name: postgres-windmill
    hostname: postgres-windmill
    restart: unless-stopped
    shm_size: 1g
    networks:
      - windmill
    env_file: ./env/postgres.env
    volumes:
      - postgres_data:/var/lib/postgresql
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U windmill -d windmill"]
      interval: 10s
      timeout: 5s
      retries: 10

  windmill-server:
    image: ${WM_IMAGE}
    container_name: windmill-server
    hostname: windmill-server
    restart: unless-stopped
    networks:
      - windmill
      - proxy
    env_file: ./env/server.env
    depends_on:
      postgres-windmill:
        condition: service_healthy
    volumes:
      - worker_logs:/tmp/windmill/logs
    labels:
      - "traefik.enable=true"
      - "traefik.docker.network=windmill_proxy"
      - "traefik.http.routers.windmill.rule=Host(`<REDACTED>`)"
      - "traefik.http.routers.windmill.entrypoints=websecure"
      - "traefik.http.routers.windmill.tls.certresolver=cloudflare"
      - "traefik.http.services.windmill.loadbalancer.server.port=8000"

  windmill-worker:
    image: ${WM_IMAGE}
    container_name: windmill-worker
    hostname: windmill-worker
    restart: unless-stopped
    privileged: true
    networks:
      - windmill
    env_file: ./env/worker.env
    depends_on:
      postgres-windmill:
        condition: service_healthy
    volumes:
      - worker_cache:/tmp/windmill/cache
      - worker_logs:/tmp/windmill/logs
COMPOSE

docker compose config --quiet
docker compose pull
docker compose up -d
docker compose ps

echo
echo "Windmill UI: https://<REDACTED>"
echo "Check after startup: curl -fsS https://<REDACTED>/api/version"
```

## Configuration files

- `.env`: Windmill image plus Traefik's `CF_API_EMAIL` and
  `CF_DNS_API_TOKEN`.
- `env/postgres.env`: PostgreSQL database, user, and password.
- `env/server.env`: Windmill server mode and database URL.
- `env/worker.env`: Windmill worker mode, group, isolation, and database URL.

Examples for every file are committed beside the Compose file. Real `.env`
files are ignored by Git and created with mode `600`.

## Storage and networking

PostgreSQL 18 stores its named volume at `/var/lib/postgresql`; the older
`/var/lib/postgresql/data` target is incorrect for PostgreSQL 18.

`shm_size: 1g` increases PostgreSQL's `/dev/shm` ceiling from Docker's 64 MiB
default. It does not reserve 1 GiB of RAM.

Docker named volumes store PostgreSQL, the dependency cache, job logs, and
Traefik ACME state. Docker manages their paths and ownership. `docker compose
down` preserves them; `docker compose down --volumes` deletes them.

Only Traefik publishes `80:80` and `443:443`; port 80 performs a global redirect
to HTTPS. PostgreSQL, Windmill port 8000, and the worker remain accessible only
on their Docker networks. Traefik mounts the Docker socket for discovery; the
Windmill worker does not.

## First login

Open <https://<REDACTED>>, change the bootstrap password, then:

1. Set `https://<REDACTED>` as **Base URL** in instance settings.
2. Create the workspace and its operator/automation groups.
3. Run a small Python script and confirm its output and logs in the UI.

## Deepgram and Supabase secrets

Credentials belong in secret Windmill Variables referenced by shared Resources,
not in the deployment environment files.

1. Create secret Variables:
   - `f/integrations/deepgram_api_key`
   - `f/integrations/supabase_service_role_key`
2. Create or select Resource types:
   - `deepgram`: `api_key`
   - `supabase`: `url`, `service_role_key`
3. Create `f/integrations/deepgram_prod` and
   `f/integrations/supabase_prod` Resources.
4. Use **Insert variable** for the credential fields.
5. Grant both the Resource and referenced Variable only to the automation group
   or folder executing the scripts.

## Operations

```bash
cd /opt/windmill
docker compose ps
docker compose logs --tail=100 traefik postgres-windmill windmill-server windmill-worker
curl -fsS https://<REDACTED>/api/version
```

Create a PostgreSQL backup:

```bash
cd /opt/windmill
mkdir -p backups
docker compose exec -T postgres-windmill pg_dump -U windmill -d windmill -Fc > "backups/windmill-$(date +%F-%H%M%S).dump"
```

Update the rolling `main` images:

```bash
cd /opt/windmill
docker compose stop windmill-worker
docker compose pull
docker compose up -d
docker compose ps
```

## Sources

- [Docker Engine installation on Debian](https://docs.docker.com/engine/install/debian/)
- [PostgreSQL official image documentation](https://github.com/docker-library/docs/blob/master/postgres/README.md)
- [Windmill self-hosting documentation](https://www.windmill.dev/docs/advanced/self_host)