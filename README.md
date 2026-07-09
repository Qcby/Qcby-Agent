# QcbyTz / NodePulse Linux 客户端一键安装脚本

这是一个面向 **NodePulse 探针客户端** 的 Linux 一键安装 / 管理脚本仓库。  
适合直接放到 GitHub / Gitee / 自建静态站点，通过：

```bash
bash <(curl -sSL https://raw.githubusercontent.com/Qcby/QcbyTz/main/install.sh)
```

一键进入安装和管理菜单。

---

## 功能特性

- 一键安装 NodePulse Linux 客户端
- 自动注册为 `systemd` 服务
- 支持升级 / 更新
- 支持卸载
- 支持启动 / 停止 / 重启
- 支持查看状态 / 查看日志
- 支持重新配置服务端地址、Token、标签、上报间隔
- 自动拼接 `/api/v1/report`
- 自动识别：
  - 公网 IP
  - 国家 / 城市 / ISP
  - Linux 发行版标签（如 `ubuntu22`、`debian12`、`centos7`）
- 自动生成标签：
  - `linux`
  - `ubuntu22` / `debian12` / `centos7`
  - `cn` / `kr` / `sg`
  - 地理位置标签

---

## 适用场景

适合给以下类型机器快速接入 NodePulse 服务端：

- Debian / Ubuntu
- CentOS / Rocky / AlmaLinux
- 云服务器 / VPS
- 家用 Linux 主机
- 宝塔所在 Linux 服务器

---

## 使用方式

### 1. 直接运行菜单版

```bash
bash <(curl -sSL https://raw.githubusercontent.com/Qcby/QcbyTz/main/install.sh)
```

运行后会出现菜单：

```text
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
```

---

### 2. 直接执行某个动作

#### 安装

```bash
bash <(curl -sSL https://raw.githubusercontent.com/Qcby/QcbyTz/main/install.sh) install
```

#### 更新

```bash
bash <(curl -sSL https://raw.githubusercontent.com/Qcby/QcbyTz/main/install.sh) update
```

#### 卸载

```bash
bash <(curl -sSL https://raw.githubusercontent.com/Qcby/QcbyTz/main/install.sh) uninstall
```

#### 启动 / 停止 / 重启

```bash
bash <(curl -sSL https://raw.githubusercontent.com/Qcby/QcbyTz/main/install.sh) start
bash <(curl -sSL https://raw.githubusercontent.com/Qcby/QcbyTz/main/install.sh) stop
bash <(curl -sSL https://raw.githubusercontent.com/Qcby/QcbyTz/main/install.sh) restart
```

#### 查看状态 / 日志

```bash
bash <(curl -sSL https://raw.githubusercontent.com/Qcby/QcbyTz/main/install.sh) status
bash <(curl -sSL https://raw.githubusercontent.com/Qcby/QcbyTz/main/install.sh) logs
```

#### 重新配置

```bash
bash <(curl -sSL https://raw.githubusercontent.com/Qcby/QcbyTz/main/install.sh) reconfig
```

---

## 安装时需要提供的信息

脚本会交互询问：

- 服务端 IP 或域名
- 服务端端口
- Token
- 上报间隔秒数
- 地区覆盖（可留空）
- ISP 覆盖（可留空）
- 额外标签

例如：

```text
服务端地址: 146.56.140.150
端口: 8080
Token: change-me-token
```

脚本会自动拼接成：

```text
http://146.56.140.150:8080/api/v1/report
```

---

## 安装后的目录结构

默认安装到：

```text
/opt/nodepulse
```

包含：

- `/opt/nodepulse/agent.sh`：客户端主脚本
- `/opt/nodepulse/agent.env`：配置文件
- `/etc/systemd/system/nodepulse-agent.service`：systemd 服务

---

## 常用命令

### 查看状态

```bash
systemctl status nodepulse-agent
```

### 查看日志

```bash
journalctl -u nodepulse-agent -f
```

### 重启客户端

```bash
systemctl restart nodepulse-agent
```

---

## 仓库使用介绍

这个仓库的定位不是完整服务端，而是：

### 一个可以被任何 Linux 主机远程执行的一键安装入口

你可以把它理解为：

- 像 `code-server` / `vscode` 那类安装脚本一样
- 用户只需要 `curl | bash`
- 不需要提前手动上传 `agent.sh`
- 不需要手动写 `systemd`
- 不需要手动拼接 `/api/v1/report`

### 适合搭配 NodePulse 服务端使用

推荐流程：

1. 先部署 NodePulse 服务端
2. 再通过本仓库的一键安装脚本接入多台 Linux 客户端
3. 统一在服务端面板中查看节点状态、在线时间、系统标签、地理位置等信息

---

## 默认值

脚本默认：

- Token：`change-me-token`
- 上报间隔：`15` 秒

但安装时都可以手动改。

---

## 注意事项

- 请确保服务端端口可达
- 请确保 Linux 主机能访问外网（用于 IP 地理识别）
- 推荐使用 root 运行，或具备 sudo 权限的用户运行
- 如果只想本机调试，也可以把服务端填为：

```text
127.0.0.1:8080
```

---

## 后续可扩展方向

- 自动更新 agent
- 多环境模板配置
- IPv6 优先 / IPv4 优先切换
- 更丰富的地区中文映射
- 与 GitHub Release / Gitee Release 联动

---

## 仓库地址

- GitHub: [Qcby/QcbyTz](https://github.com/Qcby/QcbyTz)
