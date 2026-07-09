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

get_private_ip() {
  hostname -I 2>/dev/null | awk '{print $1}' || true
}

get_public_ip() {
  if command -v curl >/dev/null 2>&1; then
    curl -fsS --max-time 8 https://api4.ipify.org 2>/dev/null \
      || curl -fsS --max-time 8 https://api.ip.sb/ip 2>/dev/null \
      || curl -fsS --max-time 8 https://api.ipify.org 2>/dev/null \
      || true
    return
  fi
  if command -v wget >/dev/null 2>&1; then
    wget -qO- --timeout=8 https://api4.ipify.org 2>/dev/null \
      || wget -qO- --timeout=8 https://api.ip.sb/ip 2>/dev/null \
      || wget -qO- --timeout=8 https://api.ipify.org 2>/dev/null \
      || true
    return
  fi
  true
}

server_installed() {
  [[ -f "$ENV_FILE" || -f "$COMPOSE_FILE" || -f "$MANAGE_SCRIPT" ]]
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
  ps|status)
    $COMPOSE_BIN --env-file .env ps
    ;;
  *)
    echo "用法: ./manage-server.sh [apply|pull|restart|logs|down|status]" >&2
    exit 1
    ;;
esac
EOF
  ${SUDO} chmod +x "$MANAGE_SCRIPT"
}

print_access_info() {
  local bind_port="$1"
  local private_ip public_ip
  private_ip="$(get_private_ip)"
  public_ip="$(get_public_ip)"

  say ""
  say "${APP_NAME} 服务端已部署完成："
  say "  安装目录: ${INSTALL_DIR}"
  say "  面板首页(内网): http://${private_ip:-你的服务器IP}:${bind_port}/"
  say "  管理后台(内网): http://${private_ip:-你的服务器IP}:${bind_port}/admin"
  if [[ -n "${public_ip:-}" ]]; then
    say "  面板首页(公网): http://${public_ip}:${bind_port}/"
    say "  管理后台(公网): http://${public_ip}:${bind_port}/admin"
  fi
  say "  管理命令: ${MANAGE_SCRIPT} [apply|pull|restart|logs|down|status]"
  say ""
  say "注意：如果你后续在后台修改绑定端口，旧客户端会失联，需要同步更新客户端上报地址；修改后请执行："
  say "  ${MANAGE_SCRIPT} apply"
}

collect_server_config() {
  ensure_existing_defaults
  IMAGE_TAG="$(read_tty "Docker 镜像标签" "${IMAGE_TAG:-$DEFAULT_IMAGE_TAG}")"
  BIND_PORT="$(read_tty "服务端绑定端口" "${BIND_PORT:-$DEFAULT_PORT}")"
  AGENT_TOKEN="$(read_tty "Agent 接入 Token" "${AGENT_TOKEN:-$DEFAULT_TOKEN}")"
  ADMIN_USERNAME="$(read_tty "后台管理员账号" "${BOOTSTRAP_ADMIN_USERNAME:-admin}")"
  ADMIN_PASSWORD="$(read_tty "后台管理员密码" "${BOOTSTRAP_ADMIN_PASSWORD:-change-me-admin-password}")"
  ONLINE_SECONDS="$(read_tty "在线判断秒数" "${ONLINE_SECONDS:-90}")"
  RETENTION_DAYS="$(read_tty "历史保留天数" "${RETENTION_DAYS:-30}")"
  APP_SECRET_KEY="${APP_SECRET_KEY:-$DEFAULT_SECRET}"
}

ensure_server_files() {
  ${SUDO} mkdir -p "${INSTALL_DIR}/data"
  write_env
  write_compose
  write_manage_script
}

install_or_reconfigure_server() {
  need_cmd docker
  need_cmd python3
  local compose_bin
  compose_bin="$(compose_cmd)"
  collect_server_config
  ensure_server_files

  cd "$INSTALL_DIR"
  $compose_bin --env-file "$ENV_FILE" pull >/dev/null 2>&1 || true
  bash "$MANAGE_SCRIPT" apply
  print_access_info "$BIND_PORT"
}

upgrade_server() {
  need_cmd docker
  need_cmd python3
  compose_cmd >/dev/null
  server_installed || fail "未检测到已安装的服务端，请先执行安装。"
  ensure_existing_defaults
  ensure_server_files

  cd "$INSTALL_DIR"
  local compose_bin
  compose_bin="$(compose_cmd)"
  $compose_bin --env-file "$ENV_FILE" pull
  $compose_bin --env-file "$ENV_FILE" up -d --force-recreate --remove-orphans
  print_access_info "${BIND_PORT:-$DEFAULT_PORT}"
}

start_server() {
  server_installed || fail "未检测到已安装的服务端，请先安装。"
  bash "$MANAGE_SCRIPT" apply
}

restart_server() {
  server_installed || fail "未检测到已安装的服务端，请先安装。"
  bash "$MANAGE_SCRIPT" restart
}

stop_server() {
  server_installed || fail "未检测到已安装的服务端，请先安装。"
  bash "$MANAGE_SCRIPT" down
}

status_server() {
  server_installed || fail "未检测到已安装的服务端，请先安装。"
  bash "$MANAGE_SCRIPT" status
}

logs_server() {
  server_installed || fail "未检测到已安装的服务端，请先安装。"
  bash "$MANAGE_SCRIPT" logs
}

uninstall_server() {
  if server_installed; then
    if [[ -f "$MANAGE_SCRIPT" ]]; then
      bash "$MANAGE_SCRIPT" down >/dev/null 2>&1 || true
    fi
    ${SUDO} rm -rf "$INSTALL_DIR"
  fi
  say "${APP_NAME} 服务端已卸载。"
}

show_menu() {
  echo "请选择操作:"
  echo "1) 安装/重新配置"
  echo "2) 升级/更新"
  echo "3) 卸载"
  echo "4) 启动"
  echo "5) 重启"
  echo "6) 停止"
  echo "7) 查看状态"
  echo "8) 查看日志"
  echo "9) 重新配置"
  echo "0) 退出"
  read -r -p "输入数字: " choice
  case "$choice" in
    1) install_or_reconfigure_server ;;
    2) upgrade_server ;;
    3) uninstall_server ;;
    4) start_server ;;
    5) restart_server ;;
    6) stop_server ;;
    7) status_server ;;
    8) logs_server ;;
    9) install_or_reconfigure_server ;;
    0) exit 0 ;;
    *) fail "无效选择" ;;
  esac
}

case "${1:-menu}" in
  install|reconfigure|config)
    install_or_reconfigure_server
    ;;
  update|upgrade)
    upgrade_server
    ;;
  uninstall|remove)
    uninstall_server
    ;;
  start)
    start_server
    ;;
  restart)
    restart_server
    ;;
  stop)
    stop_server
    ;;
  status)
    status_server
    ;;
  logs|log)
    logs_server
    ;;
  ""|menu)
    show_menu
    ;;
  *)
    echo "用法:"
    echo "  bash scripts/install-server.sh               # 交互菜单"
    echo "  bash scripts/install-server.sh install       # 安装/重新配置"
    echo "  bash scripts/install-server.sh upgrade       # 保留配置直接升级"
    echo "  bash scripts/install-server.sh uninstall     # 卸载"
    echo "  bash scripts/install-server.sh start         # 启动"
    echo "  bash scripts/install-server.sh restart       # 重启"
    echo "  bash scripts/install-server.sh stop          # 停止"
    echo "  bash scripts/install-server.sh status        # 查看状态"
    echo "  bash scripts/install-server.sh logs          # 查看日志"
    exit 1
    ;;
esac
