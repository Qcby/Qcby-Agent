# Qcby-Agent

Qcby-Agent 是一个轻量的 Win / Linux 节点监控项目，提供：

- 公开监控首页
- `/admin` 登录后台
- Windows / Linux 客户端探针
- Docker 化服务端部署
- 设备公网 IP、地理信息、在线状态、资源指标展示
- 后台修改 Agent Token、绑定端口、设备展示名


---

## 目录结构

```text
server/                  服务端 Flask + 前端模板
client/linux/            Linux agent 与相关脚本
client/windows/          Windows agent 与一键安装脚本
scripts/install-server.sh        Linux 服务端安装器
scripts/install-linux-client.sh  Linux 客户端安装器
install.sh               统一安装入口
```

---



## 二、服务端本地开发

### 1) 安装依赖

```bash
cd server
python -m pip install -r requirements.txt
```

### 2) 运行

```bash
python app.py
```

默认地址：

- 首页：`http://127.0.0.1:8080/`
- 后台登录：`http://127.0.0.1:8080/admin`
- 上报接口：`http://127.0.0.1:8080/api/v1/report`

默认 bootstrap 管理员（仅首次无数据库时生效）：

- 用户名：`admin`
- 密码：`change-me-admin-password`

---

## 三、Docker 说明

### 1) 本地构建镜像

在仓库根目录执行：

```bash
docker build -t qcby/qcby-agent:local ./server
```

### 2) 本地运行（docker run）

```bash
docker run -d \
  --name qcby-agent \
  -p 8080:8080 \
  -e ONLINE_SECONDS=90 \
  -e RETENTION_DAYS=30 \
  -e AGENT_TOKEN=change-me-token \
  -e BOOTSTRAP_ADMIN_USERNAME=admin \
  -e BOOTSTRAP_ADMIN_PASSWORD=change-me-admin-password \
  -e BIND_PORT=8080 \
  -v "$(pwd)/server/data:/app/data" \
  qcby/qcby-agent:local
```

### 3) 本地运行（docker compose）

```bash
cd server
docker compose up -d --build
```

### 4) 多架构 buildx 构建与推送

```bash
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t qcby/qcby-agent:latest \
  -t qcby/qcby-agent:v1.0.0 \
  --push \
  ./server
```

如果你只想先验证本地构建：

```bash
docker buildx build \
  --platform linux/amd64 \
  -t qcby/qcby-agent:test \
  --load \
  ./server
```

### 5) 发布策略

建议每次发布至少推送两个标签：

- `qcby/qcby-agent:latest`
- `qcby/qcby-agent:v1.0.0`

### 6) 数据卷与持久化

SQLite 默认保存在：

```text
server/data/monitor.db
```

Docker 部署时请务必挂载：

```text
./data:/app/data
```

### 7) 默认端口与环境变量

容器内监听端口固定：

```text
8080
```

常用环境变量：

- `ONLINE_SECONDS`：在线判定秒数
- `RETENTION_DAYS`：历史保留天数
- `AGENT_TOKEN`：客户端上报 Token
- `BOOTSTRAP_ADMIN_USERNAME`：首次初始化后台管理员账号
- `BOOTSTRAP_ADMIN_PASSWORD`：首次初始化后台管理员密码
- `APP_SECRET_KEY`：Flask Session Secret
- `BIND_PORT`：当前对外绑定端口（用于后台显示与安装脚本）
- `HOST_ENV_FILE`：后台修改端口时写入的宿主机 `.env` 路径
- `HOST_APPLY_COMMAND`：后台提示用户执行的应用命令

### 8) 更新镜像后的升级步骤

如果是安装脚本部署的服务端：

```bash
cd /opt/qcby-agent
./manage-server.sh pull
./manage-server.sh restart
```

如果是手工 compose：

```bash
docker compose pull
docker compose up -d --force-recreate
```

### 9) 后台修改绑定端口的影响

后台允许修改“绑定端口”，但请注意：

1. 这只会保存新的目标端口配置
2. 你需要在宿主机重新应用 Docker 端口映射
3. 旧客户端会因为上报地址没同步而失联

安装脚本部署的默认应用命令：

```bash
cd /opt/qcby-agent
./manage-server.sh apply
```

### 10) 多架构兼容说明

官方发布镜像目标架构：

- `linux/amd64`
- `linux/arm64`

适用于常见：

- x86_64 云服务器
- ARM64 VPS / ARM 云主机

---

## 四、Linux 服务端一键安装

在仓库根目录执行：

```bash
bash install.sh
```

或直接：

```bash
bash install.sh server
```

也支持短命令远程执行：

```bash
bash <(curl -sSL https://raw.githubusercontent.com/Qcby/Qcby-Agent/main/install.sh) server
```

安装器会提示你输入：

- Docker 镜像标签
- 绑定端口
- Agent Token
- 后台管理员账号
- 后台管理员密码
- 在线判定秒数
- 历史保留天数

默认安装目录：

```text
/opt/qcby-agent
```

安装完成后常用命令：

```bash
cd /opt/qcby-agent
./manage-server.sh apply
./manage-server.sh logs
./manage-server.sh restart
./manage-server.sh down
```

安装完成后脚本会自动输出：

- 面板首页（内网）
- 管理后台（内网）
- 如果能探测到公网 IP，也会额外输出：
  - 面板首页（公网）
  - 管理后台（公网）

