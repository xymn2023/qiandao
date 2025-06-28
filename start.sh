#!/bin/bash
set -e

# ================== 服务管理器脚本 ==================
#
#   用作安装器: bash <(curl -fsSL https://raw.githubusercontent.com/xymn2023/qiandao/main/start.sh)
#   用作管理器: qiandao-bot (或在项目目录中 bash start.sh)
#
# ====================================================

REPO_URL="https://github.com/xymn2023/qiandao.git"
INSTALL_PATH_GLOBAL="/opt/qiandao"
INSTALL_PATH_LOCAL="$HOME/qiandao"
ALIAS_CMD="alias qiandao-bot='bash $INSTALL_PATH_LOCAL/start.sh'"

# 检查并安装虚拟环境支持
check_and_install_venv() {
    echo "🔍 检查虚拟环境支持..."
    
    # 检测系统类型
    if [ -f /etc/debian_version ]; then
        # Debian/Ubuntu 系统
        if ! dpkg -l | grep -q "python3-venv"; then
            echo "📦 检测到 Debian/Ubuntu 系统，正在安装 python3-venv..."
            if command -v apt &>/dev/null; then
                apt update
                apt install -y python3-venv
                echo "✅ python3-venv 安装完成"
            else
                echo "❌ 无法安装 python3-venv，请手动运行: sudo apt install python3-venv"
                exit 1
            fi
        else
            echo "✅ python3-venv 已安装"
        fi
    elif [ -f /etc/redhat-release ]; then
        # CentOS/RHEL/Fedora 系统
        if ! rpm -qa | grep -q "python3-venv"; then
            echo "📦 检测到 CentOS/RHEL/Fedora 系统，正在安装 python3-venv..."
            if command -v yum &>/dev/null; then
                yum install -y python3-venv
                echo "✅ python3-venv 安装完成"
            elif command -v dnf &>/dev/null; then
                dnf install -y python3-venv
                echo "✅ python3-venv 安装完成"
            else
                echo "❌ 无法安装 python3-venv，请手动运行: sudo yum install python3-venv 或 sudo dnf install python3-venv"
                exit 1
            fi
        else
            echo "✅ python3-venv 已安装"
        fi
    else
        # 其他系统，尝试检测 venv 模块
        if ! python3 -c "import venv" 2>/dev/null; then
            echo "⚠️ 无法自动检测系统类型，请手动安装 python3-venv"
            echo "Debian/Ubuntu: sudo apt install python3-venv"
            echo "CentOS/RHEL: sudo yum install python3-venv"
            echo "Fedora: sudo dnf install python3-venv"
            exit 1
        else
            echo "✅ 虚拟环境支持正常"
        fi
    fi
}

# 设置时区为 Asia/Shanghai
setup_timezone() {
    echo "🕐 检查并设置时区..."
    
    # 检查当前时区
    current_timezone=$(timedatectl show --property=Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null || echo "unknown")
    
    if [ "$current_timezone" = "Asia/Shanghai" ]; then
        echo "✅ 时区已正确设置为 Asia/Shanghai"
        return 0
    fi
    
    echo "⚠️ 当前时区: $current_timezone，正在设置为 Asia/Shanghai..."
    
    # 检查是否为root用户
    if [ "$(id -u)" -eq 0 ]; then
        # 设置时区
        if command -v timedatectl &>/dev/null; then
            timedatectl set-timezone Asia/Shanghai
            echo "✅ 时区设置完成"
        else
            # 备用方法
            if [ -d /usr/share/zoneinfo ]; then
                ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
                echo "Asia/Shanghai" > /etc/timezone
                echo "✅ 时区链接已创建"
            else
                echo "❌ 无法设置时区，请手动设置"
                return 1
            fi
        fi
        
        # 验证设置
        new_timezone=$(timedatectl show --property=Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null || echo "unknown")
        if [ "$new_timezone" = "Asia/Shanghai" ]; then
            echo "✅ 时区设置成功: $new_timezone"
            echo "🕐 当前时间: $(date)"
        else
            echo "⚠️ 时区设置可能未生效，当前时区: $new_timezone"
        fi
    else
        echo "⚠️ 非root用户，无法设置系统时区"
        echo "请手动运行: sudo timedatectl set-timezone Asia/Shanghai"
        echo "或者使用脚本: sudo bash setup_timezone.sh"
    fi
}

# 检查依赖
for cmd in git python3 curl; do
    if ! command -v $cmd &>/dev/null; then
        echo "缺少依赖: $cmd，请先安装！"
        exit 1
    fi
done

# 检查并安装虚拟环境支持
check_and_install_venv

