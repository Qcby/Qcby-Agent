# Qcby-Agent Release

## 发布前检查

1. 确认 `README.md` 已同步最新 Git、Docker、多架构与安装说明
2. 确认 `install.sh`、`scripts/install-server.sh`、`scripts/install-linux-client.sh` 可用
3. 确认 `client/windows/install.ps1` 可正常注册计划任务并静默运行
4. 确认后台端口修改提示、Token 修改提示、公网 IP 显示都正常

## Git 发布

```bash
git status
git add .
git commit -m "release: prepare v1.0.0"
git tag v1.0.0
git push origin main
git push origin v1.0.0
```

## Docker 多架构发布

```bash
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t qcby/qcby-agent:latest \
  -t qcby/qcby-agent:v1.0.0 \
  --push \
  ./server
```

## 部署后核验

1. 首页可访问
2. `/admin` 可登录
3. 设备列表显示公网 IP
4. 修改设备别名后首页同步显示
5. 修改 Token 后旧客户端 401
6. 修改绑定端口后提示用户执行 `manage-server.sh apply`
