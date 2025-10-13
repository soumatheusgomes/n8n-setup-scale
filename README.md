# n8n-setup-scale · Self-host n8n with **Distributed Workers** + **Runners** (Traefik, Redis, optional Postgres, optional Browserless)

Complete automation stack: **n8n + Redis + Traefik (TLS via Cloudflare DNS) + optional PostgreSQL + optional Browserless Chrome**.
Supports **cloud/local** setups, **remote/local database**, **multiple workers**, and **Task Runners** sidecars.

---

## 🧭 Table of Contents
1. [Architecture](#architecture)
2. [Requirements](#requirements)
3. [Project Structure](#project-structure)
4. [Environment Variables (`.env`)](#environment-variables-env)
5. [Profiles & Deploy Modes](#profiles--deploy-modes)
6. [Main Deploy — `install.sh`](#main-deploy--installsh)
7. [Scaling: Workers & Runners](#scaling-workers--runners)
   - [Scale on the same host](#scale-on-the-same-host)
   - [Add worker-only servers (multi-host)](#add-worker-only-servers-multi-host)
8. [Traefik + TLS (Cloudflare DNS)](#traefik--tls-cloudflare-dns)
9. [Backup & Restore](#backup--restore)
10. [Upgrading versions](#upgrading-versions)
11. [Security & Best Practices](#security--best-practices)
12. [Troubleshooting](#troubleshooting)
13. [FAQ](#faq)
14. [License](#license)

---

## Architecture

### Primary stack

```
            (optional)
┌─────────┐  profile:tls   ┌────────────┐
│ Browser │─80/443───►────▶│  Traefik   │─────┐
│ less    │                └────────────┘     │
└─────────┘                                   ▼
                                          ┌────────────┐
                                          │    n8n     │  UI/Webhooks
                                          └────────────┘
                                               ▲   ▲
                 profile:dblocal               │   │ BullMQ (Redis)
      ┌──────────────────────────┐ 5432        │   │
      │        PostgreSQL        │◀────────────┘   │
      └──────────────────────────┘                 │
                                                   ▼
                                            ┌───────────┐
                                            │ n8n-worker│  (N replicas)
                                            └───────────┘
                                                   ▲
                                                   │ http://n8n-worker:5679
                                            ┌───────────┐
                                            │ Runners   │  (sidecar per worker,
                                            │ (N×k)     │   task executors)
                                            └───────────┘
                                                   ▲
                                                   │
                                            ┌───────────┐
                                            │   Redis   │
                                            └───────────┘
```

### Distributed workers (extra servers)

```
             ┌────────────── Server A ──────────────┐
             │ n8n + Redis + Traefik (+ Postgres)   │
             └──────────────────────────────────────┘
                         ▲  BullMQ  ▼
             ┌────────────── VPN / VPC ──────────────┐
             │                                       │
┌────────────┴─────────────┐         ┌───────────────┴────────────┐
│  Server B (workers)      │         │  Server C (workers)        │
│  n8n-worker × 6          │         │  n8n-worker × 8             │
│  runners × (6×k)         │         │  runners × (8×k)            │
└──────────────────────────┘         └─────────────────────────────┘
```

> All workers share the **same Redis** queue and the **same PostgreSQL** database, and **must** use the **same** `N8N_ENCRYPTION_KEY` as the main node.

---

## Requirements

- Docker Engine **20.10+**
- Docker Compose v2
- Git 2.x

---

## Project Structure

```
n8n-setup-scale/
├─ docker-compose.yml
├─ docker-compose.local.yml           # local overrides (dev/desktop)
├─ install.sh                         # main deploy (menu + scaling)
├─ .env.example
├─ LICENSE
└─ README.md
```

> This repository enables production-style runs and local testing via profiles and a helper installer.

---

## Environment Variables (`.env`)

Copy and edit:
```bash
cp .env.example .env
```

### Core (n8n / queue / runners)

| Variable | Example / Default | Required | Notes |
|---|---|---:|---|
| `N8N_VERSION` | `latest` | — | `n8nio/n8n` image tag. |
| `N8N_RUNNER_VERSION` | `1.116.0` | — | **Must match** the n8n release line for `n8nio/runners`. |
| `N8N_PROTOCOL` | `https` | ✅ | Public protocol (Traefik). |
| `N8N_HOST` | `n8n.your-domain.com` | ✅ | Public host for n8n. |
| `N8N_ENCRYPTION_KEY` | `...` | ✅ | n8n encryption key (32+ chars). |
| `GENERIC_TIMEZONE` | `America/Sao_Paulo` | ✅ | Default timezone for flows. |
| `EXECUTIONS_MODE` | `queue` | — | **Queue mode** (BullMQ/Redis) only. |
| `EXECUTIONS_DATA_SAVE_ON_ERROR` | `none` | — | Use `none` in prod for performance; switch to `all` for debugging. |
| `EXECUTIONS_DATA_SAVE_ON_SUCCESS` | `none` | — | Same as above. |
| `OFFLOAD_MANUAL_EXECUTIONS_TO_WORKERS` | `true` | — | Enqueue even manual UI runs to workers. |
| `N8N_RUNNERS_ENABLED` | `true` | ✅ | Enables **Task Runners**. |
| `N8N_RUNNERS_MODE` | `external` | — | Runners as external sidecars. |
| `N8N_RUNNERS_AUTH_TOKEN` | `...` | ✅ | **Shared secret** used by n8n and runners. |
| `RUNNERS_PER_WORKER` | `1` | — | Factor `k` for runner replicas per worker. |
| `N8N_NATIVE_PYTHON_RUNNER` | `true` | — | Enables Native Python Runner (beta). |

### Redis (BullMQ)

| Variable | Example | Required | Notes |
|---|---|---:|---|
| `REDIS_VERSION` | `7` | — | Image tag. |
| `REDIS_PASSWORD` | `...` | ✅ | Required; service uses `--requirepass`. |

### PostgreSQL (optional: profile `dblocal`)

| Variable | Example | Required | Notes |
|---|---|---:|---|
| `POSTGRES_VERSION` | `17` | — | Image tag. |
| `POSTGRES_HOST` | `postgres` or external host | ⚠️ | Leave **empty** to use local Postgres (profile `dblocal`). |
| `POSTGRES_PORT` | `5432` | — | Port. |
| `POSTGRES_DB` | `n8n` | — | Database name. |
| `POSTGRES_USER` | `n8n` | — | User. |
| `POSTGRES_PASSWORD` | `...` | — | Password. |
| `DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED` | `false` | — | For remote DBs without CA. |

### SMTP (optional)

`SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASS`, `SMTP_SENDER_NAME`, `SMTP_SENDER_EMAIL`

### Traefik + Cloudflare (TLS via DNS)

| Variable | Example | Required |
|---|---|---:|
| `TRAEFIK_VERSION` | `v3` | — |
| `TRAEFIK_DASHBOARD_DOMAIN` | `traefik.your-domain.com` | — |
| `TRAEFIK_DASHBOARD_AUTH` | `admin:...` | — |
| `CLOUDFLARE_DNS_API_TOKEN` | `...` | ✅ |
| `LETSENCRYPT_EMAIL` | `you@email.com` | ✅ |

Tip to generate `TRAEFIK_DASHBOARD_AUTH`:
```bash
echo "TRAEFIK_DASHBOARD_AUTH=admin:$(htpasswd -nbB admin 'YOUR_PASSWORD' | cut -d: -f2 | sed 's/\$/\$\$/g')"
```

### Browserless (optional)

`BROWSERLESS_VERSION`, `BROWSERLESS_TOKEN`

---

## Profiles & Deploy Modes

The `install.sh` modes map to Compose profiles:

| Mode (`install.sh`) | Compose profiles | HTTPS | Database | Public URL |
|---|---|---|---|---|
| `cloud-remote` | `tls` | ✅ | **remote** | `https://$N8N_HOST` |
| `cloud-docker` | `tls`, `dblocal` | ✅ | **local (container)** | `https://$N8N_HOST` |
| `localhost-remote` | `local` (override) | ❌ | **remote** | `http://localhost:5678` |
| `localhost-docker` | `dblocal` + `local` | ❌ | **local (container)** | `http://localhost:5678` |

> The installer sets `WEBHOOK_URL` automatically based on the selected mode.

---

## Main Deploy — `install.sh`

```bash
chmod +x install.sh

# Interactive: choose mode, number of workers and whether to include Browserless
./install.sh

# Non-interactive: 6 workers, cloud with remote Postgres
./install.sh cloud-remote 6
```

What the script does:

1. Reads/updates `.env` and sets `WEBHOOK_URL` for the chosen mode.
2. **Requires** `N8N_RUNNERS_AUTH_TOKEN` (runners are always on in this stack).
3. Computes `RUNNERS_SCALE = WORKERS × RUNNERS_PER_WORKER`.
4. Executes: `docker compose down --remove-orphans` → `pull` → `build` (n8n/worker) →
   `up -d` with `--scale n8n-worker=$WORKERS` and `--scale n8n-worker-runners=$RUNNERS_SCALE`.
5. Prunes dangling images.
6. Removes any stray Browserless container if not included.

Quick start checklist:

```bash
# 1) Clone & enter the repo
git clone https://github.com/soumatheusgomes/n8n-setup-scale.git
cd n8n-setup-scale

# 2) Prepare .env
cp .env.example .env
# Set: N8N_HOST, N8N_ENCRYPTION_KEY, REDIS_PASSWORD, N8N_RUNNERS_AUTH_TOKEN, etc.
# Generate secrets:
openssl rand -hex 32   # for N8N_RUNNERS_AUTH_TOKEN
openssl rand -base64 32  # for N8N_ENCRYPTION_KEY

# 3) Run installer
./install.sh cloud-remote 4
```

---

## Scaling: Workers & Runners

- **Workers** pull jobs from the **BullMQ** queue (Redis).
- **Runners** are sidecars attached to workers, connecting to the **Task Broker** exposed by the worker at `http://n8n-worker:5679`. They power features like the **Native Python Runner** and isolated heavy tasks.

> **Version match is critical**: `n8nio/runners:${N8N_RUNNER_VERSION}` must align with `n8nio/n8n:${N8N_VERSION}` (same release line).

### Scale on the same host

```bash
# Increase the number of workers:
docker compose up -d --scale n8n-worker=10

# Adjust Runners (remember RUNNERS_PER_WORKER):
docker compose up -d --scale n8n-worker-runners=20
```

### Add worker-only servers (multi-host)

Use additional machines exclusively for workers+runners pointing to the **central Redis/Postgres**:

1. **Replicate secrets/configs** on each worker server:
   - Use the **same** `N8N_ENCRYPTION_KEY` as the main node.
   - Set Redis and Postgres to the **same** central instances (host/port/user/pass).
   - Use the **same** `N8N_RUNNERS_AUTH_TOKEN`.
   - Ensure network connectivity (VPN/VPC or firewall openings) from worker servers to Redis/Postgres.

2. **Minimal compose for worker-only hosts** (create `docker-compose.worker.yml` on the worker server):
   ```yaml
   version: "3.9"

   services:
     n8n-worker:
       image: n8nio/n8n:${N8N_VERSION:-latest}
       command: worker
       restart: unless-stopped
       environment:
         NODE_ENV: production
         N8N_PROXY_HOPS: "1"

         # Queue/Workers
         N8N_RUNNERS_ENABLED: "true"
         N8N_RUNNERS_MODE: external
         N8N_RUNNERS_BROKER_LISTEN_ADDRESS: "0.0.0.0"
         N8N_RUNNERS_AUTH_TOKEN: ${N8N_RUNNERS_AUTH_TOKEN}
         N8N_NATIVE_PYTHON_RUNNER: "true"

         # Base URL (not used by worker for UI)
         GENERIC_TIMEZONE: ${GENERIC_TIMEZONE:-UTC}

         # Queue (central Redis)
         EXECUTIONS_MODE: queue
         QUEUE_BULL_REDIS_HOST: ${QUEUE_REDIS_HOST}
         QUEUE_BULL_REDIS_PASSWORD: ${REDIS_PASSWORD}
         QUEUE_HEALTH_CHECK_ACTIVE: "true"

         # Postgres (central)
         DB_TYPE: postgresdb
         DB_POSTGRESDB_HOST: ${POSTGRES_HOST}
         DB_POSTGRESDB_PORT: ${POSTGRES_PORT:-5432}
         DB_POSTGRESDB_DATABASE: ${POSTGRES_DB}
         DB_POSTGRESDB_USER: ${POSTGRES_USER}
         DB_POSTGRESDB_PASSWORD: ${POSTGRES_PASSWORD}
         DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED: ${DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED:-false}

         # n8n crypto
         N8N_ENCRYPTION_KEY: ${N8N_ENCRYPTION_KEY}

         # Offload everything
         OFFLOAD_MANUAL_EXECUTIONS_TO_WORKERS: "true"
       networks:
         - backend

     n8n-worker-runners:
       image: n8nio/runners:${N8N_RUNNER_VERSION:-latest}
       restart: unless-stopped
       environment:
         N8N_RUNNERS_TASK_BROKER_URI: "http://n8n-worker:5679"
         N8N_RUNNERS_AUTH_TOKEN: ${N8N_RUNNERS_AUTH_TOKEN}
         N8N_RUNNERS_LAUNCHER_LOG_LEVEL: info
         N8N_RUNNERS_AUTO_SHUTDOWN_TIMEOUT: "15"
       depends_on:
         - n8n-worker
       networks:
         - backend

   networks:
     backend:
       driver: bridge
   ```

   Create a `.env` on the worker server with **central** endpoints:
   ```dotenv
   N8N_VERSION=latest
   N8N_RUNNER_VERSION=1.116.0

   # central Redis
   QUEUE_REDIS_HOST=10.0.0.10        # IP/hostname of the Redis on Server A
   REDIS_PASSWORD=your_redis_password

   # central Postgres
   POSTGRES_HOST=10.0.0.11
   POSTGRES_PORT=5432
   POSTGRES_DB=n8n
   POSTGRES_USER=n8n
   POSTGRES_PASSWORD=your_pg_password
   DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED=false

   # shared n8n secrets
   N8N_ENCRYPTION_KEY=your_encryption_key
   N8N_RUNNERS_AUTH_TOKEN=your_runners_token

   GENERIC_TIMEZONE=America/Sao_Paulo
   ```

   Bring up the worker host (example: 6 workers and 6 runners):
   ```bash
   docker compose -f docker-compose.worker.yml up -d \
     --scale n8n-worker=6 \
     --scale n8n-worker-runners=6
   ```

3. Repeat on as many worker servers as you need; all compete for jobs in the shared BullMQ queue.

---

## Traefik + TLS (Cloudflare DNS)

- Certificates via **ACME DNS-01** (Cloudflare). Ensure:
  - Ports **80/443** open on the Traefik host.
  - `CLOUDFLARE_DNS_API_TOKEN` has **Zone.DNS Read/Edit** for your domain zone.
  - `LETSENCRYPT_EMAIL` is valid.
- Optional Traefik dashboard with BasicAuth at `https://$TRAEFIK_DASHBOARD_DOMAIN`.

---

## Backup & Restore

| Item | Backup | Restore |
|---|---|---|
| n8n workflows & credentials | `docker cp $(docker compose ps -q n8n):/home/node/.n8n ./backup` | `docker cp ./backup/. $(docker compose ps -q n8n):/home/node/.n8n` |
| Local Postgres (profile `dblocal`) | `docker exec postgres pg_dump -U $POSTGRES_USER $POSTGRES_DB > dump.sql` | `docker exec -i postgres psql -U $POSTGRES_USER -d $POSTGRES_DB < dump.sql` |

> Stop n8n during critical restores to ensure consistency.

---

## Upgrading versions

1. Update in `.env`:
   - `N8N_VERSION` **and** `N8N_RUNNER_VERSION` (matching release line).
2. Redeploy with your usual mode:
   ```bash
   ./install.sh cloud-remote 6
   ```
3. The installer will `pull` and recreate services with new tags.

---

## Security & Best Practices

- Use long random secrets for `N8N_ENCRYPTION_KEY`, `REDIS_PASSWORD`, `N8N_RUNNERS_AUTH_TOKEN`.
- **Do not** expose Redis/Postgres publicly; keep them on private networks/VPC.
- Protect the Traefik dashboard with BasicAuth and a dedicated subdomain.
- In production, keep `EXECUTIONS_DATA_SAVE_* = none`; temporarily switch to `all` only when debugging.
- Schedule **regular backups** of `.n8n` and the database.
- Keep images updated (`install.sh` runs `pull` for you).

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Workers on extra hosts stay idle | Wrong Redis/Postgres host/creds or blocked network | Verify `.env`, routes/VPN/VPC/firewalls. |
| Runners fail with 401/403 | Mismatched `N8N_RUNNERS_AUTH_TOKEN` | Use the **same** token on n8n and runners. |
| Runner ↔ n8n incompatibility | Version mismatch | Align `N8N_VERSION` and `N8N_RUNNER_VERSION`. |
| 502 from Traefik when opening n8n | n8n still booting | `docker compose logs -f n8n`. |
| TLS issuance fails | Port 80 blocked / wrong DNS / invalid CF token | Open port 80, fix DNS A/AAAA, ensure CF token scope. |
| Manual executions hang in UI | UI does not run jobs locally | `OFFLOAD_MANUAL_EXECUTIONS_TO_WORKERS=true` (already set) + ensure workers are up. |

---

## FAQ

**What’s the difference between *workers* and *runners*?**
Workers execute **n8n workflows** pulled from the **BullMQ** queue (Redis). Runners execute **isolated tasks** (e.g., Native Python Runner) via the worker’s **Task Broker** (`:5679`).

**Do I need a domain?**
No. Use `localhost-*` modes for plain HTTP access during local testing.

**When should I use local Postgres (profile `dblocal`)?**
For simple/local environments. For multi-host or production, prefer an external/managed Postgres.

---

## License

MIT — third‑party images retain their own licenses.
