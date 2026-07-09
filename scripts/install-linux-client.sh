#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Qcby-Agent Linux Client"
INSTALL_DIR="/opt/qcby-agent-client"
SERVICE_NAME="qcby-agent-client"
CONFIG_FILE="${INSTALL_DIR}/agent.env"
AGENT_FILE="${INSTALL_DIR}/agent.sh"
SYSTEMD_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
RAW_BASE="${QCBY_AGENT_RAW_BASE:-https://raw.githubusercontent.com/Qcby/Qcby-Agent/main}"
CACHE_BUSTER="${QCBY_AGENT_CACHE_BUSTER:-$(date +%s)}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SOURCE_AGENT="${REPO_DIR}/client/linux/agent.sh"

if [[ ${EUID} -eq 0 ]]; then
  SUDO=""
else
  SUDO="sudo"
fi

say() { echo "$*"; }
fail() { echo "[ERROR] $*" >&2; exit 1; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || fail "缺少命令: $1"; }

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

get_private_ip() {
  hostname -I 2>/dev/null | awk '{print $1}' || true
}

download_agent() {
  local target="$1"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "${RAW_BASE}/client/linux/agent.sh?t=${CACHE_BUSTER}" -o "$target"
    return
  fi
  if command -v wget >/dev/null 2>&1; then
    wget -qO "$target" "${RAW_BASE}/client/linux/agent.sh?t=${CACHE_BUSTER}"
    return
  fi
  fail "缺少 curl 或 wget，无法远程下载 Linux agent。"
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

client_installed() {
  [[ -f "$CONFIG_FILE" || -f "$SYSTEMD_FILE" || -f "$AGENT_FILE" ]]
}

service_exists() {
  systemctl list-unit-files "${SERVICE_NAME}.service" --no-legend 2>/dev/null | grep -q "${SERVICE_NAME}\.service" || [[ -f "$SYSTEMD_FILE" ]]
}

load_existing_defaults() {
  EXISTING_SERVER_HOST=""
  EXISTING_SERVER_PORT=""
  EXISTING_AGENT_ID=""
  EXISTING_INTERVAL_SECONDS=""
  EXISTING_TOKEN=""
  EXISTING_REGION=""
  EXISTING_ISP=""
  EXISTING_TAGS=""
  if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
    local existing_url="${SERVER_URL:-}"
    if [[ -n "$existing_url" ]]; then
      EXISTING_SERVER_HOST="$(printf '%s' "$existing_url" | sed -E 's#^https?://([^:/]+).*$#\1#')"
      EXISTING_SERVER_PORT="$(printf '%s' "$existing_url" | sed -nE 's#^https?://[^:/]+:([0-9]+)/.*$#\1#p')"
    fi
    EXISTING_AGENT_ID="${AGENT_ID:-}"
    EXISTING_INTERVAL_SECONDS="${INTERVAL_SECONDS:-}"
    EXISTING_TOKEN="${TOKEN:-}"
    EXISTING_REGION="${REGION:-}"
    EXISTING_ISP="${ISP:-}"
    EXISTING_TAGS="${TAGS:-}"
  fi
}

write_agent_files() {
  local server_url="$1"
  local agent_id="$2"
  local interval_seconds="$3"
  local token="$4"
  local region="$5"
  local isp="$6"
  local tags="$7"

  ${SUDO} mkdir -p "$INSTALL_DIR"
  if [[ -f "$SOURCE_AGENT" ]]; then
    ${SUDO} cp "$SOURCE_AGENT" "$AGENT_FILE"
  else
    local temp_agent
    temp_agent="$(mktemp)"
    download_agent "$temp_agent"
    ${SUDO} cp "$temp_agent" "$AGENT_FILE"
    rm -f "$temp_agent"
  fi
  ${SUDO} chmod +x "$AGENT_FILE"

  ${SUDO} tee "$CONFIG_FILE" >/dev/null <<EOF
SERVER_URL=${server_url}
AGENT_ID=${agent_id}
INTERVAL_SECONDS=${interval_seconds}
TOKEN=${token}
REGION=${region}
ISP=${isp}
TAGS=${tags}
EOF

  ${SUDO} tee "$SYSTEMD_FILE" >/dev/null <<EOF
[Unit]
Description=${APP_NAME}
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=${CONFIG_FILE}
ExecStart=/bin/bash ${AGENT_FILE}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  ${SUDO} systemctl daemon-reload
}

install_or_update_client() {
  need_cmd bash
  need_cmd systemctl
  load_existing_defaults

  local default_server_host default_server_port default_token default_agent_id default_interval default_region default_isp default_tags
  default_server_host="${EXISTING_SERVER_HOST:-}"
  default_server_port="${EXISTING_SERVER_PORT:-8080}"
  default_token="${EXISTING_TOKEN:-change-me-token}"
  default_agent_id="${EXISTING_AGENT_ID:-}"
  default_interval="${EXISTING_INTERVAL_SECONDS:-30}"
  default_region="${EXISTING_REGION:-}"
  default_isp="${EXISTING_ISP:-}"
  default_tags="${EXISTING_TAGS:-}"

  local server_host server_port token agent_id interval_seconds region isp tags server_url
  server_host="$(read_tty "服务端 IP / 域名" "${default_server_host:-}")"
  server_port="$(read_tty "服务端端口" "$default_server_port")"
  token="$(read_tty "Agent Token" "$default_token")"
  agent_id="$(read_tty "节点唯一 ID（留空默认主机名）" "$default_agent_id")"
  interval_seconds="$(read_tty "上报间隔秒数" "$default_interval")"
  region="$(read_tty "区域（可留空）" "$default_region")"
  isp="$(read_tty "运营商 / 线路（可留空）" "$default_isp")"
  tags="$(read_tty "标签，逗号分隔（可留空）" "$default_tags")"

  server_url="http://${server_host}:${server_port}/api/v1/report"
  write_agent_files "$server_url" "$agent_id" "$interval_seconds" "$token" "$region" "$isp" "$tags"
  ${SUDO} systemctl enable --now "$SERVICE_NAME"

  say ""
  say "${APP_NAME} 已安装 / 更新："
  say "  配置文件: ${CONFIG_FILE}"
  say "  服务名: ${SERVICE_NAME}"
  say "  上报地址: ${server_url}"
  say "  查看状态: ${SUDO} systemctl status ${SERVICE_NAME}"
  say "  查看日志: ${SUDO} journalctl -u ${SERVICE_NAME} -f"
}

uninstall_client() {
  if service_exists; then
    ${SUDO} systemctl disable --now "$SERVICE_NAME" >/dev/null 2>&1 || true
    ${SUDO} rm -f "$SYSTEMD_FILE"
    ${SUDO} systemctl daemon-reload
  fi
  ${SUDO} rm -rf "$INSTALL_DIR"
  say "${APP_NAME} 已卸载。"
}

start_client() {
  service_exists || fail "未检测到 ${SERVICE_NAME}，请先安装。"
  ${SUDO} systemctl start "$SERVICE_NAME"
  say "${SERVICE_NAME} 已启动。"
}

restart_client() {
  service_exists || fail "未检测到 ${SERVICE_NAME}，请先安装。"
  ${SUDO} systemctl restart "$SERVICE_NAME"
  say "${SERVICE_NAME} 已重启。"
}

stop_client() {
  service_exists || fail "未检测到 ${SERVICE_NAME}，请先安装。"
  ${SUDO} systemctl stop "$SERVICE_NAME"
  say "${SERVICE_NAME} 已停止。"
}

status_client() {
  service_exists || fail "未检测到 ${SERVICE_NAME}，请先安装。"
  ${SUDO} systemctl status "$SERVICE_NAME" --no-pager
}

logs_client() {
  service_exists || fail "未检测到 ${SERVICE_NAME}，请先安装。"
  ${SUDO} journalctl -u "$SERVICE_NAME" -f
}

reconfigure_client() {
  client_installed || fail "未检测到客户端配置，请先安装。"
  install_or_update_client
}

show_menu() {
  echo "请选择操作:"
  echo "1) 安装/更新"
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
    1|2) install_or_update_client ;;
    3) uninstall_client ;;
    4) start_client ;;
    5) restart_client ;;
    6) stop_client ;;
    7) status_client ;;
    8) logs_client ;;
    9) reconfigure_client ;;
    0) exit 0 ;;
    *) fail "无效选择" ;;
  esac
}

case "${1:-menu}" in
  install|update|upgrade)
    install_or_update_client
    ;;
  uninstall|remove)
    uninstall_client
    ;;
  start)
    start_client
    ;;
  restart)
    restart_client
    ;;
  stop)
    stop_client
    ;;
  status)
    status_client
    ;;
  logs|log)
    logs_client
    ;;
  reconfigure|config)
    reconfigure_client
    ;;
  ""|menu)
    show_menu
    ;;
  *)
    echo "用法:"
    echo "  bash scripts/install-linux-client.sh            # 交互菜单"
    echo "  bash scripts/install-linux-client.sh install    # 安装/更新"
    echo "  bash scripts/install-linux-client.sh uninstall  # 卸载"
    echo "  bash scripts/install-linux-client.sh start      # 启动"
    echo "  bash scripts/install-linux-client.sh restart    # 重启"
    echo "  bash scripts/install-linux-client.sh stop       # 停止"
    echo "  bash scripts/install-linux-client.sh status     # 查看状态"
    echo "  bash scripts/install-linux-client.sh logs       # 查看日志"
    echo "  bash scripts/install-linux-client.sh reconfigure # 重新配置"
    exit 1
    ;;
esac
