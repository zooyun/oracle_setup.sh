#!/bin/bash

# =================================================================
# 脚本名称: oracle_vps_setup.sh
# 功能: 开启密码登录, 切换 UFW 防火墙, 交互式修改 SSH 端口
# 适用系统: Ubuntu 24.04 (Oracle Cloud ARM/AMD)
# =================================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

echo -e "${GREEN}>>> 开始甲骨文云 VPS 初始化程序...${NC}"

# 1. 交互式询问 SSH 端口
DEFAULT_PORT=1022
read -p "请输入你想设置的 SSH 端口 (默认: $DEFAULT_PORT): " CUSTOM_PORT
SSH_PORT=${CUSTOM_PORT:-$DEFAULT_PORT}

# 端口合法性简单校验
if [[ ! "$SSH_PORT" =~ ^[0-9]+$ ]] || [ "$SSH_PORT" -gt 65535 ] || [ "$SSH_PORT" -lt 1 ]; then
    echo -e "${RED}错误: 无效的端口号，将使用默认端口 $DEFAULT_PORT${NC}"
    SSH_PORT=$DEFAULT_PORT
fi

echo -e "${GREEN}>>> 将使用端口: $SSH_PORT${NC}"

# 2. 设置用户密码
echo ">>> 正在设置 ubuntu 用户密码..."
sudo passwd ubuntu

# 3. 修改 SSH 配置开启密码登录
echo ">>> 正在配置 SSH 允许密码登录..."
sudo sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/g' /etc/ssh/sshd_config
sudo sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/g' /etc/ssh/sshd_config
sudo sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/g' /etc/ssh/sshd_config

# 4. 消除甲骨文镜像配置覆盖
if [ -f /etc/ssh/sshd_config.d/60-cloudimg-settings.conf ]; then
    sudo sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/g' /etc/ssh/sshd_config.d/60-cloudimg-settings.conf
fi

# 5. 修改 SSH 端口
echo ">>> 正在修改 SSH 端口为 $SSH_PORT..."
sudo sed -i "s/#Port 22/Port $SSH_PORT/g" /etc/ssh/sshd_config
sudo sed -i "s/Port 22/Port $SSH_PORT/g" /etc/ssh/sshd_config
# 针对已经修改过非22端口的情况再次覆盖
sudo sed -i "s/^Port [0-9]*/Port $SSH_PORT/g" /etc/ssh/sshd_config

# 6. 清理旧防火墙并安装 UFW
echo ">>> 正在清理旧防火墙并安装 UFW..."
sudo iptables -P INPUT ACCEPT
sudo iptables -P FORWARD ACCEPT
sudo iptables -P OUTPUT ACCEPT
sudo iptables -F
sudo apt-get purge iptables-persistent -y
sudo apt update && sudo apt install ufw -y

# 7. 配置 UFW 规则
echo ">>> 正在配置 UFW 规则..."
sudo ufw allow "$SSH_PORT"/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# 8. 切换 SSH 服务模式 (针对 Ubuntu 24.04 优化)
echo ">>> 正在重置 SSH 服务模式..."
sudo systemctl stop ssh.socket
sudo systemctl disable ssh.socket
sudo systemctl enable --now ssh.service

# 9. 启用 UFW
echo "y" | sudo ufw enable

echo -e "${GREEN}===============================================================${NC}"
echo -e "${GREEN}脚本执行完毕！${NC}"
echo "1. 请确保甲骨文云后台【入站规则】已设为【所有协议全开放】"
echo -e "2. 请使用新端口连接: ${RED}ssh ubuntu@你的IP -p $SSH_PORT${NC}"
echo -e "${GREEN}===============================================================${NC}"
