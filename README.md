# n8n Production Setup

**Production-ready n8n deployment with workers, task runners, and automatic TLS.**

[![Docker](https://img.shields.io/badge/Docker-20.10+-blue.svg)](https://www.docker.com/)
[![n8n](https://img.shields.io/badge/n8n-latest-orange.svg)](https://n8n.io/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

---

## 🎯 What is This?

A complete Docker Compose setup for self-hosting **n8n** with:

- **Scalable Workers**: Scale workflow execution with multiple workers
- **Task Runners**: Isolated Python execution and heavy workload processing
- **Automatic TLS**: Let's Encrypt certificates via Cloudflare DNS
- **Queue-based**: BullMQ/Redis for distributed job processing
- **Production-ready**: Health checks, restarts, and security best practices

Perfect for high-traffic workflows, long-running automations, and production environments.

---

## 📊 Architecture

```
Internet
   │
   ├─── Traefik (HTTPS) ───► n8n (UI/Webhooks)
   │                              │
   │                              │
   │                          PostgreSQL
   │                              │
   │                              ▼
   └──────────────────────► Redis Queue
                                  │
                                  ▼
                          Workers (scalable)
                                  │
                                  ▼
                          Runners (N × workers)
```

> Workers pull jobs from Redis queue and execute them. Runners provide isolated environments for Python and heavy tasks.

---

## ⚡ Quick Start

### 1. Clone and Setup

```bash
git clone https://github.com/soumatheusgomes/n8n-setup-scale.git
cd n8n-setup-scale
cp .env.example .env
```

### 2. Configure Environment

Edit `.env` and set **at minimum**:

```bash
# Required secrets (generate with commands below)
N8N_ENCRYPTION_KEY=<your-32-char-key>
N8N_RUNNERS_AUTH_TOKEN=<your-32-char-token>
REDIS_PASSWORD=<your-redis-password>

# Domain configuration
N8N_HOST=n8n.yourdomain.com
LETSENCRYPT_EMAIL=you@email.com
CLOUDFLARE_DNS_API_TOKEN=<your-cloudflare-token>
```

**Generate secrets:**
```bash
openssl rand -base64 32   # N8N_ENCRYPTION_KEY
openssl rand -hex 32      # N8N_RUNNERS_AUTH_TOKEN
openssl rand -base64 32   # REDIS_PASSWORD
```

### 3. Deploy

```bash
chmod +x install.sh
./install.sh
```

**Or non-interactive:**
```bash
./install.sh cloud-remote 4  # 4 workers with remote DB
./install.sh cloud-docker 6  # 6 workers with local DB
```

Access n8n at `https://your-domain.com` 🚀

---

## 🔧 Deployment Modes

| Mode | Description | Database | TLS | URL |
|------|-------------|----------|-----|-----|
| **cloud-remote** | Production with remote DB | Remote PostgreSQL | ✅ | `https://n8n.domain.com` |
| **cloud-docker** | Production with local DB | Docker container | ✅ | `https://n8n.domain.com` |
| **localhost-remote** | Development with remote DB | Remote PostgreSQL | ❌ | `http://localhost:5678` |
| **localhost-docker** | Development with local DB | Docker container | ❌ | `http://localhost:5678` |

---

## 📈 Scaling

### Scale Workers

```bash
# Scale to 10 workers with 20 runners (2 per worker)
docker compose up -d --scale n8n-worker=10 --scale n8n-worker-runners=20
```

### Scaling Tips

- **Workers**: Handle workflow execution. Scale based on concurrent workflow needs.
- **Runners**: Handle Python code and heavy operations. Use `RUNNERS_PER_WORKER` in `.env` to set the ratio.
- **Redis**: Single instance handles queue coordination.
- **PostgreSQL**: Consider managed database (RDS, Cloud SQL) for high availability.

---

## 🔐 Security Setup

### Required for Production

1. **Generate strong secrets** (32+ characters)
2. **Cloudflare API Token** with `Zone.DNS Read/Edit` permissions
   Create at: https://dash.cloudflare.com/profile/api-tokens
3. **Firewall Rules**:
   - Open ports `80`, `443` on main server (Traefik)
   - Keep Redis (`6379`) and PostgreSQL (`5432`) private
4. **BasicAuth for Traefik Dashboard**:
   ```bash
   echo "admin:$(htpasswd -nbB admin 'YOUR_PASSWORD' | cut -d: -f2 | sed 's/\$/\$\$/g')"
   ```

---

## 🛠️ Key Environment Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `N8N_ENCRYPTION_KEY` | Encrypts credentials (never change after setup) | ✅ |
| `N8N_RUNNERS_AUTH_TOKEN` | Authenticates runners with workers | ✅ |
| `REDIS_PASSWORD` | Redis authentication | ✅ |
| `N8N_HOST` | Public domain for n8n | ✅ |
| `CLOUDFLARE_DNS_API_TOKEN` | For automatic TLS certificates | ✅ |
| `LETSENCRYPT_EMAIL` | Certificate notifications | ✅ |
| `POSTGRES_HOST` | Leave empty for local DB, or set IP/hostname | ⚠️ |
| `RUNNERS_PER_WORKER` | Runner replicas per worker (default: 1) | - |

**See `.env.example` for complete list with detailed explanations.**

---

## 📦 Optional Services

### PostgreSQL (Local Container)

Use `cloud-docker` or `localhost-docker` mode to deploy PostgreSQL container.

For production, **consider managed PostgreSQL** (AWS RDS, Google Cloud SQL, etc.) and use `cloud-remote` mode.

### Browserless Chrome

Add to deployment:
```bash
# During install.sh, answer "y" when prompted
# Or manually:
docker compose --profile browserless up -d
```

---

## 🔄 Maintenance

### Backup

```bash
# Backup n8n data
docker cp $(docker compose ps -q n8n):/home/node/.n8n ./backup

# Backup database (if using local PostgreSQL)
docker exec postgres pg_dump -U n8n n8n > n8n-backup.sql
```

### Restore

```bash
# Restore n8n data
docker cp ./backup/. $(docker compose ps -q n8n):/home/node/.n8n

# Restore database
docker exec -i postgres psql -U n8n -d n8n < n8n-backup.sql
```

### Update n8n

1. Update versions in `.env`:
   ```bash
   N8N_VERSION=1.120.0
   N8N_RUNNER_VERSION=1.120.0  # Must match n8n version
   ```

2. Redeploy:
   ```bash
   ./install.sh cloud-remote 4
   ```

### Monitor Logs

```bash
# All services
docker compose logs -f

# Specific service
docker compose logs -f n8n-worker
```

---

## 🐛 Troubleshooting

| Issue | Solution |
|-------|----------|
| **Runners fail with 401/403** | Verify `N8N_RUNNERS_AUTH_TOKEN` is set correctly. |
| **TLS certificate fails** | Open port 80. Check DNS points to server. Verify Cloudflare token permissions. |
| **n8n shows 502 error** | Wait for n8n to finish starting: `docker compose logs -f n8n` |
| **Manual executions hang** | Check `OFFLOAD_MANUAL_EXECUTIONS_TO_WORKERS=true` and workers are running. |
| **Version incompatibility** | Ensure `N8N_VERSION` and `N8N_RUNNER_VERSION` match release line. |
| **Workers not processing** | Check Redis connectivity: `docker compose logs redis` |

---

## 📚 Project Structure

```
n8n-setup-scale/
├── docker-compose.yml    # Main compose file
├── install.sh            # Deployment script
├── Dockerfile            # Custom n8n image (optional)
├── .env.example          # Environment template
├── .editorconfig         # Code formatting
├── .gitignore            # Git ignore rules
└── README.md             # This file
```

---

## 🎓 How It Works

1. **Main n8n instance** serves UI and webhooks, but doesn't execute workflows
2. **Redis (BullMQ)** queues all workflow executions
3. **Workers** pull jobs from queue and execute them
4. **Runners** provide isolated environments for Python and heavy tasks
5. **Traefik** handles HTTPS, automatic certificates, and routing
6. **PostgreSQL** stores workflows, credentials, and execution history

**Result**: Unlimited horizontal scaling with complete isolation.

---

## 🤝 Contributing

Found an issue? Have an improvement? Pull requests are welcome!

1. Fork the repository
2. Create your feature branch
3. Commit your changes
4. Push to the branch
5. Open a Pull Request

---

## 📄 License

MIT License - see [LICENSE](LICENSE) for details.

Third-party images retain their original licenses.

---

## 🔗 Resources

- **n8n Documentation**: https://docs.n8n.io
- **n8n Community**: https://community.n8n.io
- **Traefik Documentation**: https://doc.traefik.io/traefik
- **Docker Compose**: https://docs.docker.com/compose

---

**Built with ❤️ for the n8n community**

For questions or support, open an issue on GitHub.
