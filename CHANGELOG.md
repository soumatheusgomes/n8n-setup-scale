# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0] - 2026-02-03

### 🚀 Major Updates

#### Version Upgrades
- **n8n**: Updated from `latest` to `2.3.4` (n8n 2.0 with breaking changes)
  - Task runners now enabled by default
  - Improved security with isolated Code node execution
  - Better database performance with SQLite pooling
  - [Release Notes](https://docs.n8n.io/release-notes/)

- **Redis**: Upgraded from `7` to `8.4`
  - 30%+ performance improvement for caching workloads
  - 92% memory reduction for homogenous JSON arrays
  - New atomic commands (DIGEST, DELEX, MSETEX)
  - [Release Info](https://redis.io/blog/redis-8-4-open-source-ga/)

- **PostgreSQL**: Upgraded from `17` to `18`
  - Async I/O implementation for better concurrency
  - Improved performance for sequential scans
  - [Release Notes](https://www.postgresql.org/docs/release/)

- **Traefik**: Updated from `v3` to `v3.6`
  - Security updates including CVE-2026-22045 fix
  - [Release Info](https://github.com/traefik/traefik/releases)

### ✨ New Features

#### Environment Variables
- `NODE_FUNCTION_ALLOW_EXTERNAL`: Allow external NPM modules in workflows
- `EXECUTIONS_DATA_PRUNE`: Automatic cleanup of old execution data
- `EXECUTIONS_DATA_MAX_AGE`: Configure execution retention period (default: 14 days)
- `N8N_METRICS`: Enable Prometheus metrics endpoint
- `N8N_METRICS_PREFIX`: Custom metrics prefix
- `N8N_LOG_LEVEL`: Configurable logging level (error, warn, info, verbose, debug)
- `N8N_LOG_OUTPUT`: Log format (console, json)
- `N8N_VERSION_NOTIFICATIONS_ENABLED`: Toggle version update notifications
- `N8N_TEMPLATES_ENABLED`: Enable/disable community templates
- `EXECUTIONS_PROCESS_CONCURRENCY`: Limit concurrent executions
- `EXECUTIONS_TIMEOUT`: Global execution timeout
- `N8N_PAYLOAD_SIZE_MAX`: Maximum webhook payload size
- `TZ`: System timezone configuration

#### Docker Compose Improvements
- **Resource Limits**: Added CPU and memory limits for all services
  - Traefik: 1 CPU / 512MB RAM
  - PostgreSQL: 2 CPU / 2GB RAM
  - Redis: 1 CPU / 1GB RAM
  - n8n: 2 CPU / 2GB RAM
  - Workers: 2 CPU / 4GB RAM
  - Runners: 1 CPU / 1GB RAM
  - Browserless: 2 CPU / 2GB RAM

- **Logging Configuration**: Standardized JSON logging with rotation
  - Max size: 10MB per file
  - Max files: 3 rotations
  - Prevents disk space issues

- **Health Checks**: Improved health checks for all services
  - Added start_period for better initialization
  - n8n and workers now use /healthz endpoint
  - Better retry logic

- **Redis Optimizations**:
  - Memory limit: 1GB with LRU eviction policy
  - AOF persistence with fsync every second
  - Configurable save points
  - Better performance tuning

- **PostgreSQL Optimizations**:
  - UTF-8 encoding by default
  - Async I/O enabled (PostgreSQL 18)
  - Better initialization parameters

### 🔒 Security Enhancements

- Task runners now run in isolated environments by default (n8n 2.0)
- Improved password generation guidelines in .env.example
- Better secret management documentation
- TZ environment variable for consistent timestamps
- Updated security best practices in README

### 📚 Documentation

- **README.md**: Complete rewrite
  - More concise and objective
  - Better visual hierarchy
  - Clearer quick start guide
  - Improved troubleshooting section
  - Added badges and better formatting

- **.env.example**: Enhanced documentation
  - Detailed comments for each variable
  - Security guidelines
  - Version-specific notes
  - Generation commands for secrets

- **Code Comments**: All files now in English
  - docker-compose.yml: Comprehensive service documentation
  - Scripts: Better function documentation
  - Consistent comment formatting

### 🛠️ Code Refactoring

#### install.sh
- Renamed from `update-stack.sh` to match README
- Modular function structure
- Better error handling and validation
- Colored output for better UX
- English comments throughout

#### deploy-workers-only.sh
- Added full Task Runners support
- Better validation of required variables
- Auto-generation of docker-compose.worker.yml
- Support for runners-per-worker configuration
- English comments throughout

#### docker-compose.yml
- Reorganized structure with clear sections
- Removed duplicate networks/volumes declarations
- Added profiles to Traefik service
- Better environment variable organization
- Comprehensive inline documentation

### 🔧 Configuration Files

- **.gitignore**: Expanded coverage
  - Docker-specific files
  - OS-specific files (macOS, Linux, Windows)
  - Editor files (.vscode, .idea)
  - Backup files
  - Log files and directories

- **.editorconfig**: Enhanced rules
  - Shell script formatting
  - YAML file configuration
  - Markdown file handling
  - Makefile support

- **Dockerfile**: Created for custom nodes
  - Base template for extending n8n
  - Examples for community nodes
  - System dependency installation guide

### 📊 Performance Improvements

- Redis 8.4: 30%+ throughput increase
- PostgreSQL 18: Async I/O for better concurrency
- Execution data pruning to save disk space
- Configurable concurrency limits
- Better resource allocation with limits

### 🐛 Bug Fixes

- Fixed install.sh not being executable by default
- Corrected profile assignment for Traefik
- Fixed worker-only deployment missing runners
- Resolved duplicate sections in docker-compose.yml

### ⚠️ Breaking Changes

- **n8n 2.0 Breaking Changes**:
  - Environment variable access blocked from Code nodes by default
  - Task runners mandatory (already configured in this setup)
  - Database schema changes (automatic migration)
  - See [n8n 2.0 breaking changes](https://docs.n8n.io/2-0-breaking-changes/)

- **Version Pinning**: Changed from `latest` to specific versions
  - Update .env to use new version numbers
  - N8N_VERSION and N8N_RUNNER_VERSION must match

### 📦 Migration Guide

To upgrade from previous version:

1. **Backup your data**:
   ```bash
   docker cp $(docker compose ps -q n8n):/home/node/.n8n ./backup
   docker exec postgres pg_dump -U n8n n8n > n8n-backup.sql
   ```

2. **Update .env file**:
   ```bash
   # Copy new variables from .env.example
   # Update versions:
   N8N_VERSION=2.3.4
   N8N_RUNNER_VERSION=2.3.4
   REDIS_VERSION=8.4
   POSTGRES_VERSION=18
   TRAEFIK_VERSION=v3.6
   ```

3. **Review new optional variables** in .env.example and add as needed

4. **Redeploy**:
   ```bash
   ./install.sh cloud-remote 4
   ```

5. **Verify health**:
   ```bash
   docker compose logs -f
   docker compose ps
   ```

### 🔗 References

- [n8n 2.0 Release](https://blog.n8n.io/introducing-n8n-2-0/)
- [Redis 8.4 Release](https://redis.io/blog/redis-8-4-open-source-ga/)
- [PostgreSQL 18 Release](https://www.postgresql.org/about/news/postgresql-181-177-1611-1515-1420-and-1323-released-3171/)
- [Traefik Releases](https://github.com/traefik/traefik/releases)
- [n8n Docker Compose Best Practices](https://docs.n8n.io/hosting/installation/server-setups/docker-compose/)

---

## [1.0.0] - Previous Version

Initial release with basic n8n distributed setup.
