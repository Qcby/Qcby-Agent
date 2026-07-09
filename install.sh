#!/usr/bin/env bash
set -euo pipefail

APP_NAME="NodePulse Linux Agent"
INSTALL_DIR="/opt/nodepulse"
SERVICE_NAME="nodepulse-agent"
CONFIG_FILE="${INSTALL_DIR}/agent.env"
AGENT_FILE="${INSTALL_DIR}/agent.sh"
SYSTEMD_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
DEFAULT_TOKEN="change-me-token"
DEFAULT_INTERVAL="15"

if [[ ${EUID} -eq 0 ]]; then
  SUDO=""
else
  SUDO="sudo"
fi

say() {
  echo "$*"
}

warn() {
  echo "[WARN] $*"
}

fail() {
  echo "[ERROR] $*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "缺少命令: $1"
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

confirm_tty() {
  local prompt="$1"
  local answer
  read -r -p "$prompt [y/N]: " answer </dev/tty || true
  [[ "$answer" =~ ^[Yy]$ ]]
}

ensure_dirs() {
  ${SUDO} mkdir -p "$INSTALL_DIR"
}

write_agent() {
  ${SUDO} tee "$AGENT_FILE" > /dev/null <<'AGENT_EOF'
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/agent.env"

if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
fi

SERVER_URL="${SERVER_URL:-http://146.56.140.150:8080/api/v1/report}"
AGENT_ID="${AGENT_ID:-$(hostname)}"
INTERVAL_SECONDS="${INTERVAL_SECONDS:-15}"
TOKEN="${TOKEN:-change-me-token}"
REGION="${REGION:-}"
ISP="${ISP:-}"
TAGS="${TAGS:-}"

command -v curl >/dev/null 2>&1 || { echo 'curl 未安装'; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo 'python3 未安装'; exit 1; }

get_public_ip() {
  curl -fsS --max-time 8 https://api4.ipify.org 2>/dev/null \
    || curl -fsS --max-time 8 https://api.ip.sb/ip 2>/dev/null \
    || curl -fsS --max-time 8 https://api.ipify.org 2>/dev/null \
    || true
}

lookup_geo_json() {
  local ip="$1"
  if [[ -z "$ip" ]]; then
    echo '{}'
    return
  fi
  curl -fsS --max-time 10 "https://api.ip.sb/geoip/${ip}" 2>/dev/null \
    || curl -fsS --max-time 10 "https://ipwho.is/${ip}" 2>/dev/null \
    || curl -fsS --max-time 10 "http://ip-api.com/json/${ip}?lang=zh-CN" 2>/dev/null \
    || echo '{}'
}

get_ips_json() {
  python3 - <<'PY'
import json, subprocess
ips = []
try:
    out = subprocess.check_output("hostname -I", shell=True, text=True).strip()
    for ip in out.split():
        if ip and not ip.startswith("127."):
            ips.append(ip)
except Exception:
    pass
print(json.dumps(ips, ensure_ascii=False))
PY
}

get_geo_fields() {
  local ip geo_json
  ip="$(get_public_ip)"
  geo_json="$(lookup_geo_json "$ip")"
  GEO_JSON="$geo_json" PUBLIC_IP="$ip" python3 - <<'PY'
import json, os
raw_text = os.environ.get('GEO_JSON', '').strip()
raw = json.loads(raw_text) if raw_text else {}
country = raw.get('country_code') or raw.get('countryCode') or raw.get('country') or ''
region = raw.get('regionName') or raw.get('region') or ''
city = raw.get('city') or ''
isp = (raw.get('isp') or raw.get('organization') or (raw.get('connection') or {}).get('isp') or (raw.get('connection') or {}).get('org') or raw.get('org') or '')
parts = []
for p in [country, region, city]:
    if p and p not in parts:
        parts.append(p)
print(json.dumps({
  'public_ip': os.environ.get('PUBLIC_IP', ''),
  'country_code': country,
  'region_name': region,
  'city_name': city,
  'location_label': ' '.join(parts) if parts else '',
  'isp_name': isp
}, ensure_ascii=False))
PY
}

get_os_flavor_tag() {
  python3 - <<'PY'
import re, pathlib
text = pathlib.Path('/etc/os-release').read_text(encoding='utf-8', errors='ignore')
pretty = ''
for line in text.splitlines():
    if line.startswith('PRETTY_NAME='):
        pretty = line.split('=', 1)[1].strip().strip('"')
        break
s = pretty.lower()
if 'centos' in s and '7' in s:
    print('centos7')
elif 'centos' in s:
    print('centos')
elif 'ubuntu' in s:
    m = re.search(r'ubuntu\s+(\d+)', s)
    print(f"ubuntu{m.group(1)}" if m else 'ubuntu')
elif 'debian' in s:
    m = re.search(r'debian.*?(\d+)', s)
    print(f"debian{m.group(1)}" if m else 'debian')
elif 'rocky' in s:
    print('rockylinux')
elif 'alma' in s:
    print('almalinux')
else:
    print('linux')
PY
}

read_net_bytes() {
  awk -F '[: ]+' 'NR>2 {rx+=$3; tx+=$11} END {printf "%.0f %.0f", rx, tx}' /proc/net/dev
}

get_uptime_seconds() {
  awk '{printf "%d", $1}' /proc/uptime 2>/dev/null || echo 0
}

build_identity() {
  local hostname os_version cpu_model cpu_cores mem_total_mb disk_total_gb ips_json tags_json geo_json public_ip country_code region_name city_name location_label isp_name flavor_tag uptime_seconds
  hostname="$(hostname)"
  os_version="$(grep PRETTY_NAME= /etc/os-release 2>/dev/null | head -n1 | cut -d= -f2- | tr -d '"')"
  cpu_model="$(awk -F: '/model name/ {gsub(/^ +/, "", $2); print $2; exit}' /proc/cpuinfo 2>/dev/null)"
  cpu_cores="$(nproc 2>/dev/null || echo 0)"
  mem_total_mb="$(awk '/MemTotal/ {printf "%d", $2/1024}' /proc/meminfo 2>/dev/null)"
  disk_total_gb="$(df -BG / | awk 'NR==2 {gsub(/G/,"",$2); print $2+0}')"
  ips_json="$(get_ips_json)"
  geo_json="$(get_geo_fields)"
  public_ip="$(GEO_JSON="$geo_json" python3 - <<'PY'
import json, os
geo = json.loads(os.environ['GEO_JSON'])
print(geo.get('public_ip',''))
PY
)"
  country_code="$(GEO_JSON="$geo_json" python3 - <<'PY'
import json, os
geo = json.loads(os.environ['GEO_JSON'])
print(geo.get('country_code',''))
PY
)"
  region_name="$(GEO_JSON="$geo_json" python3 - <<'PY'
import json, os
geo = json.loads(os.environ['GEO_JSON'])
print(geo.get('region_name',''))
PY
)"
  city_name="$(GEO_JSON="$geo_json" python3 - <<'PY'
