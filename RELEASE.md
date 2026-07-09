# 发布说明

## 当前版本

v0.1.0

## 包含内容

- `install.sh`
  - 单文件 Linux 客户端安装/管理脚本
  - 内置 agent 内容
  - 支持安装、更新、卸载、启动、停止、重启、状态、日志、重配置

## 已实现能力

- 自动创建 `/opt/nodepulse`
- 自动生成 `agent.sh`
- 自动生成 `agent.env`
- 自动注册 `nodepulse-agent.service`
- 自动拼接 `/api/v1/report`
- 自动上报系统信息、资源信息、网络信息、地理信息
- 自动生成系统/地区标签

## 适用命令

```bash
bash <(curl -sSL https://raw.githubusercontent.com/Qcby/QcbyTz/main/install.sh)
```

## 推荐后续版本规划

### v0.2.0
- 增加非交互参数安装模式
- 增加 GitHub Release 下载逻辑
- 增加更丰富的地理中文映射

### v0.3.0
- 增加自动升级
- 增加 shell 自动补全
- 增加客户端自检命令
