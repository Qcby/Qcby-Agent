#!/usr/bin/env bash
set -euo pipefail

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
  curl -fsS --max-time 8 https://api4.ipify.org 2>/dev/null || curl -fsS --max-time 8 https://api.ip.sb/ip 2>/dev/null || curl -fsS --max-time 8 https://api.ipify.org 2>/dev/null || true
}

lookup_geo_json() {
  local ip="$1"
  if [[ -z "$ip" ]]; then
    echo '{}'
    return
  fi
  curl -fsS --max-time 10 "http://ip-api.com/json/${ip}?lang=zh-CN" 2>/dev/null     || curl -fsS --max-time 10 "https://ipwho.is/${ip}" 2>/dev/null     || curl -fsS --max-time 10 "https://api.ip.sb/geoip/${ip}" 2>/dev/null     || echo '{}'
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
  local ip
  ip="$(get_public_ip)"
  PUBLIC_IP="$ip" python3 - <<'PY'
import json, os, re, urllib.request
ip = os.environ.get('PUBLIC_IP', '').strip()
if not ip:
    print(json.dumps({
        'public_ip': '',
        'country_code': '',
        'country_name': '',
        'country_name_zh': '',
        'region_name': '',
        'region_name_zh': '',
        'city_name': '',
        'city_name_zh': '',
        'location_label': '',
        'location_label_zh': '',
        'isp_name': '',
        'geo_source': ''
    }, ensure_ascii=False))
    raise SystemExit

queries = [
    {'url': f"http://ip-api.com/json/{ip}?lang=zh-CN", 'source': 'ip-api-zh', 'prefer_zh': True},
    {'url': f"https://ipwho.is/{ip}", 'source': 'ipwho.is', 'prefer_zh': False},
    {'url': f"https://api.ip.sb/geoip/{ip}", 'source': 'api.ip.sb', 'prefer_zh': False},
]

def pick(*values):
    for value in values:
        text = str(value or '').strip()
        if text:
            return text
    return ''

def has_cjk(value):
    return bool(re.search(r'[\u3400-\u9fff]', str(value or '')))

def join_parts(parts, sep=' '):
    out = []
    for p in parts:
        text = str(p or '').strip()
        if text and text not in out:
            out.append(text)
    return sep.join(out)

def normalize(raw, source, prefer_zh=False):
    country_code = pick(raw.get('countryCode'), raw.get('country_code'))
    country_name = pick(raw.get('country'), raw.get('country_name'))
    region_name = pick(raw.get('regionName'), raw.get('region_name'), raw.get('region'))
    city_name = pick(raw.get('city'), raw.get('city_name'))
    location_label_raw = pick(raw.get('location_label'), raw.get('location'))
    isp_name = pick(raw.get('isp'), raw.get('organization'), (raw.get('connection') or {}).get('isp'), (raw.get('connection') or {}).get('org'), raw.get('org'))

    country_name_zh = pick(raw.get('country_name_zh'), raw.get('country_zh'))
    region_name_zh = pick(raw.get('region_name_zh'), raw.get('region_zh'), raw.get('regionNameZh'))
    city_name_zh = pick(raw.get('city_name_zh'), raw.get('city_zh'))
    location_label_zh = pick(raw.get('location_label_zh'), raw.get('location_zh'))

    if prefer_zh or has_cjk(country_name):
        country_name_zh = country_name_zh or country_name
    if prefer_zh or has_cjk(region_name):
        region_name_zh = region_name_zh or region_name
    if prefer_zh or has_cjk(city_name):
        city_name_zh = city_name_zh or city_name
    if prefer_zh or has_cjk(location_label_raw):
        location_label_zh = location_label_zh or location_label_raw

    location_label_zh = location_label_zh or join_parts([country_name_zh, region_name_zh, city_name_zh])
    primary_country = country_name_zh or country_name
    primary_region = region_name_zh or region_name
    primary_city = city_name_zh or city_name
    location_label = location_label_zh or location_label_raw or join_parts([primary_country or country_code, primary_region, primary_city])

    return {
        'public_ip': ip,
        'country_code': country_code,
        'country_name': primary_country,
        'country_name_zh': country_name_zh,
        'region_name': primary_region,
        'region_name_zh': region_name_zh,
        'city_name': primary_city,
        'city_name_zh': city_name_zh,
        'location_label': location_label,
        'location_label_zh': location_label_zh,
        'isp_name': isp_name,
        'geo_source': source,
    }

result = {
    'public_ip': ip,
    'country_code': '',
    'country_name': '',
    'country_name_zh': '',
    'region_name': '',
    'region_name_zh': '',
    'city_name': '',
    'city_name_zh': '',
    'location_label': '',
    'location_label_zh': '',
    'isp_name': '',
    'geo_source': ''
}
for query in queries:
    try:
        with urllib.request.urlopen(query['url'], timeout=10) as r:
            raw = json.loads(r.read().decode('utf-8', 'replace'))
        if raw.get('status') == 'fail' or raw.get('success') is False:
            continue
        normalized = normalize(raw, query['source'], query['prefer_zh'])
        if normalized['country_code'] or normalized['country_name'] or normalized['location_label']:
            result = normalized
            break
    except Exception:
        continue
print(json.dumps(result, ensure_ascii=False))
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

build_identity() {
  local hostname os_version cpu_model cpu_cores mem_total_mb disk_total_gb ips_json tags_json geo_json public_ip country_code country_name country_name_zh region_name region_name_zh city_name city_name_zh location_label location_label_zh isp_name geo_source flavor_tag final_tags_json uptime_seconds
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
  country_name="$(GEO_JSON="$geo_json" python3 - <<'PY'
import json, os
geo = json.loads(os.environ['GEO_JSON'])
print(geo.get('country_name',''))
PY
)"
  country_name_zh="$(GEO_JSON="$geo_json" python3 - <<'PY'
import json, os
geo = json.loads(os.environ['GEO_JSON'])
print(geo.get('country_name_zh',''))
PY
)"
  region_name="$(GEO_JSON="$geo_json" python3 - <<'PY'