import json, os
geo = json.loads(os.environ['GEO_JSON'])
print(geo.get('city_name',''))
PY
)"
  location_label="$(GEO_JSON="$geo_json" python3 - <<'PY'
import json, os
geo = json.loads(os.environ['GEO_JSON'])
print(geo.get('location_label',''))
PY
)"
  isp_name="$(GEO_JSON="$geo_json" python3 - <<'PY'
import json, os
geo = json.loads(os.environ['GEO_JSON'])
print(geo.get('isp_name',''))
PY
)"
  flavor_tag="$(get_os_flavor_tag)"
  uptime_seconds="$(get_uptime_seconds)"
  tags_json="$(TAGS_INPUT="$TAGS" COUNTRY_CODE="$country_code" REGION_NAME="$region_name" CITY_NAME="$city_name" LOCATION_LABEL="$location_label" FLAVOR_TAG="$flavor_tag" python3 - <<'PY'
import json, os
items = []
raw = os.environ.get('TAGS_INPUT', '')
if raw:
    items.extend([x.strip() for x in raw.split(',') if x.strip()])
items.append('linux')
flavor = os.environ.get('FLAVOR_TAG', '').strip()
if flavor:
    items.append(flavor)
country = os.environ.get('COUNTRY_CODE', '').strip().lower()
if country:
    items.append(country)
region = os.environ.get('REGION_NAME', '').strip()
city = os.environ.get('CITY_NAME', '').strip()
location = os.environ.get('LOCATION_LABEL', '').strip()
if location:
    items.append(location)
elif region or city:
    items.append('·'.join([x for x in [region, city] if x]))
seen = set()
out = []
for x in items:
    if x and x not in seen:
        seen.add(x)
        out.append(x)
