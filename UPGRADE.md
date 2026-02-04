# Upgrade Guide

This guide will help you upgrade your n8n setup to the latest version with all improvements.

## 📋 Pre-Upgrade Checklist

- [ ] Read the [CHANGELOG.md](CHANGELOG.md) to understand what's changing
- [ ] Backup your data (see below)
- [ ] Review n8n 2.0 [breaking changes](https://docs.n8n.io/2-0-breaking-changes/)
- [ ] Plan for potential downtime (5-15 minutes)
- [ ] Verify you have enough disk space for new Docker images

## 💾 Step 1: Backup Current Setup

### Backup n8n Data

```bash
# Backup n8n workflows, credentials, and settings
docker cp $(docker compose ps -q n8n):/home/node/.n8n ./backup-$(date +%Y%m%d)

# Verify backup
ls -lh ./backup-$(date +%Y%m%d)
```

### Backup Database (if using local PostgreSQL)

```bash
# Backup database
docker exec postgres pg_dump -U n8n n8n > n8n-backup-$(date +%Y%m%d).sql

# Verify backup
ls -lh n8n-backup-*.sql
```

### Backup Current Configuration

```bash
# Backup current .env file
cp .env .env.backup-$(date +%Y%m%d)

# Backup current docker-compose files
cp docker-compose.yml docker-compose.yml.backup
```

## 🔄 Step 2: Pull Latest Code

```bash
# Fetch latest changes
git fetch origin

# Checkout latest version
git checkout main
git pull origin main

# Or download latest release
# wget https://github.com/soumatheusgomes/n8n-setup-scale/archive/refs/heads/main.zip
# unzip main.zip
```

## ⚙️ Step 3: Update Configuration

### Update .env File

Compare your current `.env` with the new `.env.example`:

```bash
# See what's new
diff .env .env.example
```

**Critical updates needed:**

```bash
# Update service versions
N8N_VERSION=2.3.4
N8N_RUNNER_VERSION=2.3.4
REDIS_VERSION=8.4
POSTGRES_VERSION=18
TRAEFIK_VERSION=v3.6

# Add new optional variables (see .env.example for full list)
TZ=America/Sao_Paulo
NODE_FUNCTION_ALLOW_EXTERNAL=
EXECUTIONS_DATA_PRUNE=true
EXECUTIONS_DATA_MAX_AGE=336
N8N_METRICS=false
N8N_LOG_LEVEL=info
N8N_LOG_OUTPUT=console
EXECUTIONS_PROCESS_CONCURRENCY=10
EXECUTIONS_TIMEOUT=-1
N8N_PAYLOAD_SIZE_MAX=16
```

### Review New Features

Check [.env.example](.env.example) for detailed documentation on all new variables.

Key additions:
- **Monitoring**: `N8N_METRICS` for Prometheus integration
- **Performance**: `EXECUTIONS_PROCESS_CONCURRENCY` to limit concurrent executions
- **Cleanup**: `EXECUTIONS_DATA_PRUNE` for automatic data pruning
- **Security**: `NODE_FUNCTION_ALLOW_EXTERNAL` for NPM module control
- **Logging**: `N8N_LOG_LEVEL` and `N8N_LOG_OUTPUT` for better debugging

## 🚀 Step 4: Perform Upgrade

### Option A: Using install.sh (Recommended)

```bash
# Make script executable
chmod +x install.sh

# Interactive upgrade
./install.sh

# Or non-interactive
./install.sh cloud-remote 4  # Replace with your mode and worker count
```

The script will:
1. Stop current containers
2. Pull new images
3. Rebuild custom images
4. Start services with new configuration
5. Clean up old images

### Option B: Manual Upgrade

```bash
# Stop current services
docker compose down

# Pull new images
docker compose pull

# Rebuild custom images (if using Dockerfile)
docker compose build --no-cache n8n n8n-worker

# Start services
docker compose up -d --scale n8n-worker=4 --scale n8n-worker-runners=4

# Clean up old images
docker image prune -f
```

## ✅ Step 5: Verify Upgrade

### Check Service Status

```bash
# View all containers
docker compose ps

# Should show all services as "Up" or "healthy"
```

### Check Logs

```bash
# Check n8n main logs
docker compose logs -f n8n

# Check worker logs
docker compose logs -f n8n-worker

# Check for errors
docker compose logs --tail=50 | grep -i error
```

### Test n8n Access

```bash
# For cloud deployments
curl -I https://your-domain.com

# For local deployments
curl -I http://localhost:5678

# Should return HTTP 200 or 302
```

### Verify Health Endpoints

```bash
# n8n health check
docker exec n8n-setup-scale-n8n-1 wget -qO- http://localhost:5678/healthz

# Worker health check
docker exec n8n-setup-scale-n8n-worker-1 wget -qO- http://localhost:5679/healthz
```

### Check Database Migration

```bash
# n8n 2.0 automatically migrates the database
# Check logs for migration messages
docker compose logs n8n | grep -i migration
```

## 🔧 Step 6: Post-Upgrade Tasks

### Review Resource Usage

```bash
# Check resource usage
docker stats

# Adjust resource limits in docker-compose.yml if needed
# See deploy.resources sections for each service
```

### Enable New Features (Optional)

**Enable Metrics** (for Prometheus monitoring):
```bash
# In .env
N8N_METRICS=true
N8N_METRICS_PREFIX=n8n_

# Restart services
docker compose up -d

# Access metrics at: http://your-n8n:5678/metrics
```

**Enable External NPM Modules**:
```bash
# In .env (use cautiously, security risk)
NODE_FUNCTION_ALLOW_EXTERNAL=axios,lodash  # Specific modules
# OR
NODE_FUNCTION_ALLOW_EXTERNAL=*  # All modules (not recommended)

# Restart services
docker compose up -d
```

**Enable Automatic Execution Pruning**:
```bash
# In .env
EXECUTIONS_DATA_PRUNE=true
EXECUTIONS_DATA_MAX_AGE=336  # 14 days

# Restart services
docker compose up -d
```

## 🐛 Troubleshooting

### Issue: Containers Won't Start

**Solution:**
```bash
# Check logs for errors
docker compose logs

# Verify .env has all required variables
grep -E "^(N8N_ENCRYPTION_KEY|N8N_RUNNERS_AUTH_TOKEN|REDIS_PASSWORD)=" .env

# Ensure ports aren't in use
sudo lsof -i :80 -i :443 -i :5678 -i :6379 -i :5432
```

### Issue: Database Migration Failed

**Solution:**
```bash
# Stop services
docker compose down

# Restore database backup
docker compose up -d postgres
sleep 10
docker exec -i postgres psql -U n8n -d n8n < n8n-backup-YYYYMMDD.sql

# Try upgrade again
./install.sh
```

### Issue: Workers Not Connecting

**Solution:**
```bash
# Verify Redis connectivity
docker compose exec n8n-worker redis-cli -h redis -a $REDIS_PASSWORD ping

# Check worker logs
docker compose logs n8n-worker

# Ensure REDIS_PASSWORD matches in .env
grep REDIS_PASSWORD .env
```

### Issue: Runners Authentication Failed

**Solution:**
```bash
# Verify token matches
docker compose exec n8n env | grep N8N_RUNNERS_AUTH_TOKEN
docker compose exec n8n-worker-runners env | grep N8N_RUNNERS_AUTH_TOKEN

# Both should be identical
# If not, update .env and restart
docker compose up -d
```

### Issue: High Resource Usage

**Solution:**
```bash
# Check current usage
docker stats

# Adjust limits in docker-compose.yml
# Edit deploy.resources sections for each service

# Apply changes
docker compose up -d
```

## 🔙 Rollback Procedure

If you encounter issues and need to rollback:

### 1. Stop New Version

```bash
docker compose down
```

### 2. Restore Configuration

```bash
# Restore .env
cp .env.backup-YYYYMMDD .env

# Restore compose files
cp docker-compose.yml.backup docker-compose.yml
```

### 3. Restore Database

```bash
# Start only database
docker compose up -d postgres
sleep 10

# Restore backup
docker exec -i postgres psql -U n8n -d n8n < n8n-backup-YYYYMMDD.sql
```

### 4. Restore n8n Data

```bash
# Start n8n
docker compose up -d n8n

# Restore data
docker cp ./backup-YYYYMMDD/. $(docker compose ps -q n8n):/home/node/.n8n

# Restart n8n
docker compose restart n8n
```

### 5. Start Other Services

```bash
docker compose up -d
```

## 📊 Performance Optimization

After upgrading, consider these optimizations:

### Redis Tuning

Edit `docker-compose.yml` Redis command section:
```yaml
--maxmemory 2gb  # Increase if you have RAM available
--maxmemory-policy allkeys-lru  # Keep this
```

### Worker Scaling

```bash
# Scale workers based on load
docker compose up -d --scale n8n-worker=8 --scale n8n-worker-runners=8
```

### Enable Execution Pruning

```bash
# .env
EXECUTIONS_DATA_PRUNE=true
EXECUTIONS_DATA_MAX_AGE=168  # 7 days (more aggressive)
```

## 📚 Additional Resources

- [n8n 2.0 Documentation](https://docs.n8n.io/)
- [n8n Breaking Changes](https://docs.n8n.io/2-0-breaking-changes/)
- [CHANGELOG.md](CHANGELOG.md) - Full list of changes
- [README.md](README.md) - Updated documentation
- [n8n Community](https://community.n8n.io/)

## 🆘 Getting Help

If you encounter issues:

1. Check the [Troubleshooting](#troubleshooting) section above
2. Review the [CHANGELOG.md](CHANGELOG.md)
3. Check [GitHub Issues](https://github.com/soumatheusgomes/n8n-setup-scale/issues)
4. Ask in [n8n Community](https://community.n8n.io/)

---

**Remember**: Always keep backups before major upgrades!
