# Qcby-Agent

Qcby-Agent 是一个轻量的 Win / Linux 节点监控项目，提供公开监控首页、`/admin` 管理后台、Windows / Linux 客户端探针，以及 Docker 化服务端部署。

---

## 一行命令安装

### 服务端

```bash
bash <(curl -sSL https://raw.githubusercontent.com/Qcby/Qcby-Agent/main/install.sh)
```

进入菜单后选择：

```text
1) 管理服务端
```

### Linux 客户端

```bash
bash <(curl -sSL https://raw.githubusercontent.com/Qcby/Qcby-Agent/main/install.sh)
```

进入菜单后选择：

```text
2) 管理 Linux 客户端
```

### Windows 客户端

以管理员 PowerShell 运行：

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; $tmp = Join-Path $env:TEMP 'qcby-agent-install.ps1'; Invoke-WebRequest 'https://raw.githubusercontent.com/Qcby/Qcby-Agent/main/client/windows/install.ps1' -OutFile $tmp; PowerShell -ExecutionPolicy Bypass -File $tmp
```

---

## 探针功能

Qcby-Agent 探针支持：

- 采集 CPU、内存、磁盘、进程数
- 采集网络上下行速率
- 采集 Docker 运行状态与容器数量
- 采集公网 IP、地区、运营商信息
- 上报在线时长
- 支持 Linux / Windows
- 支持后台静默运行与开机自启

---

## 管理后台功能

后台支持：

- 登录记忆与退出登录
- 修改 Agent Token
- 修改 Docker 绑定端口
- 修改设备展示名
- 查看设备公网 IP
- 节点资源状态总览

---

## 页面截图预留

> 在这里粘贴你的页面截图

```md
![Qcby-Agent 页面截图](在这里替换成你的图片链接)
```

---

## 项目地址

- GitHub: [Qcby/Qcby-Agent](https://github.com/Qcby/Qcby-Agent)
- Docker Hub: [qcby/qcby-agent](https://hub.docker.com/r/qcby/qcby-agent)