print(json.dumps(out, ensure_ascii=False))
PY
)"

  HOSTNAME_VAL="$hostname" \
  OS_VERSION_VAL="$os_version" \
  CPU_MODEL_VAL="$cpu_model" \
  CPU_CORES_VAL="$cpu_cores" \
  MEM_TOTAL_MB_VAL="$mem_total_mb" \
  DISK_TOTAL_GB_VAL="$disk_total_gb" \
  IPS_JSON_VAL="$ips_json" \
  TAGS_JSON_VAL="$tags_json" \
  REGION_OVERRIDE_VAL="$REGION" \
  ISP_OVERRIDE_VAL="$ISP" \
  AGENT_ID_VAL="$AGENT_ID" \
  PUBLIC_IP_VAL="$public_ip" \
  COUNTRY_CODE_VAL="$country_code" \
  REGION_NAME_VAL="$region_name" \
  CITY_NAME_VAL="$city_name" \
  LOCATION_LABEL_VAL="$location_label" \
  ISP_NAME_VAL="$isp_name" \
  UPTIME_SECONDS_VAL="$uptime_seconds" \
  python3 - <<'PY'
import json, os
region_override = os.environ.get('REGION_OVERRIDE_VAL', '').strip()
isp_override = os.environ.get('ISP_OVERRIDE_VAL', '').strip()
region_value = region_override or os.environ.get('COUNTRY_CODE_VAL', '')
isp_value = isp_override or os.environ.get('ISP_NAME_VAL', '')
print(json.dumps({
  "agent_id": os.environ['AGENT_ID_VAL'],
  "hostname": os.environ['HOSTNAME_VAL'],
  "os_type": "linux",
  "os_version": os.environ['OS_VERSION_VAL'],
  "ip_addresses": json.loads(os.environ['IPS_JSON_VAL']),
  "cpu_model": os.environ['CPU_MODEL_VAL'],
  "cpu_cores": int(float(os.environ.get('CPU_CORES_VAL', '0') or 0)),
  "memory_total_mb": int(float(os.environ.get('MEM_TOTAL_MB_VAL', '0') or 0)),
  "disk_total_gb": float(os.environ.get('DISK_TOTAL_GB_VAL', '0') or 0),
  "docker_version": "",
  "region": region_value,
  "isp": isp_value,
  "public_ip": os.environ.get('PUBLIC_IP_VAL', ''),
  "country_code": os.environ.get('COUNTRY_CODE_VAL', ''),
  "region_name": os.environ.get('REGION_NAME_VAL', ''),
  "city_name": os.environ.get('CITY_NAME_VAL', ''),
  "location_label": os.environ.get('LOCATION_LABEL_VAL', ''),
  "uptime_seconds": int(float(os.environ.get('UPTIME_SECONDS_VAL', '0') or 0)),
  "tags": json.loads(os.environ['TAGS_JSON_VAL'])
}, ensure_ascii=False))
PY
}

IDENTITY_JSON="$(build_identity)"
read -r last_rx last_tx <<< "$(read_net_bytes)"
last_ts="$(date +%s)"
echo "[$(date '+%F %T')] Linux agent started -> $SERVER_URL (interval ${INTERVAL_SECONDS}s)"

while true; do
  cpu_percent="$(python3 - <<'PY'
import time

def read_cpu():
    with open('/proc/stat', 'r', encoding='utf-8') as f:
        parts = f.readline().split()[1:]
    vals = list(map(int, parts[:8]))
    idle = vals[3] + vals[4]
    total = sum(vals)
    return idle, total

idle1, total1 = read_cpu()
time.sleep(1)
idle2, total2 = read_cpu()
delta_idle = idle2 - idle1
delta_total = total2 - total1
usage = 0 if delta_total <= 0 else (1 - delta_idle / delta_total) * 100
print(f"{usage:.2f}")
PY
)"

  read -r mem_used_mb mem_total_mb mem_percent <<< "$(awk '
    /MemTotal/ {total=$2/1024}
    /MemAvailable/ {avail=$2/1024}
    END {
      used=total-avail;
      pct=(total>0)?used/total*100:0;
      printf "%.2f %.2f %.2f", used, total, pct;
    }
  ' /proc/meminfo)"

  read -r disk_used_gb disk_total_gb disk_percent <<< "$(df -BG / | awk 'NR==2 {
    gsub(/G/,"",$2); gsub(/G/,"",$3); gsub(/%/,"",$5);
    printf "%s %s %s", $3+0, $2+0, $5+0
  }')"

  read -r load_1 load_5 load_15 _ < /proc/loadavg
  process_count="$(ps -e --no-headers | wc -l | awk '{print $1}')"
  read -r rx tx <<< "$(read_net_bytes)"
  now_ts="$(date +%s)"
  elapsed=$(( now_ts - last_ts ))
  if [ "$elapsed" -le 0 ]; then elapsed=1; fi

  network_rx_mbps="$(RX="$rx" LAST_RX="$last_rx" ELAPSED="$elapsed" python3 - <<'PY'
