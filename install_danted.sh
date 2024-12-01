#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 错误处理函数
error_exit() {
    echo -e "${RED}错误: $1${NC}" >&2
    exit 1
}

# 状态输出函数
info() {
    echo -e "${GREEN}[INFO] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[WARN] $1${NC}"
}

# 检查是否为root用户
[[ $EUID -ne 0 ]] && error_exit "请使用root权限运行此脚本"

# 检查系统环境
[[ ! -f /etc/debian_version ]] && error_exit "此脚本仅支持Debian/Ubuntu系统"

###################
# 安装 Dante Server
###################

# 更新系统软件包
info "正在更新系统..."
apt-get update > /dev/null 2>&1 || error_exit "系统更新失败"

# 安装 Dante Server
info "正在安装 Dante Server..."
apt-get install -y dante-server > /dev/null 2>&1 || error_exit "Dante Server 安装失败"

# 获取实际网卡名称
INTERFACE=$(ip route | grep default | awk '{print $5}')
[[ -z "$INTERFACE" ]] && error_exit "无法获取网卡名称"
info "检测到网卡: ${INTERFACE}"

# 配置 Dante Server
info "正在配置 Dante Server..."

# 备份原有配置文件
if [[ -f "/etc/danted.conf" ]]; then
    mv /etc/danted.conf /etc/danted.conf.bak
    info "已备份原配置文件到 /etc/danted.conf.bak"
fi

# 创建新的配置文件
cat > /etc/danted.conf << EOF
# 日志配置
logoutput: syslog

# 用户权限配置
user.privileged: root
user.unprivileged: nobody

# 全局认证方法配置
clientmethod: none
socksmethod: none

# 网络配置
internal: 0.0.0.0 port=1080    # 监听所有网卡的1080端口
external: ${INTERFACE}         # 自动检测的外部网卡

# 客户端访问规则
client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: error connect disconnect
}

# Socks代理规则
socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: error connect disconnect
}
EOF

# 启动服务
info "正在启动 Dante Server..."
systemctl restart danted
systemctl enable danted > /dev/null 2>&1

# 检查服务状态
if ! systemctl is-active --quiet danted; then
    warn "Dante Server 启动失败"
    warn "查看详细错误信息: journalctl -u danted"
    exit 1
fi

###################
# 安装 Tailscale
###################

info "正在安装 Tailscale..."
if ! curl -fsSL https://tailscale.com/install.sh | sh > /dev/null 2>&1; then
    warn "Tailscale 安装失败，请手动安装"
fi

# 获取公网IP
PUBLIC_IP=$(curl -s ifconfig.me)
[[ -z "$PUBLIC_IP" ]] && warn "无法获取公网IP，请手动检查"

# 输出配置信息
echo -e "\n${GREEN}================================================${NC}"
echo -e "${GREEN}安装完成！${NC}"
echo -e "${GREEN}------------------------------------------------${NC}"
echo -e "${GREEN}Dante Server 配置信息：${NC}"
echo -e "代理服务器地址: ${PUBLIC_IP}"
echo -e "端口: 1080"
echo -e "无需用户名密码"
echo -e "${GREEN}------------------------------------------------${NC}"
echo -e "正在启动 Tailscale...请按提示登录"
sudo tailscale up

# 配置 Tailscale 接受路由
info "配置 Tailscale..."
tailscale set --accept-routes > /dev/null 2>&1

# 最终检查
if systemctl is-active --quiet danted; then
    info "Dante Server 运行正常"
else
    warn "Dante Server 可能未正常运行，请检查"
fi
