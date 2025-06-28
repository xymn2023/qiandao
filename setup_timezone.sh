#!/bin/bash

# ================== 时区设置脚本 ==================
# 一键设置服务器时区为 Asia/Shanghai
# ====================================================

echo "🕐 正在设置服务器时区为 Asia/Shanghai..."

# 检查是否为root用户
if [ "$(id -u)" -ne 0 ]; then
    echo "❌ 此脚本需要root权限运行"
    echo "请使用: sudo bash setup_timezone.sh"
    exit 1
fi

# 检测系统类型并设置时区
if [ -f /etc/debian_version ]; then
    # Debian/Ubuntu 系统
    echo "📦 检测到 Debian/Ubuntu 系统"
    
    # 安装tzdata包（如果未安装）
    if ! dpkg -l | grep -q "tzdata"; then
        echo "📦 正在安装 tzdata..."
        apt update
        apt install -y tzdata
    fi
    
    # 设置时区
    echo "🕐 正在设置时区为 Asia/Shanghai..."
    timedatectl set-timezone Asia/Shanghai
    
elif [ -f /etc/redhat-release ]; then
    # CentOS/RHEL/Fedora 系统
    echo "📦 检测到 CentOS/RHEL/Fedora 系统"
    
    # 安装tzdata包（如果未安装）
    if ! rpm -qa | grep -q "tzdata"; then
        echo "📦 正在安装 tzdata..."
        if command -v yum &>/dev/null; then
            yum install -y tzdata
        elif command -v dnf &>/dev/null; then
            dnf install -y tzdata
        fi
    fi
    
    # 设置时区
    echo "🕐 正在设置时区为 Asia/Shanghai..."
    timedatectl set-timezone Asia/Shanghai
    
else
    # 其他系统，尝试通用方法
    echo "⚠️ 无法自动检测系统类型，尝试通用方法..."
    
    # 创建时区链接
    if [ -d /usr/share/zoneinfo ]; then
        ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
        echo "Asia/Shanghai" > /etc/timezone
        echo "✅ 时区链接已创建"
    else
        echo "❌ 无法找到时区信息文件"
        exit 1
    fi
fi

# 验证时区设置
echo "🔍 验证时区设置..."
current_timezone=$(timedatectl show --property=Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null || echo "unknown")

if [ "$current_timezone" = "Asia/Shanghai" ]; then
    echo "✅ 时区设置成功: $current_timezone"
else
    echo "⚠️ 时区可能未正确设置，当前时区: $current_timezone"
fi

# 显示当前时间
echo "🕐 当前时间信息:"
date
echo "UTC时间: $(date -u)"

# 设置NTP同步（如果可用）
if command -v systemctl &>/dev/null; then
    echo "🔄 配置NTP时间同步..."
    
    # 启用并启动systemd-timesyncd
    if systemctl list-unit-files | grep -q "systemd-timesyncd"; then
        systemctl enable systemd-timesyncd
        systemctl start systemd-timesyncd
        echo "✅ systemd-timesyncd 已启用"
    fi
    
    # 或者启用chronyd（CentOS/RHEL）
    if systemctl list-unit-files | grep -q "chronyd"; then
        systemctl enable chronyd
        systemctl start chronyd
        echo "✅ chronyd 已启用"
    fi
fi

echo ""
echo "🎉 时区设置完成！"
echo "📝 注意事项："
echo "1. 重启机器人以确保时区设置生效"
echo "2. 定时任务将按照上海时间执行"
echo "3. 建议定期检查时间同步状态"
echo ""
echo "🔄 重启机器人命令："
echo "cd /opt/qiandao && bash start.sh" 