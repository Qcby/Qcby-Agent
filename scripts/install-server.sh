#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Qcby-Agent"
INSTALL_DIR="/opt/qcby-agent"
ENV_FILE="${INSTALL_DIR}/.env"
COMPOSE_FILE="${INSTALL_DIR}/docker-compose.yml"
MANAGE_SCRIPT="${INSTALL_DIR}/manage-server.sh"
IMAGE_REPO="qcby/qcby-agent"
DEFAULT_PORT="8080"
DEFAULT_IMAGE_TAG="latest"
DEFAULT_TOKEN="$(python3 - <<'PY'
import secrets
print(secrets.token_hex(16))
PY
)"
DEFAULT_SECRET="$(python3 - <<'PY'
import secrets
print(secrets.token_hex(32))
PY
)"

if [[ ${EUID} -eq 0 ]]; then
  SUDO=""
else
  SUDO="sudo"
fi

say() { echo "$*"; }
fail() { echo "[ERROR] $*" >&2; exit 1; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || fail "缺少命令: $1"; }

compose_cmd() {
  if docker compose version >/dev/null 2>&1; then
    echo "docker compose"
    return
  fi
  if command -v docker-compose >/dev/null 2>&1; then
    echo "docker-compose"
    return
  fi
  fail "未找到 docker compose / docker-compose"
}

read_tty() {
  local prompt="$1"
  local default="${2-}"
  local answer
  if [[ -n "$default" ]]; then
    read -r -p "$prompt [$default]: " answer </dev/tty || true
    answer="${answer:-$default}"
  else
    read -r -p "$prompt: " answer </dev/tty || true
  fi
  printf '%s' "$answer"
}

ensure_existing_defaults() {
  if [[ -f "$ENV_FILE" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
  fi
}

write_env() {
  ${SUDO} tee "$ENV_FILE" >/dev/null <<EOF
IMAGE_REPO=${IMAGE_REPO}
IMAGE_TAG=${IMAGE_TAG}
BIND_PORT=${BIND_PORT}
AGENT_TOKEN=${AGENT_TOKEN}
BOOTSTRAP_ADMIN_USERNAME=${ADMIN_USERNAME}
BOOTSTRAP_ADMIN_PASSWORD=${ADMIN_PASSWORD}
APP_SECRET_KEY=${APP_SECRET_KEY}
ONLINE_SECONDS=${ONLINE_SECONDS}
RETENTION_DAYS=${RETENTION_DAYS}
EOF
}

write_compose() {
  ${SUDO} tee "$COMPOSE_FILE" >/dev/null <<'EOF'
services:
  qcby-agent:
    image: ${IMAGE_REPO}:${IMAGE_TAG}
    container_name: qcby-agent
    ports:
      - "${BIND_PORT}:8080"
    environment:
      ONLINE_SECONDS: ${ONLINE_SECONDS}
      RETENTION_DAYS: ${RETENTION_DAYS}
      AGENT_TOKEN: ${AGENT_TOKEN}
      BOOTSTRAP_ADMIN_USERNAME: ${BOOTSTRAP_ADMIN_USERNAME}
      BOOTSTRAP_ADMIN_PASSWORD: ${BOOTSTRAP_ADMIN_PASSWORD}
      APP_SECRET_KEY: ${APP_SECRET_KEY}
      BIND_PORT: ${BIND_PORT}
      HOST_ENV_FILE: /host-config/.env
      HOST_APPLY_COMMAND: ./manage-server.sh apply
    volumes:
      - ./data:/app/data
      - ./:/host-config
    restart: unless-stopped
EOF
}

write_manage_script() {
  ${SUDO} tee "$MANAGE_SCRIPT" >/dev/null <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

compose_bin() {
  if docker compose version >/dev/null 2>&1; then
    echo "docker compose"
    return
  fi
  if command -v docker-compose >/dev/null 2>&1; then
    echo "docker-compose"
    return
  fi
  echo "docker compose"
}

COMPOSE_BIN="$(compose_bin)"
ACTION="${1:-apply}"
case "$ACTION" in
  apply|up)
    $COMPOSE_BIN --env-file .env up -d --remove-orphans
    ;;
  pull)
    $COMPOSE_BIN --env-file .env pull
    ;;
  restart)
    $COMPOSE_BIN --env-file .env up -d --force-recreate --remove-orphans
    ;;
  logs)
    $COMPOSE_BIN --env-file .env logs -f
    ;;
  down)
    $COMPOSE_BIN --env-file .env down
    ;;
  *)
    echo "用法: ./manage-server.sh [apply|pull|restart|logs|down]" >&2
    exit 1
    ;;
esac
EOF
  ${SUDO} chmod +x "$MANAGE_SCRIPT"
}

main() {
  need_cmd docker
  need_cmd python3
  COMPOSE_BIN="$(compose_cmd)"
  ensure_existing_defaults

  IMAGE_TAG="$(read_tty "Docker 镜像标签" "${IMAGE_TAG:-$DEFAULT_IMAGE_TAG}")"
  BIND_PORT="$(read_tty "服务端绑定端口" "${BIND_PORT:-$DEFAULT_PORT}")"
  AGENT_TOKEN="$(read_tty "Agent 接入 Token" "${AGENT_TOKEN:-$DEFAULT_TOKEN}")"
  ADMIN_USERNAME="$(read_tty "后台管理员账号" "${BOOTSTRAP_ADMIN_USERNAME:-admin}")"
  ADMIN_PASSWORD="$(read_tty "后台管理员密码" "${BOOTSTRAP_ADMIN_PASSWORD:-change-me-admin-password}")"
  ONLINE_SECONDS="$(read_tty "在线判断秒数" "${ONLINE_SECONDS:-90}")"
  RETENTION_DAYS="$(read_tty "历史保留天数" "${RETENTION_DAYS:-30}")"
  APP_SECRET_KEY="${APP_SECRET_KEY:-$DEFAULT_SECRET}"

  ${SUDO} mkdir -p "${INSTALL_DIR}/data"
  write_env
  write_compose
  write_manage_script

  cd "$INSTALL_DIR"
  $COMPOSE_BIN --env-file "$ENV_FILE" pull || true
  $COMPOSE_BIN --env-file "$ENV_FILE" up -d --remove-orphans

  say ""
  say "${APP_NAME} 服务端已部署完成："
  say "  安装目录: ${INSTALL_DIR}"
  say "  面板首页: http://$(hostname -I 2>/dev/null | awk '{print $1}' || echo '你的服务器IP'):${BIND_PORT}/"
  say "  管理后台: http://$(hostname -I 2>/dev/null | awk '{print $1}' || echo '你的服务器IP'):${BIND_PORT}/admin"
  say "  管理命令: ${MANAGE_SCRIPT} [apply|pull|restart|logs|down]"
  say ""
  say "注意：如果你后续在后台修改绑定端口，旧客户端会失联，需要同步更新客户端上报地址；修改后请执行："
  say "  ${MANAGE_SCRIPT} apply"
}

main "$@"
