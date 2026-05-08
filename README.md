# 小米路由器 BE6500 SSH 开启工具

通过小米路由器的命令注入漏洞开启 SSH，支持 BE6500 型号。

## 使用方法

```bash
chmod +x miwifi-ssh.sh
./miwifi-ssh.sh
```

脚本会依次询问：

1. **STOK** — 登录小米路由器管理后台后，URL 中 `stok=` 后面的部分
2. **路由器 IP** — 默认 `192.168.31.1`
3. **SN** — 路由器底部的序列号（如 `57941/F4U711396`）

然后自动执行开启 SSH 的四个步骤，并计算 root 密码。

## 依赖

- `curl`
- `openssl`
- `ssh`（可选，用于自动连接）

均为 macOS 和常见 Linux 发行版自带工具。

## 原理

1. 通过小米路由器 `/api/xqsystem/start_binding` 接口的命令注入漏洞，执行以下操作：
   - 启用 SSH（`nvram set ssh_en=1`）
   - 提交 NVRAM 配置
   - 修改 dropbear 启动脚本
   - 启动 dropbear
2. 根据 SN 序列号计算 root 密码（MD5 哈希算法）

## 许可证

MIT License