# 智能判断pip命令
get_pip_command() {
    if command -v pip3 &>/dev/null; then
        echo "pip3"
    elif command -v pip &>/dev/null; then
        echo "pip"
    else
        echo "python3 -m pip"
    fi
}

# 获取pip命令
PIP_CMD=$(get_pip_command)
echo "🔧 使用包管理器: $PIP_CMD"

# 判断是否root
if [ "$(id -u)" -eq 0 ]; then
    INSTALL_PATH="$INSTALL_PATH_GLOBAL"
    SHORTCUT="/usr/local/bin/qiandao-bot"
    IS_ROOT=1
else
    INSTALL_PATH="$INSTALL_PATH_LOCAL"
    SHORTCUT=""
    IS_ROOT=0
fi

# 只要未安装，立即自举
if [ ! -d "$INSTALL_PATH" ]; then
    echo "未检测到机器人，正在自动下载安装..."
    rm -rf "$INSTALL_PATH"
    git clone "$REPO_URL" "$INSTALL_PATH"
    cd "$INSTALL_PATH"
    
    # 创建虚拟环境
    echo "🔧 正在创建虚拟环境..."
    if python3 -m venv .venv; then
        echo "✅ 虚拟环境创建成功"
    else
        echo "❌ 虚拟环境创建失败，请检查 python3-venv 是否正确安装"
        exit 1
    fi
    
    echo "📦 正在安装依赖包..."
    ./.venv/bin/python -m pip install --upgrade pip
    ./.venv/bin/python -m pip install -r requirements.txt
    ./.venv/bin/python -m pip install "python-telegram-bot[job-queue]"
    echo "✅ 依赖安装完成"
    read -p "请输入你的 Telegram Bot Token: " TOKEN < /dev/tty
    read -p "请输入你的 Telegram Chat ID (管理员ID): " CHAT_ID < /dev/tty
    cat > .env <<EOF
TELEGRAM_BOT_TOKEN=$TOKEN
TELEGRAM_CHAT_ID=$CHAT_ID
EOF
    chmod +x start.sh
    if [ "$IS_ROOT" = "1" ]; then
        ln -sf "$INSTALL_PATH/start.sh" "$SHORTCUT"
        chmod +x "$SHORTCUT"
        echo "✅ 全局命令已注册：qiandao-bot"
    else
        if ! grep -q "alias qiandao-bot=" ~/.bashrc; then
            echo "$ALIAS_CMD" >> ~/.bashrc
            echo "alias 已添加到 ~/.bashrc，请运行 source ~/.bashrc 后使用 qiandao-bot"
        fi
    fi
    echo "✅ 安装完成！"
    exec bash "$INSTALL_PATH/start.sh"
    exit 0
fi

# --- 全局变量 ---
# 修正 SCRIPT_DIR 兼容 bash <(curl ...) 场景
if [[ -f "$INSTALL_PATH/start.sh" ]]; then
    SCRIPT_DIR="$INSTALL_PATH"
else
    SCRIPT_REAL_PATH=$(readlink -f "${BASH_SOURCE[0]}")
    SCRIPT_DIR=$(dirname "$SCRIPT_REAL_PATH")
fi
PYTHON_IN_VENV="$SCRIPT_DIR/.venv/bin/python"

# 检查虚拟环境是否存在
if [ ! -f "$PYTHON_IN_VENV" ]; then
    echo "⚠️ 检测到虚拟环境不存在，正在重新创建..."
    cd "$SCRIPT_DIR"
    if python3 -m venv .venv; then
        echo "✅ 虚拟环境重新创建成功"
        echo "📦 正在重新安装依赖包..."
        "$PYTHON_IN_VENV" -m pip install --upgrade pip
        "$PYTHON_IN_VENV" -m pip install -r requirements.txt
        "$PYTHON_IN_VENV" -m pip install "python-telegram-bot[job-queue]"
        echo "✅ 依赖重新安装完成"
    else
        echo "❌ 虚拟环境创建失败，请检查 python3-venv 是否正确安装"
        exit 1
    fi
fi

# --- 函数定义区 ---
find_bot_pid() {
    pgrep -f "$PYTHON_IN_VENV -u bot.py" || true
}

