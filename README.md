# n8n‑Stack · Docker Compose **multi‑environment** (Distributed Workers)

End‑to‑end automation stack: **n8n + Redis + Browserless Chrome + optional PostgreSQL + optional Traefik TLS**  
Supports cloud/local, remote/local database **and extra worker‑only nodes**.

---

## 📑 Table of Contents
1. [Architecture](#architecture)
2. [Prerequisites](#prerequisites)
3. [Project Structure](#project-structure)
4. [`.env` Variables](#env-variables)
5. [Profiles & Deploy Modes](#profiles--deploy-modes)
6. [Main Deploy – `update-stack.sh`](#main-deploy--update-stacksh)
7. [Workers](#workers)
   * [Scaling on the same host](#scaling-on-the-same-host)
   * [Adding worker‑only servers](#adding-worker-only-servers)
8. [Backup & Restore](#backup--restore)
9. [Troubleshooting](#troubleshooting)
10. [FAQ](#faq)
11. [License](#license)

---

## Architecture

### Primary stack

```
            ( optional )
┌─────────┐ profiles:tls  ┌────────────┐
│ Browser │─80/443───►───▶│  Traefik   │─────┐
└─────────┘               └────────────┘     │
                                             ▼
                                      ┌────────────┐
                                      │     n8n    │ UI
                                      └────────────┘
                                           ▲  ▲
          profiles:dblocal                 │  │ BullMQ
   ┌───────────────────────┐ 5432          │  │
   │      PostgreSQL       │◀──────────────┘  │
   └───────────────────────┘                  │
                                              ▼
                                        ┌───────────┐
                                        │ n8n-worker│ (N replicas)
                                        └───────────┘
                                               ▲
                                               │
                                        ┌───────────┐
                                        │   Redis   │
                                        └───────────┘
```

### Distributed workers (extra servers)

```
             ┌────────────── Server A ───────────────┐
             │  n8n + Redis + Traefik (+ Postgres)   │
             └───────────────────────────────────────┘
                          ▲  BullMQ  ▼
             ┌────────────── VPN / VPC ───────────────┐
             │                                        │
┌────────────┴─────────────┐         ┌────────────────┴────────────┐
│   Server B  (workers)    │         │    Server C   (workers)     │
│     n8n-worker × 6       │         │    n8n-worker × 8           │
└──────────────────────────┘         └─────────────────────────────┘
```

*All workers share the very same **Redis** queue and **PostgreSQL** database, using the identical encryption key.*

---

## Prerequisites

* Docker Engine 20.10+  
* Docker Compose v2 (included with Docker Desktop)  
* Git 2.x  

---

## Project Structure

```
n8n-stack/
├─ docker-compose.yml
├─ docker-compose.local.yml
├─ Dockerfile
├─ update-stack.sh           # main deploy (menu + workers)
├─ deploy-workers-only.sh    # worker‑only nodes
├─ .env.example
└─ secrets/
   ├─ n8n_encryption_key.txt
   ├─ redis_password.txt
   └─ postgres_password.txt  # only when dblocal profile is used
```

---

## `.env` Variables

```dotenv
N8N_PROTOCOL=http            # http | https
N8N_HOST=localhost           # domain or public IP
GENERIC_TIMEZONE=America/Sao_Paulo
EMAIL=admin@example.com      # Let's Encrypt (https)

# Remote DB (leave POSTGRES_HOST empty to use dblocal profile)
POSTGRES_HOST=
POSTGRES_PORT=5432
POSTGRES_DB=n8n
POSTGRES_USER=n8n
POSTGRES_PASSWORD=change_me

# Browserless
BROWSERLESS_TOKEN=demo-token
```

`WEBHOOK_URL` is optional—set it only if you expose n8n on a non‑default port.

---

## Profiles & Deploy Modes

| Mode (`update-stack.sh`) | Docker profiles | HTTPS | Database | Public URL |
|--------------------------|-----------------|-------|----------|------------|
| `cloud-remote` | `tls` | ✅ | remote | `https://your.domain` |
| `cloud-local`  | `tls`, `dblocal` | ✅ | container | id. |
| `local-remote` | desktop override | ❌ | remote | `http://localhost:5678` |
| `local-local`  | `dblocal` + override | ❌ | container | id. |

---

## Main Deploy – `update-stack.sh`

```bash
chmod +x update-stack.sh

# Interactive: choose mode + number of workers (default 4)
./update-stack.sh

# Non‑interactive:
./update-stack.sh cloud-remote 6
```

What it does:

1. **Interactive menu** → mode & desired workers.  
2. Creates/updates secrets.  
3. `docker compose down` → `pull` → `build` → `up -d --scale n8n-worker=N`.  
4. Cleans dangling images.

---

## Workers

### Scaling on the same host

```bash
docker compose up -d --scale n8n-worker=10
```

### Adding worker‑only servers

1. **On worker server (B):**

   * Copy **`secrets/n8n_encryption_key.txt`** and **`redis_password.txt`** from server A.
   * Create `.env` with the **same** Redis and Postgres credentials (HOST, PORT, USER, PASS).

2. **Run the script**

   ```bash
   chmod +x deploy-workers-only.sh
   ./deploy-workers-only.sh        # prompts for amount (default 4)
   ./deploy-workers-only.sh 8      # non‑interactive, 8 replicas
   ```

   The script generates a minimal `docker-compose.worker.yml`, pulls the image and launches the requested replicas—without Redis, Traefik or Postgres locally.

3. **Repeat** on any additional server. All workers compete for the shared BullMQ queue.

---

## Backup & Restore

| Item | Backup | Restore |
|------|--------|---------|
| n8n workflows & creds | `docker cp $(docker compose ps -q n8n):/home/node/.n8n ./backup` | copy back |
| Local Postgres | `docker exec postgres pg_dump -U $POSTGRES_USER $POSTGRES_DB > dump.sql` | `docker exec -i postgres psql -U $POSTGRES_USER -d $POSTGRES_DB < dump.sql` |

---

## Troubleshooting

| Issue | Likely cause | Fix |
|-------|--------------|-----|
| Workers on server B idle | wrong Redis / Postgres host or password | check `.env` + secrets |
| 502 Bad Gateway | n8n still booting | `docker compose logs -f n8n` |
| TLS cert fails | port 80 blocked / wrong DNS | open port or fix A record |

---

## FAQ

<details>
<summary>Can I run without a domain?</summary>
Yes — use any `local-*` mode; you’ll access via plain HTTP.
</details>

<details>
<summary>Do I need WEBHOOK_URL?</summary>
Only if your external port differs from 80/443/5678.
</details>

<details>
<summary>How do I add custom nodes?</summary>
Edit the Dockerfile and `npm install your-node-package`.
</details>

---

## License

MIT — third‑party images retain their own licenses.