import os
rx_delta = max(0, int(float(os.environ['RX'])) - int(float(os.environ['LAST_RX'])))
elapsed = max(1, int(float(os.environ['ELAPSED'])))
print(f"{(rx_delta * 8 / 1024 / 1024) / elapsed:.2f}")
PY
)"

  network_tx_mbps="$(TX="$tx" LAST_TX="$last_tx" ELAPSED="$elapsed" python3 - <<'PY'
import os
tx_delta = max(0, int(float(os.environ['TX'])) - int(float(os.environ['LAST_TX'])))
elapsed = max(1, int(float(os.environ['ELAPSED'])))
print(f"{(tx_delta * 8 / 1024 / 1024) / elapsed:.2f}")
PY
)"

  last_rx="$rx"
  last_tx="$tx"
  last_ts="$now_ts"

  IDENTITY_JSON="$(build_identity)"

  CPU_PERCENT_VAL="$cpu_percent" \
  MEM_USED_MB_VAL="$mem_used_mb" \
  MEM_TOTAL_MB_VAL="$mem_total_mb" \
  MEM_PERCENT_VAL="$mem_percent" \
  DISK_USED_GB_VAL="$disk_used_gb" \
  DISK_TOTAL_GB_VAL="$disk_total_gb" \
  DISK_PERCENT_VAL="$disk_percent" \
  LOAD1_VAL="$load_1" \
  LOAD5_VAL="$load_5" \
  LOAD15_VAL="$load_15" \
  PROCESS_COUNT_VAL="$process_count" \
  RX_MBPS_VAL="$network_rx_mbps" \
  TX_MBPS_VAL="$network_tx_mbps" \
  IDENTITY_JSON_VAL="$IDENTITY_JSON" \
  python3 - <<'PY' >/tmp/nodepulse-payload.json
import json, datetime, os
payload = {
  "timestamp": datetime.datetime.utcnow().isoformat() + "Z",
  "identity": json.loads(os.environ["IDENTITY_JSON_VAL"]),
  "metrics": {
    "cpu_percent": float(os.environ.get("CPU_PERCENT_VAL", "0") or 0),
    "memory_used_mb": float(os.environ.get("MEM_USED_MB_VAL", "0") or 0),
    "memory_total_mb": float(os.environ.get("MEM_TOTAL_MB_VAL", "0") or 0),
    "memory_percent": float(os.environ.get("MEM_PERCENT_VAL", "0") or 0),
    "disk_used_gb": float(os.environ.get("DISK_USED_GB_VAL", "0") or 0),
    "disk_total_gb": float(os.environ.get("DISK_TOTAL_GB_VAL", "0") or 0),
    "disk_percent": float(os.environ.get("DISK_PERCENT_VAL", "0") or 0),
    "load_1": float(os.environ.get("LOAD1_VAL", "0") or 0),
    "load_5": float(os.environ.get("LOAD5_VAL", "0") or 0),
    "load_15": float(os.environ.get("LOAD15_VAL", "0") or 0),
    "process_count": int(float(os.environ.get("PROCESS_COUNT_VAL", "0") or 0)),
    "network_rx_mbps": float(os.environ.get("RX_MBPS_VAL", "0") or 0),
    "network_tx_mbps": float(os.environ.get("TX_MBPS_VAL", "0") or 0),
    "docker_running": False,
    "docker_containers_running": 0,
    "docker_containers_total": 0
  }
}
print(json.dumps(payload, ensure_ascii=False))
PY

  if curl -fsS -X POST "$SERVER_URL" -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json; charset=utf-8' --data-binary @/tmp/nodepulse-payload.json >/dev/null; then
    echo "[$(date '+%F %T')] Reported CPU=${cpu_percent}% MEM=${mem_percent}% DISK=${disk_percent}% RX=${network_rx_mbps}Mbps TX=${network_tx_mbps}Mbps"
  else
    echo "[$(date '+%F %T')] Report failed"
  fi

  sleep "$INTERVAL_SECONDS"
done
AGENT_EOF
}

write_systemd() {
  ${SUDO} tee "$SYSTEMD_FILE" > /dev/null <<EOF
[Unit]
Description=NodePulse Linux Agent
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=${INSTALL_DIR}
EnvironmentFile=${CONFIG_FILE}
ExecStart=/bin/bash ${AGENT_FILE}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
}

