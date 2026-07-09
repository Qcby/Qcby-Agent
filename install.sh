#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

run_server() {
  bash "${SCRIPT_DIR}/scripts/install-server.sh"
}

run_linux_client() {
  bash "${SCRIPT_DIR}/scripts/install-linux-client.sh"
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
    exit 1
    ;;
esac
