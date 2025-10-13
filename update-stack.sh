#!/usr/bin/env bash
# install.sh  –  Provisiona/atualiza a stack n8n + Traefik (com workers e runners sempre ativos)
# Uso:   ./install.sh <MODE> [WORKERS]
# MODE  : cloud-remote | cloud-docker | localhost-remote | localhost-docker
# WORKERS (opcional)  : nº de workers (default 4)

set -euo pipefail

STACK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$STACK_DIR"

MODES=(cloud-remote cloud-docker localhost-remote localhost-docker)

MODE="${1:-}"
WORKERS="${2:-}"

if [[ -z "$MODE" ]]; then
  echo "Choose deploy mode: [Only numbers]"
  select MODE in "${MODES[@]}"; do
    [[ -n "$MODE" ]] && break
    echo "Invalid option."
  done
fi

if [[ ! " ${MODES[*]} " =~ " $MODE " ]]; then
  echo "Invalid mode. Options: ${MODES[*]}"
  exit 1
fi

if [[ -z "$WORKERS" ]]; then
  read -rp "Number of workers? [Default 4]: " WORKERS
  WORKERS="${WORKERS:-4}"
fi
if ! [[ "$WORKERS" =~ ^[0-9]+$ ]]; then
  echo "Invalid number — using 4."
  WORKERS=4
fi
if [[ "$WORKERS" -lt 1 ]]; then
  echo "At least 1 worker is required when runners are always enabled."
  WORKERS=1
fi

echo ">> Deploy mode : $MODE"
echo ">> Worker count: $WORKERS"

#######################################
# Utils: leitura/edição de .env
#######################################
ENV_FILE="$STACK_DIR/.env"
touch "$ENV_FILE"

env_get() {
  local key="$1"
  grep -E "^${key}=" "$ENV_FILE" | tail -n 1 | cut -d= -f2- || true
}

env_set() {
  local key="$1"
  local val="$2"
  if grep -qE "^${key}=" "$ENV_FILE"; then
    awk -v k="$key" -v v="$val" -F= '
      BEGIN{OFS="="}
      $1==k {last=NR}
      {lines[NR]=$0}
      END{
        if(last){
          for(i=1;i<=length(lines);i++){
            if(i==last){print k,v}
            else{print lines[i]}
          }
        } else {
          for(i=1;i<=length(lines);i++) print lines[i]
          print k "=" v
        }
      }' "$ENV_FILE" > "$ENV_FILE.tmp" && mv "$ENV_FILE.tmp" "$ENV_FILE"
  else
    echo "${key}=${val}" >> "$ENV_FILE"
  fi
}

#######################################
# Ajusta WEBHOOK_URL dinamicamente
#######################################
sed -i '/^WEBHOOK_URL=/d' "$ENV_FILE" || true

N8N_PROTOCOL_VAL="$(env_get N8N_PROTOCOL)"; N8N_PROTOCOL_VAL="${N8N_PROTOCOL_VAL:-http}"
N8N_HOST_VAL="$(env_get N8N_HOST)";       N8N_HOST_VAL="${N8N_HOST_VAL:-localhost}"

if [[ "$MODE" =~ ^localhost- ]]; then
  env_set WEBHOOK_URL "${N8N_PROTOCOL_VAL}://localhost:5678"
  echo ">> WEBHOOK_URL definido (local): ${N8N_PROTOCOL_VAL}://localhost:5678"
else
  env_set WEBHOOK_URL "${N8N_PROTOCOL_VAL}://${N8N_HOST_VAL}"
  echo ">> WEBHOOK_URL definido (cloud): ${N8N_PROTOCOL_VAL}://${N8N_HOST_VAL}"
fi

#######################################
# Pergunta se inclui o Browserless
#######################################
INCLUDE_BROWSERLESS="false"
read -rp "Do you want to include the Browserless container? (y/N): " INCLUDE_BROWSERLESS_ANSWER
case "$INCLUDE_BROWSERLESS_ANSWER" in
  [yY][eE][sS]|[yY]) INCLUDE_BROWSERLESS="true" ;;
  *) INCLUDE_BROWSERLESS="false" ;;
esac

#######################################
# Runners: sempre habilitados
# - Exige N8N_RUNNERS_AUTH_TOKEN no .env
# - Calcula escala: RUNNERS = WORKERS * RUNNERS_PER_WORKER
#######################################
RUNNERS_PER_WORKER="$(env_get RUNNERS_PER_WORKER)"; RUNNERS_PER_WORKER="${RUNNERS_PER_WORKER:-1}"

AUTH_TOKEN="$(env_get N8N_RUNNERS_AUTH_TOKEN)"
if [[ -z "${AUTH_TOKEN}" ]]; then
  echo "ERROR: N8N_RUNNERS_AUTH_TOKEN must be set in .env (runners are always enabled)."
  echo "Generate one, e.g.:   openssl rand -hex 32"
  exit 1
fi

if ! [[ "$RUNNERS_PER_WORKER" =~ ^[0-9]+$ ]]; then
  echo "Invalid RUNNERS_PER_WORKER — using 1."
  RUNNERS_PER_WORKER=1
fi
if [[ "$RUNNERS_PER_WORKER" -lt 1 ]]; then
  echo "RUNNERS_PER_WORKER must be >= 1 when runners are always enabled. Forcing 1."
  RUNNERS_PER_WORKER=1
fi

RUNNERS_SCALE=$(( WORKERS * RUNNERS_PER_WORKER ))

echo ">> Runners always ON"
echo ">> RUNNERS_PER_WORKER: $RUNNERS_PER_WORKER"
echo ">> Runner replicas    : $RUNNERS_SCALE"

#######################################
# Compose profile e overrides
#######################################
PROFILE_TLS=""; PROFILE_DB=""; EXTRA_FILE=""
case "$MODE" in
  cloud-remote)       PROFILE_TLS="--profile tls" ;;
  cloud-docker)       PROFILE_TLS="--profile tls"; PROFILE_DB="--profile dblocal" ;;
  localhost-remote)   EXTRA_FILE="-f docker-compose.local.yml" ;;
  localhost-docker)   PROFILE_DB="--profile dblocal"; EXTRA_FILE="-f docker-compose.local.yml" ;;
esac

#######################################
# Deploy stack
#######################################
DC="docker compose $PROFILE_TLS $PROFILE_DB -f docker-compose.yml $EXTRA_FILE"
EXTRA_PROFILES=""
if [[ "$INCLUDE_BROWSERLESS" == "true" ]]; then
  EXTRA_PROFILES="--profile browserless"
fi

echo ">> Stopping previous containers..."
$DC down --remove-orphans

echo ">> Pulling latest images..."
$DC pull

echo ">> Rebuilding custom n8n image..."
$DC build --no-cache n8n n8n-worker

echo ">> Starting stack..."
$DC $EXTRA_PROFILES up -d \
  --scale n8n-worker="$WORKERS" \
  --scale n8n-worker-runners="$RUNNERS_SCALE" \
  --remove-orphans

echo ">> Cleaning dangling images..."
docker image prune -f

echo "✅  Stack is up — $WORKERS worker(s), $RUNNERS_SCALE runner(s)."

# Remove browserless manual se não incluído
if [[ "$INCLUDE_BROWSERLESS" != "true" ]]; then
  echo ">> Cleaning up browserless container if exists..."
  docker ps -a --filter "name=browserless" --format "{{.ID}}" | xargs -r docker rm -f
fi