import json, os
geo = json.loads(os.environ['GEO_JSON'])
print(geo.get('region_name',''))
PY
)"
  region_name_zh="$(GEO_JSON="$geo_json" python3 - <<'PY'
import json, os
geo = json.loads(os.environ['GEO_JSON'])
print(geo.get('region_name_zh',''))
PY
)"
  city_name="$(GEO_JSON="$geo_json" python3 - <<'PY'
import json, os
geo = json.loads(os.environ['GEO_JSON'])
print(geo.get('city_name',''))
PY
)"
  city_name_zh="$(GEO_JSON="$geo_json" python3 - <<'PY'
import json, os
geo = json.loads(os.environ['GEO_JSON'])
print(geo.get('city_name_zh',''))
PY
)"
  location_label="$(GEO_JSON="$geo_json" python3 - <<'PY'
import json, os
geo = json.loads(os.environ['GEO_JSON'])
print(geo.get('location_label',''))
PY
)"
  location_label_zh="$(GEO_JSON="$geo_json" python3 - <<'PY'
import json, os
geo = json.loads(os.environ['GEO_JSON'])
print(geo.get('location_label_zh',''))
PY
)"
  isp_name="$(GEO_JSON="$geo_json" python3 - <<'PY'
import json, os
geo = json.loads(os.environ['GEO_JSON'])
print(geo.get('isp_name',''))
PY
)"
  geo_source="$(GEO_JSON="$geo_json" python3 - <<'PY'
import json, os
geo = json.loads(os.environ['GEO_JSON'])
print(geo.get('geo_source',''))
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
  COUNTRY_NAME_VAL="$country_name" \
  COUNTRY_NAME_ZH_VAL="$country_name_zh" \
  REGION_NAME_VAL="$region_name" \
  REGION_NAME_ZH_VAL="$region_name_zh" \
  CITY_NAME_VAL="$city_name" \
  CITY_NAME_ZH_VAL="$city_name_zh" \
  LOCATION_LABEL_VAL="$location_label" \
  LOCATION_LABEL_ZH_VAL="$location_label_zh" \
  ISP_NAME_VAL="$isp_name" \
  GEO_SOURCE_VAL="$geo_source" \
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
  "country_name": os.environ.get('COUNTRY_NAME_VAL', ''),
  "country_name_zh": os.environ.get('COUNTRY_NAME_ZH_VAL', ''),
  "region_name": os.environ.get('REGION_NAME_VAL', ''),
  "region_name_zh": os.environ.get('REGION_NAME_ZH_VAL', ''),
  "city_name": os.environ.get('CITY_NAME_VAL', ''),
  "city_name_zh": os.environ.get('CITY_NAME_ZH_VAL', ''),
  "location_label": os.environ.get('LOCATION_LABEL_VAL', ''),
  "location_label_zh": os.environ.get('LOCATION_LABEL_ZH_VAL', ''),
  "geo_source": os.environ.get('GEO_SOURCE_VAL', ''),
  "uptime_seconds": int(float(os.environ.get('UPTIME_SECONDS_VAL', '0') or 0)),
  "tags": json.loads(os.environ['TAGS_JSON_VAL'])
}, ensure_ascii=False))
PY
}

read_net_bytes() {
  awk -F '[: ]+' 'NR>2 {rx+=$3; tx+=$11} END {printf "%.0f %.0f", rx, tx}' /proc/net/dev
}

get_uptime_seconds() {
  awk '{printf "%d", $1}' /proc/uptime 2>/dev/null || echo 0
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
  python3 - <<'PY' >/tmp/qcby-agent-payload.json
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

  if curl -fsS -X POST "$SERVER_URL" -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json; charset=utf-8' --data-binary @/tmp/qcby-agent-payload.json >/dev/null; then
    echo "[$(date '+%F %T')] Reported CPU=${cpu_percent}% MEM=${mem_percent}% DISK=${disk_percent}% RX=${network_rx_mbps}Mbps TX=${network_tx_mbps}Mbps"
  else
    echo "[$(date '+%F %T')] Report failed"
  fi

  sleep "$INTERVAL_SECONDS"
done
