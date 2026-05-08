#!/bin/sh
set -e

echo "============================================"
echo "  小米路由器 BE6500 SSH 开启工具"
echo "  Xiaomi BE6500 SSH Enabler"
echo "============================================"
echo ""

# --- Gather inputs ---

printf "请输入路由器的 STOK (stok= 后面的部分): "
read -r STOK

printf "请输入路由器 IP 地址 (默认: 192.168.31.1): "
read -r ROUTER_IP
ROUTER_IP="${ROUTER_IP:-192.168.31.1}"

printf "请输入路由器 SN (序列号, 如 57941/F4U711396): "
read -r SN

echo ""
echo "--- 正在开启 SSH ---"

# --- Build base URL ---
BASE_URL="http://${ROUTER_IP}/cgi-bin/luci/;stok=${STOK}/api/xqsystem/start_binding"

# --- Step 1: enable ssh ---
echo "[1/4] 启用 SSH (nvram set ssh_en=1)..."
RESP=$(curl -s -X POST "$BASE_URL" -d "uid=1234&key=1234'%0Anvram%20set%20ssh_en%3D1'")
if echo "$RESP" | grep -q '"code":0'; then
    echo "  ✓ 成功"
else
    echo "  ✗ 失败: $RESP"
fi

# --- Step 2: commit nvram ---
echo "[2/4] 提交 NVRAM (nvram commit)..."
RESP=$(curl -s -X POST "$BASE_URL" -d "uid=1234&key=1234'%0Anvram%20commit'")
if echo "$RESP" | grep -q '"code":0'; then
    echo "  ✓ 成功"
else
    echo "  ✗ 失败: $RESP"
fi

# --- Step 3: modify dropbear to debug channel ---
echo "[3/4] 修改 dropbear 启动脚本..."
RESP=$(curl -s -X POST "$BASE_URL" -d "uid=1234&key=1234'%0Ased%20-i%20's%2Fchannel%3D.*%2Fchannel%3D%22debug%22%2Fg'%20%2Fetc%2Finit.d%2Fdropbear'")
if echo "$RESP" | grep -q '"code":0'; then
    echo "  ✓ 成功"
else
    echo "  ✗ 失败: $RESP"
fi

# --- Step 4: start dropbear ---
echo "[4/4] 启动 dropbear SSH 服务..."
RESP=$(curl -s -X POST "$BASE_URL" -d "uid=1234&key=1234'%0A%2Fetc%2Finit.d%2Fdropbear%20start'")
if echo "$RESP" | grep -q '"code":0'; then
    echo "  ✓ 成功"
else
    echo "  ✗ 失败: $RESP"
fi

# --- Calculate SSH password from SN ---
echo ""
echo "--- 正在计算 root 密码 ---"

if echo "$SN" | grep -q '/'; then
    SALT="6d2df50a-250f-4a30-a5e6-d44fb0960aa0"
else
    SALT="A2E371B0-B34B-48A5-8C40-A7133F3B5D88"
fi

PASSWORD=$(printf "%s" "${SN}${SALT}" | openssl md5 | awk '{print $2}' | cut -c1-8)

echo ""
echo "============================================"
echo "  SSH 已开启!"
echo "============================================"
echo "  路由器 IP : ${ROUTER_IP}"
echo "  用户名    : root"
echo "  密码      : ${PASSWORD}"
echo "============================================"
echo ""

# --- Offer SSH connection ---
printf "是否现在通过 SSH 连接路由器? [y/N]: "
read -r CONNECT
case "$CONNECT" in
    [Yy]|[Yy][Ee][Ss])
        echo "正在连接..."
        ssh -o HostKeyAlgorithms=+ssh-rsa "root@${ROUTER_IP}"
        ;;
    *)
        echo "你可以稍后手动连接:"
        echo "  ssh -o HostKeyAlgorithms=+ssh-rsa root@${ROUTER_IP}"
        echo "  密码: ${PASSWORD}"
        ;;
esac