---

## 五、Linux 客户端安装与管理

### 方式 1：统一入口

```bash
bash install.sh client
```

也支持短命令远程执行：

```bash
bash <(curl -sSL https://raw.githubusercontent.com/Qcby/Qcby-Agent/main/install.sh) client
```

执行后会进入管理菜单，支持：

- 安装/更新
- 卸载
- 启动
- 重启
- 停止
- 查看状态
- 查看日志
- 重新配置

### 方式 2：直接脚本

```bash
bash scripts/install-linux-client.sh
```

也可以直接指定动作：

```bash
bash scripts/install-linux-client.sh install
bash scripts/install-linux-client.sh status
bash scripts/install-linux-client.sh logs
bash scripts/install-linux-client.sh reconfigure
bash scripts/install-linux-client.sh uninstall
```

安装时需要填写：

- 服务端 IP / 域名（默认自动探测当前执行机器的公网 IP，失败则回退内网 IP）
- 服务端端口
- Agent Token
- Agent ID（可选）
- 区域 / ISP / 标签（可选）

安装完成后会注册 systemd 服务：

```bash
systemctl status qcby-agent-client
journalctl -u qcby-agent-client -f
```

---

## 六、Windows 客户端一键安装

Windows 侧提供：

```text
client/windows/install.ps1
```

### 1) 交互式安装

以管理员 PowerShell 运行：

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
PowerShell -ExecutionPolicy Bypass -File .\client\windows\install.ps1
```

### 1.1) 一条命令远程安装

以管理员 PowerShell 运行：

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; $tmp = Join-Path $env:TEMP 'qcby-agent-install.ps1'; Invoke-WebRequest 'https://raw.githubusercontent.com/Qcby/Qcby-Agent/main/client/windows/install.ps1' -OutFile $tmp; PowerShell -ExecutionPolicy Bypass -File $tmp
```

如果你想直接带参数安装：

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; $tmp = Join-Path $env:TEMP 'qcby-agent-install.ps1'; Invoke-WebRequest 'https://raw.githubusercontent.com/Qcby/Qcby-Agent/main/client/windows/install.ps1' -OutFile $tmp; PowerShell -ExecutionPolicy Bypass -File $tmp -ServerHost '你的服务端IP或域名' -Port 8080 -Token '你的Token'
```

### 2) 直接传参安装

```powershell
PowerShell -ExecutionPolicy Bypass -File .\client\windows\install.ps1 `
  -ServerHost "你的服务端IP或域名" `
  -Port 8080 `
  -Token "change-me-token" `
  -AgentId "win-node-01" `
  -IntervalSeconds 30 `
  -Region "HK" `
  -ISP "CMI" `
  -Tags prod,windows
```

### 3) 运行机制说明

Windows 安装脚本会：

- 复制 `agent.ps1` 到系统安装目录
- 生成配置文件与启动脚本
- 注册计划任务为 **SYSTEM 开机自启**
- 以 **PowerShell Hidden Window** 方式后台运行

因此效果是：

- 无窗口后台静默
- 开机自启
- 无 cmd 闪屏弹出后又关闭

### 4) 卸载

```powershell
PowerShell -ExecutionPolicy Bypass -File .\client\windows\install.ps1 -Uninstall
```

---

## 七、后台功能说明

后台地址：

```text
http://你的服务端IP:端口/admin
```

当前支持：

- 登录记忆 30 天
- 退出登录
- 修改 Agent Token
- 修改 Docker 绑定端口
- 修改设备展示名（后台别名）
- 查看设备公网 IP

### 设备改名规则

- 只改后台展示名 `display_name`
- 不修改 `agent_id`
- 不覆盖原始 `hostname`

### Token 修改规则

修改 Token 后：

- 服务端会立即使用新的 Token 校验
- 所有旧客户端如果不更新 Token，将无法继续上报

### 端口修改规则

修改端口后：

- 服务端会记录新的目标端口
- 你仍需在宿主机重新应用 Docker 映射
- 旧客户端因上报地址未同步会失联

---

## 八、客户端参数与上报地址

客户端最终上报地址格式：

```text
http://你的服务端IP:端口/api/v1/report
```

如果你修改了：

- `Agent Token`
- 服务端绑定端口

都需要同步更新客户端配置。

---

## 九、常用 API

### 公开接口

- `GET /api/v1/dashboard`
- `GET /api/v1/agents`
- `GET /api/v1/agents/<agent_id>`
- `GET /api/v1/agents/<agent_id>/metrics`
- `POST /api/v1/report`

### 后台接口（需登录）

- `GET /api/v1/admin/settings`
- `PUT /api/v1/admin/settings`
- `GET /api/v1/admin/agents`
- `PATCH /api/v1/admin/agents/<agent_id>`

---

## 十、建议发布流程

```bash
git pull --rebase origin main
git tag v1.0.0
git push origin main
git push origin v1.0.0

docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t qcby/qcby-agent:latest \
  -t qcby/qcby-agent:v1.0.0 \
  --push \
  ./server
```

---

## 十一、生产使用建议

- 修改默认后台账号密码
- 修改默认 Agent Token
- 定期备份 `monitor.db`
- 使用 HTTPS / 反向代理
- 修改端口前先准备好客户端批量更新方案
