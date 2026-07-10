# Qcby-Agent

> 轻量的 Win / Linux 节点监控与探针管理面板

[GitHub](https://github.com/Qcby/Qcby-Agent) · [Docker Hub](https://hub.docker.com/r/qcby/qcby-agent)

Qcby-Agent 提供公开监控首页、`/admin` 管理后台、Windows / Linux 客户端探针，以及 Docker 化服务端部署。适合 VPS、家用主机、混合节点统一监控。

---

## 快速安装

### 1) 服务端

```bash
bash <(curl -sSL https://raw.githubusercontent.com/Qcby/Qcby-Agent/main/install.sh)
```

进入菜单后选择：

```text
1) 管理服务端
```

### 2) Linux 客户端

```bash
bash <(curl -sSL https://raw.githubusercontent.com/Qcby/Qcby-Agent/main/install.sh)
```

进入菜单后选择：

```text
2) 管理 Linux 客户端
```

### 3) Windows 客户端

以管理员 PowerShell 运行：

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; $tmp = Join-Path $env:TEMP 'qcby-agent-install.ps1'; Invoke-WebRequest 'https://raw.githubusercontent.com/Qcby/Qcby-Agent/main/client/windows/install.ps1' -OutFile $tmp; PowerShell -ExecutionPolicy Bypass -File $tmp
```

---

## 探针功能

### 节点采集

- CPU、内存、磁盘、进程数
- 网络上下行速率
- Docker 运行状态与容器数量
- 在线时长统计

### 节点识别

- 公网 IP
- 地区 / 城市 / 运营商
- 自定义标签
- Windows / Linux 混合接入

### 运行方式

- Linux 后台常驻
- Windows 静默后台运行
- 开机自启
- 支持安装、升级、卸载、重配

---

## 后台功能

- 公开首页总览
- `/admin` 登录后台
- 修改 Agent Token
- 修改 Docker 绑定端口
- 修改设备展示名
- 查看设备公网 IP

---

## 页面截图

> 这里预留给你粘贴后台页面 / 首页截图

```md
![Qcby-Agent 页面截图](https://github.com/user-attachments/assets/dc12cded-9699-497a-9db8-5e37485ac6f1)
![后台管理](https://github.com/user-attachments/assets/a4d82dea-6831-4c7b-861e-e9c653d779d8)
```


---

## 项目地址

- GitHub: [Qcby/Qcby-Agent](https://github.com/Qcby/Qcby-Agent)
- Docker Hub: [qcby/qcby-agent](https://hub.docker.com/r/qcby/qcby-agent)