# 检查和修复虚拟环境
check_and_fix_venv() {
    echo "--- 检查/修复虚拟环境 ---"
    cd "$SCRIPT_DIR" || exit
    
    if [ ! -f "$PYTHON_IN_VENV" ]; then
        echo "⚠️ 检测到虚拟环境不存在，正在重新创建..."
        if python3 -m venv .venv; then
            echo "✅ 虚拟环境重新创建成功"
            echo "📦 正在重新安装依赖包..."
            "$PYTHON_IN_VENV" -m pip install --upgrade pip
            "$PYTHON_IN_VENV" -m pip install -r requirements.txt
            "$PYTHON_IN_VENV" -m pip install "python-telegram-bot[job-queue]"
            echo "✅ 依赖重新安装完成"
        else
            echo "❌ 虚拟环境创建失败，请检查 python3-venv 是否正确安装"
            return 1
        fi
    else
        echo "✅ 虚拟环境存在"
        
        # 测试虚拟环境是否正常工作
        if ! "$PYTHON_IN_VENV" -c "import sys; print('Python version:', sys.version)" 2>/dev/null; then
            echo "⚠️ 虚拟环境可能损坏，正在重新创建..."
            rm -rf .venv
            if python3 -m venv .venv; then
                echo "✅ 虚拟环境重新创建成功"
                echo "📦 正在重新安装依赖包..."
                "$PYTHON_IN_VENV" -m pip install --upgrade pip
                "$PYTHON_IN_VENV" -m pip install -r requirements.txt
                "$PYTHON_IN_VENV" -m pip install "python-telegram-bot[job-queue]"
                echo "✅ 依赖重新安装完成"
            else
                echo "❌ 虚拟环境创建失败"
                return 1
            fi
        else
            echo "✅ 虚拟环境工作正常"
        fi
    fi
    
    echo "📊 虚拟环境信息："
    "$PYTHON_IN_VENV" -c "import sys; print('Python 路径:', sys.executable); print('Python 版本:', sys.version)"
    echo ""
}

perform_update() {
    echo "--- 检查更新 ---"
    cd "$SCRIPT_DIR" || exit
    git config --global --add safe.directory "$SCRIPT_DIR"
    echo "正在暂存本地更改以避免冲突..."
    git stash push -m "autostash_by_script" >/dev/null
    echo "正在从 GitHub 拉取最新版本..."
    if git pull origin main; then
        echo "正在恢复本地更改..."
        if ! git stash pop >/dev/null 2>&1; then
            echo "警告：自动恢复本地更改时可能存在冲突。请手动检查并解决：git status"
        fi
        echo "✅ 更新完成。正在重新安装依赖..."
        echo "📦 正在更新依赖包..."
        "$PYTHON_IN_VENV" -m pip install --upgrade pip
        "$PYTHON_IN_VENV" -m pip install -r requirements.txt
        "$PYTHON_IN_VENV" -m pip install "python-telegram-bot[job-queue]"
        echo "✅ 依赖更新完成。"
    else
        echo "❌ 更新失败。请检查网络或git配置。"
    fi
    echo ""
}

perform_uninstall() {
    echo "警告：这将彻底卸载机器人，并删除所有相关文件！"
    echo "项目目录: $INSTALL_PATH"
    read -p "确认要卸载吗？请输入 'yes' 继续: " confirm_uninstall < /dev/tty
    if [ "$confirm_uninstall" == "yes" ]; then
        echo "正在开始卸载..."
        # 强力查杀所有bot.py相关进程，最多尝试3次
        for i in 1 2 3; do
            PIDS=$(ps aux | grep '[b]ot.py' | awk '{print $2}')
            if [ -n "$PIDS" ]; then
                echo "正在强制终止以下进程: $PIDS"
                kill -9 $PIDS
                sleep 1
            else
                break
            fi
        done
        if [ -L "/usr/local/bin/qiandao-bot" ]; then rm -f "/usr/local/bin/qiandao-bot"; fi
        if [ -d "$INSTALL_PATH" ]; then rm -rf "$INSTALL_PATH"; fi
        REMAIN=$(ps aux | grep '[b]ot.py' | grep -v grep)
        if [ -n "$REMAIN" ]; then
            echo "⚠️ 警告：仍有以下bot.py相关进程未被终止，请手动kill："
            echo "$REMAIN"
            echo "如遇极端情况，建议先用菜单停止机器人，再卸载。"
        else
            echo "✅ 卸载完成，所有相关进程已终止。"
        fi
        exit 0
    else
        echo "卸载已取消。"
    fi
}

perform_dependency_check() {
    echo "--- 检查/修复依赖 ---"
    cd "$SCRIPT_DIR" || exit
    
    if [ ! -f "requirements.txt" ]; then
        echo "❌ requirements.txt 文件不存在"
        return 1
    fi
    
    echo "📋 检查依赖包状态..."
    "$PYTHON_IN_VENV" -m pip check
    
    if [ $? -eq 0 ]; then
        echo "✅ 依赖包状态正常"
    else
        echo "⚠️ 发现依赖问题，正在修复..."
        echo "📦 重新安装依赖包..."
        "$PYTHON_IN_VENV" -m pip install --upgrade pip
        "$PYTHON_IN_VENV" -m pip install -r requirements.txt --force-reinstall
        "$PYTHON_IN_VENV" -m pip install "python-telegram-bot[job-queue]"
        echo "✅ 依赖修复完成"
    fi
    
    echo "📊 已安装的依赖包："
    "$PYTHON_IN_VENV" -m pip list | grep -E "(telegram|requests|pyotp|curl|dotenv|croniter)"
    echo ""
}

