#!/usr/bin/env bash
# n8n Stack Deployment Script
#
# Usage:
#   ./install.sh                     # Interactive
#   ./install.sh <mode> [workers]    # Non-interactive
#
# Modes: cloud-remote, cloud-docker, localhost-remote, localhost-docker

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

AVAILABLE_MODES=(cloud-remote cloud-docker localhost-remote localhost-docker)
DEFAULT_WORKERS=4
DEFAULT_RUNNERS_PER_WORKER=1

# Output helpers
print_info()    { echo ">> $1"; }
print_success() { echo "✅  $1"; }
print_error()   { echo "❌ ERROR: $1" >&2; }
print_warning() { echo "⚠️  WARNING: $1"; }

# Environment file helpers
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

# Validation
validate_mode() {
  local mode="$1"
  for valid_mode in "${AVAILABLE_MODES[@]}"; do
    [[ "$mode" == "$valid_mode" ]] && return 0
  done
  return 1
}

validate_number() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

validate_env_vars() {
  local missing_vars=()

  [[ -z "$(env_get N8N_RUNNERS_AUTH_TOKEN)" ]] && missing_vars+=("N8N_RUNNERS_AUTH_TOKEN")
  [[ -z "$(env_get N8N_ENCRYPTION_KEY)" ]] && missing_vars+=("N8N_ENCRYPTION_KEY")

  if [[ ${#missing_vars[@]} -gt 0 ]]; then
    print_error "Missing required environment variables:"
    for var in "${missing_vars[@]}"; do
      echo "  - $var"
    done
    echo ""
    echo "Generate with:"
    echo "  openssl rand -hex 32     # N8N_RUNNERS_AUTH_TOKEN"
    echo "  openssl rand -base64 32  # N8N_ENCRYPTION_KEY"
    return 1
  fi
  return 0
}

# Configuration
configure_webhook_url() {
  local mode="$1"
  sed -i.bak '/^WEBHOOK_URL=/d' "$ENV_FILE" && rm -f "$ENV_FILE.bak"

  local protocol host
  protocol="$(env_get N8N_PROTOCOL)"
  protocol="${protocol:-http}"
  host="$(env_get N8N_HOST)"
  host="${host:-localhost}"

  if [[ "$mode" =~ ^localhost- ]]; then
    env_set WEBHOOK_URL "${protocol}://localhost:5678"
    print_info "WEBHOOK_URL: ${protocol}://localhost:5678"
  else
    env_set WEBHOOK_URL "${protocol}://${host}"
    print_info "WEBHOOK_URL: ${protocol}://${host}"
  fi
}

get_compose_config() {
  local mode="$1"
  PROFILE_TLS=""
  PROFILE_DB=""
  EXTRA_FILE=""

  case "$mode" in
    cloud-remote)    PROFILE_TLS="--profile tls" ;;
    cloud-docker)    PROFILE_TLS="--profile tls"; PROFILE_DB="--profile dblocal" ;;
    localhost-remote) EXTRA_FILE="-f docker-compose.local.yml" ;;
    localhost-docker) PROFILE_DB="--profile dblocal"; EXTRA_FILE="-f docker-compose.local.yml" ;;
  esac
}

# Interactive prompts
prompt_mode() {
  echo "Select deployment mode:"
  select mode in "${AVAILABLE_MODES[@]}"; do
    [[ -n "$mode" ]] && echo "$mode" && return 0
    print_warning "Invalid selection."
  done
}

prompt_workers() {
  local input
  read -rp "Number of workers? [Default: $DEFAULT_WORKERS]: " input
  echo "${input:-$DEFAULT_WORKERS}"
}

prompt_browserless() {
  local answer
  read -rp "Include Browserless Chrome? (y/N): " answer
  case "$answer" in
    [yY][eE][sS]|[yY]) echo "true" ;;
    *) echo "false" ;;
  esac
}

# Deployment
build_compose_command() {
  echo "docker compose $PROFILE_TLS $PROFILE_DB -f docker-compose.yml $EXTRA_FILE"
}

deploy_stack() {
  local workers="$1"
  local runners_scale="$2"
  local include_browserless="$3"

  local dc_cmd
  dc_cmd="$(build_compose_command)"

  local extra_profiles=""
  [[ "$include_browserless" == "true" ]] && extra_profiles="--profile browserless"

  print_info "Stopping previous containers..."
  $dc_cmd down --remove-orphans

  print_info "Pulling latest images..."
  $dc_cmd pull

  print_info "Rebuilding custom n8n images..."
  $dc_cmd build --no-cache n8n n8n-worker

  print_info "Starting stack..."
  $dc_cmd $extra_profiles up -d \
    --scale n8n-worker="$workers" \
    --scale n8n-worker-runners="$runners_scale" \
    --remove-orphans

  print_info "Cleaning dangling images..."
  docker image prune -f

  if [[ "$include_browserless" != "true" ]]; then
    docker ps -a --filter "name=browserless" --format "{{.ID}}" | \
      xargs -r docker rm -f 2>/dev/null || true
  fi
}

# Main
main() {
  ENV_FILE="$SCRIPT_DIR/.env"
  touch "$ENV_FILE"

  local mode="${1:-}"
  local workers="${2:-}"

  # Get mode
  [[ -z "$mode" ]] && mode="$(prompt_mode)"
  if ! validate_mode "$mode"; then
    print_error "Invalid mode: $mode"
    echo "Available: ${AVAILABLE_MODES[*]}"
    exit 1
  fi

  # Get workers
  [[ -z "$workers" ]] && workers="$(prompt_workers)"
  if ! validate_number "$workers"; then
    print_warning "Invalid number. Using default: $DEFAULT_WORKERS"
    workers=$DEFAULT_WORKERS
  fi
  [[ "$workers" -lt 1 ]] && workers=1

  print_info "Mode: $mode"
  print_info "Workers: $workers"

  configure_webhook_url "$mode"

  if ! validate_env_vars; then
    exit 1
  fi

  # Calculate runners
  local runners_per_worker
  runners_per_worker="$(env_get RUNNERS_PER_WORKER)"
  runners_per_worker="${runners_per_worker:-$DEFAULT_RUNNERS_PER_WORKER}"

  if ! validate_number "$runners_per_worker" || [[ "$runners_per_worker" -lt 1 ]]; then
    runners_per_worker=$DEFAULT_RUNNERS_PER_WORKER
  fi

  local runners_scale=$((workers * runners_per_worker))

  print_info "Runners per worker: $runners_per_worker"
  print_info "Total runners: $runners_scale"

  local include_browserless
  include_browserless="$(prompt_browserless)"

  get_compose_config "$mode"
  deploy_stack "$workers" "$runners_scale" "$include_browserless"

  echo ""
  print_success "Stack deployed!"
  print_success "Workers: $workers | Runners: $runners_scale"
  echo ""

  if [[ "$mode" =~ ^localhost- ]]; then
    echo "Access: http://localhost:5678"
  else
    echo "Access: $(env_get N8N_PROTOCOL)://$(env_get N8N_HOST)"
  fi
}

main "$@"
