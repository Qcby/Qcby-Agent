#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RAW_BASE="${QCBY_AGENT_RAW_BASE:-https://raw.githubusercontent.com/Qcby/Qcby-Agent/main}"

run_remote_script() {
  local relative_path="$1"
  local temp_file
  local status
  temp_file="$(mktemp)"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "${RAW_BASE}/${relative_path}" -o "$temp_file"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$temp_file" "${RAW_BASE}/${relative_path}"
  else
    rm -f "$temp_file"
    echo "缺少 curl 或 wget，无法远程下载安装脚本。" >&2
    exit 1
  fi
  bash "$temp_file"
  status=$?
  rm -f "$temp_file"
  return $status
}

run_server() {
  if [[ -f "${SCRIPT_DIR}/scripts/install-server.sh" ]]; then
    bash "${SCRIPT_DIR}/scripts/install-server.sh"
  else
    run_remote_script "scripts/install-server.sh"
  fi
}

run_linux_client() {
  if [[ -f "${SCRIPT_DIR}/scripts/install-linux-client.sh" ]]; then
    bash "${SCRIPT_DIR}/scripts/install-linux-client.sh"
  else
    run_remote_script "scripts/install-linux-client.sh"
  fi
}

show_menu() {
  echo "Qcby-Agent 安装入口"
  echo "1) 安装 / 升级服务端"
  echo "2) 安装 / 升级 Linux 客户端"
  echo "q) 退出"
  read -r -p "请选择 [1/2/q]: " choice
  case "${choice}" in
    1) run_server ;;
    2) run_linux_client ;;
    q|Q) exit 0 ;;
    *) echo "无效选择"; exit 1 ;;
  esac
}

case "${1:-}" in
  server)
    run_server
    ;;
  linux-client|client)
    run_linux_client
    ;;
  ""|menu)
    show_menu
    ;;
  *)
    echo "用法:"
    echo "  bash install.sh             # 交互菜单"
    echo "  bash install.sh server      # 安装 / 升级服务端"
    echo "  bash install.sh client      # 安装 / 升级 Linux 客户端"
    echo ""
    echo "一键远程安装示例:"
    echo "  bash <(curl -sSL ${RAW_BASE}/install.sh) server"
    echo "  bash <(curl -sSL ${RAW_BASE}/install.sh) client"
    exit 1
    ;;
esac