write_config() {
  local server_host server_port server_url token interval region isp tags
  server_host="$(read_tty '请输入服务端 IP 或域名')"
  server_port="$(read_tty '请输入服务端端口' '8080')"
  token="$(read_tty '请输入 Token' "$DEFAULT_TOKEN")"
  interval="$(read_tty '上报间隔秒数' "$DEFAULT_INTERVAL")"
  region="$(read_tty '地区覆盖(留空自动识别)' '')"
  isp="$(read_tty 'ISP 覆盖(留空自动识别)' '')"
  tags="$(read_tty '额外标签(逗号分隔，可留空)' '')"

  server_host="${server_host#http://}"
  server_host="${server_host#https://}"
  server_host="${server_host%%/}"
  server_url="http://${server_host}:${server_port}/api/v1/report"

  ${SUDO} tee "$CONFIG_FILE" > /dev/null <<EOF
SERVER_URL="${server_url}"
TOKEN="${token}"
INTERVAL_SECONDS="${interval}"
REGION="${region}"
ISP="${isp}"
TAGS="${tags}"
EOF
}

install_agent() {
  say "开始安装 ${APP_NAME} ..."
  ensure_dirs
  write_agent
  write_config
  write_systemd
  ${SUDO} chmod +x "$AGENT_FILE"
  ${SUDO} systemctl daemon-reload
  ${SUDO} systemctl enable --now "$SERVICE_NAME"
  say "安装完成。"
  ${SUDO} systemctl status "$SERVICE_NAME" --no-pager || true
}

update_agent() {
  say "更新 ${APP_NAME} ..."
  ensure_dirs
  write_agent
  ${SUDO} chmod +x "$AGENT_FILE"
  if [[ -f "$CONFIG_FILE" ]]; then
    if confirm_tty '是否重新配置服务端信息？'; then
      write_config
    fi
  else
    write_config
  fi
  write_systemd
  ${SUDO} systemctl daemon-reload
  ${SUDO} systemctl restart "$SERVICE_NAME"
  say "更新完成。"
  ${SUDO} systemctl status "$SERVICE_NAME" --no-pager || true
}

uninstall_agent() {
  if ! confirm_tty '确认卸载 NodePulse 客户端？'; then
    say '已取消。'
    return
  fi
  ${SUDO} systemctl disable --now "$SERVICE_NAME" 2>/dev/null || true
  ${SUDO} rm -f "$SYSTEMD_FILE"
  ${SUDO} rm -rf "$INSTALL_DIR"
  ${SUDO} systemctl daemon-reload
  say '卸载完成。'
}

start_agent() {
  ${SUDO} systemctl start "$SERVICE_NAME"
  ${SUDO} systemctl status "$SERVICE_NAME" --no-pager || true
}

restart_agent() {
  ${SUDO} systemctl restart "$SERVICE_NAME"
  ${SUDO} systemctl status "$SERVICE_NAME" --no-pager || true
}

stop_agent() {
  ${SUDO} systemctl stop "$SERVICE_NAME"
  ${SUDO} systemctl status "$SERVICE_NAME" --no-pager || true
}

status_agent() {
  ${SUDO} systemctl status "$SERVICE_NAME" --no-pager || true
}

logs_agent() {
  ${SUDO} journalctl -u "$SERVICE_NAME" -f
}

show_menu() {
  cat <<'EOF'
=== NodePulse Linux 客户端管理脚本 ===
请选择操作:
  1) 安装
  2) 升级/更新
  3) 卸载
  4) 启动
  5) 重启
  6) 停止
  7) 查看状态
  8) 查看日志
  9) 重新配置
  0) 退出
EOF
}

reconfigure_agent() {
  ensure_dirs
  write_config
  write_systemd
  ${SUDO} systemctl daemon-reload
  ${SUDO} systemctl restart "$SERVICE_NAME"
  say '重新配置完成。'
}

main() {
  need_cmd bash
  need_cmd curl
  need_cmd python3
  need_cmd systemctl

  local action="${1:-}"
  case "$action" in
    install) install_agent; return ;;
    update) update_agent; return ;;
    uninstall) uninstall_agent; return ;;
    start) start_agent; return ;;
    restart) restart_agent; return ;;
    stop) stop_agent; return ;;
    status) status_agent; return ;;
    logs) logs_agent; return ;;
    reconfig) reconfigure_agent; return ;;
  esac

  while true; do
    show_menu
    choice="$(read_tty '输入数字' '')"
    case "$choice" in
      1) install_agent ;;
      2) update_agent ;;
      3) uninstall_agent ;;
      4) start_agent ;;
      5) restart_agent ;;
      6) stop_agent ;;
      7) status_agent ;;
      8) logs_agent ;;
      9) reconfigure_agent ;;
      0) say '退出脚本'; exit 0 ;;
      *) warn '无效选择，请重新输入。' ;;
    esac
    echo
  done
}

main "$@"
