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

main() {
  need_cmd bash
  need_cmd systemctl

  SERVER_HOST="$(read_tty "服务端 IP / 域名" "146.56.140.150")"
  SERVER_PORT="$(read_tty "服务端端口" "8080")"
  TOKEN="$(read_tty "Agent Token" "change-me-token")"
  AGENT_ID="$(read_tty "节点唯一 ID（留空默认主机名）" "")"
  INTERVAL_SECONDS="$(read_tty "上报间隔秒数" "30")"
  REGION="$(read_tty "区域（可留空）" "")"
  ISP="$(read_tty "运营商 / 线路（可留空）" "")"
  TAGS="$(read_tty "标签，逗号分隔（可留空）" "")"

  SERVER_URL="http://${SERVER_HOST}:${SERVER_PORT}/api/v1/report"
  ${SUDO} mkdir -p "$INSTALL_DIR"
  if [[ -f "$SOURCE_AGENT" ]]; then
    ${SUDO} cp "$SOURCE_AGENT" "$AGENT_FILE"
  else
    temp_agent="$(mktemp)"
    download_agent "$temp_agent"
    ${SUDO} cp "$temp_agent" "$AGENT_FILE"
    rm -f "$temp_agent"
  fi
  ${SUDO} chmod +x "$AGENT_FILE"

  ${SUDO} tee "$CONFIG_FILE" >/dev/null <<EOF
SERVER_URL=${SERVER_URL}
AGENT_ID=${AGENT_ID}
INTERVAL_SECONDS=${INTERVAL_SECONDS}
TOKEN=${TOKEN}
REGION=${REGION}
ISP=${ISP}
TAGS=${TAGS}
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
  ${SUDO} systemctl enable --now "$SERVICE_NAME"

  say ""
  say "${APP_NAME} 已安装："
  say "  配置文件: ${CONFIG_FILE}"
  say "  服务名: ${SERVICE_NAME}"
  say "  查看日志: ${SUDO} journalctl -u ${SERVICE_NAME} -f"
}

main "$@"