install_dependencies() {
    echo "--- 安装依赖 ---"
    cd "$SCRIPT_DIR" || exit
    
    if [ ! -f "requirements.txt" ]; then
        echo "❌ requirements.txt 文件不存在"
        return 1
    fi
    
    echo "📦 正在安装依赖包..."
    echo "🔧 使用包管理器: $PIP_CMD"
    
    # 升级pip
    "$PYTHON_IN_VENV" -m pip install --upgrade pip
    
    # 安装依赖
    "$PYTHON_IN_VENV" -m pip install -r requirements.txt
    "$PYTHON_IN_VENV" -m pip install "python-telegram-bot[job-queue]"
    
    if [ $? -eq 0 ]; then
        echo "✅ 依赖安装成功"
        echo "📊 已安装的依赖包："
        "$PYTHON_IN_VENV" -m pip list | grep -E "(telegram|requests|pyotp|curl|dotenv|croniter)"
    else
        echo "❌ 依赖安装失败"
        return 1
    fi
    echo ""
}

run_management_menu() {
    cd "$SCRIPT_DIR" || exit
    trap '' INT
    while true; do
        PID=$(find_bot_pid)
        [ -n "$PID" ] && STATUS_MSG="✅ 正在运行 (PID: $PID)" || STATUS_MSG="❌ 已停止"
        echo ""
        echo "--- 机器人管理菜单 (当前状态: $STATUS_MSG) ---"
        echo " [1] 启动/重启机器人"
        echo " [2] 停止机器人"
        echo " [3] 查看实时日志"
        echo " [4] 检查进程状态"
        echo " [5] 检查并安装更新"
        echo " [6] 检查/修复依赖"
        echo " [7] 重新安装依赖"
        echo " [8] 检查/修复虚拟环境"
        echo " [9] 卸载机器人"
        echo " [0] 退出"
        read -p "请输入操作选项: " action < /dev/tty
        case $action in
            1)
                [ -n "$PID" ] && echo "正在重启..." && kill "$PID" && sleep 2 || echo "正在启动..."
                # 设置时区
                setup_timezone
                echo "🚀 启动机器人..."
                nohup "$PYTHON_IN_VENV" -u bot.py > "$SCRIPT_DIR/bot.log" 2>&1 &
                disown $!
                sleep 1
                [ -n "$(find_bot_pid)" ] && echo "✅ 操作成功。" || echo "❌ 操作失败，请检查日志。"
                ;;
            2)
                if [ -n "$PID" ]; then
                    echo "正在停止机器人 (PID: $PID)..." && kill "$PID" && sleep 1
                    [ -z "$(find_bot_pid)" ] && echo "✅ 已停止。" || echo "❌ 停止失败。"
                else
                    echo "机器人当前未运行。"
                fi
                ;;
            3)
                echo "--- 正在查看实时日志... 按任意键返回菜单 ---"
                tail -f "$SCRIPT_DIR/bot.log" &
                TAIL_PID=$!
                read -n 1 -s -r < /dev/tty
                kill $TAIL_PID
                echo -e "\n--- 已返回菜单 ---"
                ;;
            4)
                echo "--- 检查进程状态 ---"
                if [ -n "$PID" ]; then
                    echo "✅ 机器人正在运行。"
                    ps -p "$PID" -o comm,pid,etime,user,ppid
                else
                    echo "❌ 机器人已停止。"
                fi
                read -n 1 -s -r -p "按任意键返回菜单..." < /dev/tty
                ;;
            5) perform_update ;;
            6) perform_dependency_check ;;
            7) install_dependencies ;;
            8) check_and_fix_venv ;;
            9) perform_uninstall ;;
            0) echo "已退出。" && trap - INT && exit 0 ;;
            *) echo "无效输入。" ;;
        esac
    done
}

export -f perform_update
export -f perform_uninstall
export -f perform_dependency_check
export -f install_dependencies
export -f check_and_fix_venv

# --- 主逻辑 ---
if [ "$1" == "uninstall" ]; then
    perform_uninstall
elif [ "$1" == "update" ]; then
    perform_update
elif [ "$1" == "install-deps" ]; then
    install_dependencies
elif [ "$1" == "check-deps" ]; then
    perform_dependency_check
elif [ "$1" == "check-venv" ]; then
    check_and_fix_venv
else
    run_management_menu
fi 