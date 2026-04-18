#!/bin/bash

# --- 基础默认配置 ---
DEFAULT_START_PORT=20000
DEFAULT_WS_PATH="/ws"
DEFAULT_UUID=$(cat /proc/sys/kernel/random/uuid)

# 获取服务器所有 IP
IP_ADDRESSES=($(hostname -I))

install_xray() {
    echo "正在安装 Xray..."
    apt-get update && apt-get install unzip wget -y || yum install unzip wget -y
    wget https://github.com/XTLS/Xray-core/releases/download/v1.8.3/Xray-linux-64.zip
    unzip -o Xray-linux-64.zip
    mv xray /usr/local/bin/xrayL
    chmod +x /usr/local/bin/xrayL
    
    cat <<EOF >/etc/systemd/system/xrayL.service
[Unit]
Description=XrayL Service
After=network.target

[Service]
ExecStart=/usr/local/bin/xrayL -c /etc/xrayL/config.toml
Restart=on-failure
User=nobody
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable xrayL.service
    systemctl start xrayL.service
}

config_xray() {
    config_type=$1
    mkdir -p /etc/xrayL

    # 使用 /dev/tty 确保在 curl 管道执行时也能接收键盘输入
    echo "--- 配置参数录入 ---"
    read -p "请输入起始端口 (默认 $DEFAULT_START_PORT): " START_PORT < /dev/tty
    START_PORT=${START_PORT:-$DEFAULT_START_PORT}

    if [ "$config_type" == "socks" ]; then
        read -p "请输入 SOCKS 用户名: " SOCKS_USERNAME < /dev/tty
        read -p "请输入 SOCKS 密码: " SOCKS_PASSWORD < /dev/tty
        # 如果用户没输入，给个默认值防止配置报错
        SOCKS_USERNAME=${SOCKS_USERNAME:-"admin"}
        SOCKS_PASSWORD=${SOCKS_PASSWORD:-"pass123"}
    elif [ "$config_type" == "vmess" ]; then
        read -p "请输入 UUID (回车随机生成): " UUID < /dev/tty
        UUID=${UUID:-$DEFAULT_UUID}
        read -p "请输入 WebSocket 路径 (默认 $DEFAULT_WS_PATH): " WS_PATH < /dev/tty
        WS_PATH=${WS_PATH:-$DEFAULT_WS_PATH}
    fi

    config_content=""
    for ((i = 0; i < ${#IP_ADDRESSES[@]}; i++)); do
        config_content+="[[inbounds]]\n"
        config_content+="port = $((START_PORT + i))\n"
        config_content+="protocol = \"$config_type\"\n"
        config_content+="tag = \"tag_$((i + 1))\"\n"
        config_content+="[inbounds.settings]\n"
        if [ "$config_type" == "socks" ]; then
            config_content+="auth = \"password\"\n"
            config_content+="udp = true\n"
            config_content+="ip = \"${IP_ADDRESSES[i]}\"\n"
            config_content+="[[inbounds.settings.accounts]]\n"
            config_content+="user = \"$SOCKS_USERNAME\"\n"
            config_content+="pass = \"$SOCKS_PASSWORD\"\n"
        elif [ "$config_type" == "vmess" ]; then
            config_content+="[[inbounds.settings.clients]]\n"
            config_content+="id = \"$UUID\"\n"
            config_content+="[inbounds.streamSettings]\n"
            config_content+="network = \"ws\"\n"
            config_content+="[inbounds.streamSettings.wsSettings]\n"
            config_content+="path = \"$WS_PATH\"\n\n"
        fi
        config_content+="[[outbounds]]\n"
        config_content+="sendThrough = \"${IP_ADDRESSES[i]}\"\n"
        config_content+="protocol = \"freedom\"\n"
        config_content+="tag = \"tag_$((i + 1))\"\n\n"
        config_content+="[[routing.rules]]\n"
        config_content+="type = \"field\"\n"
        config_content+="inboundTag = \"tag_$((i + 1))\"\n"
        config_content+="outboundTag = \"tag_$((i + 1))\"\n\n\n"
    done

    echo -e "$config_content" >/etc/xrayL/config.toml
    systemctl restart xrayL.service
    
    echo "-------------------------------------------"
    echo "生成 $config_type 配置完成！"
    echo "地址范围: $START_PORT 到 $(($START_PORT + ${#IP_ADDRESSES[@]} - 1))"
    [ "$config_type" == "socks" ] && echo "账号: $SOCKS_USERNAME | 密码: $SOCKS_PASSWORD"
    [ "$config_type" == "vmess" ] && echo "UUID: $UUID | Path: $WS_PATH"
    echo "-------------------------------------------"
}

main() {
    # 检查是否安装
    [ -x "$(command -v xrayL)" ] || install_xray
    
    # 选择类型
    if [ $# -eq 1 ]; then
        config_type="$1"
    else
        echo "请选择节点类型:"
        echo "1) socks"
        echo "2) vmess"
        read -p "请输入数字或类型名称 (默认 socks): " choice < /dev/tty
        case $choice in
            2|vmess) config_type="vmess" ;;
            *) config_type="socks" ;;
        esac
    fi

    config_xray "$config_type"
}

main "$@"
