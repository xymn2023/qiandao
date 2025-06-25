#!/bin/bash
set -e

# ================== 服务管理器脚本 ==================
#
#   用作安装器: curl ... | sudo bash -s install
#   用作管理器: qiandao-bot (或在项目目录中 bash start.sh)
#
# ====================================================

# --- 全局变量和函数 ---
PROJECT_DIR_NAME="qiandao"
INSTALL_PATH="/opt/qiandao"
# 通过readlink -f确保能解析软链接，找到脚本的真实目录
SCRIPT_REAL_PATH=$(readlink -f "${BASH_SOURCE[0]}")
SCRIPT_DIR=$(dirname "$SCRIPT_REAL_PATH")

PYTHON_IN_VENV="$SCRIPT_DIR/.venv/bin/python"

# 查找机器人进程PID的函数
find_bot_pid() {
    pgrep -f "$SCRIPT_DIR/.venv/bin/python -u bot.py" || true
}

# --- 管理菜单函数 ---
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
        echo " [6] 卸载机器人"
        echo " [0] 退出"
        read -p "请输入操作选项: " action < /dev/tty

        case $action in
            1) # 启动/重启
                [ -n "$PID" ] && echo "正在重启..." && kill "$PID" && sleep 2 || echo "正在启动..."
                nohup "$PYTHON_IN_VENV" -u bot.py > "$SCRIPT_DIR/bot.log" 2>&1 &
                disown $!
                sleep 1
                [ -n "$(find_bot_pid)" ] && echo "✅ 操作成功。" || echo "❌ 操作失败，请检查日志。"
                ;;
            2) # 停止
                if [ -n "$PID" ]; then
                    echo "正在停止机器人 (PID: $PID)..." && kill "$PID" && sleep 1
                    [ -z "$(find_bot_pid)" ] && echo "✅ 已停止。" || echo "❌ 停止失败。"
                else
                    echo "机器人当前未运行。"
                fi
                ;;
            3) # 查看日志
                echo "--- 正在查看实时日志... 按任意键返回菜单 ---"
                tail -f "$SCRIPT_DIR/bot.log" &
                TAIL_PID=$!
                read -n 1 -s -r < /dev/tty
                kill $TAIL_PID
                echo -e "\n--- 已返回菜单 ---"
                ;;
            4) # 检查进程状态
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
            6) perform_uninstall ;;
            0) echo "已退出。" && trap - INT && exit 0 ;;
            *) echo "无效输入。" ;;
        esac
    done
}


# --- 主逻辑：根据参数判断执行流程 ---
if [ "$1" == "install" ]; then
    # --- 安装流程 ---
    echo "开始一键安装..."
    cd /tmp || exit
    if ! command -v git &> /dev/null; then echo "错误:需要git"; exit 1; fi
    [ -d "qiandao" ] && rm -rf "qiandao"
    git clone "https://github.com/xymn2023/qiandao.git" "qiandao"
    [ -d "$INSTALL_PATH" ] && rm -rf "$INSTALL_PATH"
    mv "qiandao" /opt/
    cd "$INSTALL_PATH" || exit
    python3 -m venv .venv
    ./.venv/bin/python -m pip install --upgrade pip python-telegram-bot requests pyotp curl_cffi python-dotenv
    read -p "请输入你的 Telegram Bot Token: " TOKEN < /dev/tty
    read -p "请输入你的 Telegram Chat ID (管理员ID): " CHAT_ID < /dev/tty
    sed -i "s/^TELEGRAM_BOT_TOKEN = .*/TELEGRAM_BOT_TOKEN = \"$TOKEN\"/" bot.py
    sed -i "s/^TELEGRAM_CHAT_ID = .*/TELEGRAM_CHAT_ID = \"$CHAT_ID\"/" bot.py
    if [ "$(id -u)" -eq 0 ]; then
        ln -sf "$INSTALL_PATH/start.sh" /usr/local/bin/qiandao-bot
        echo "✅ 已创建系统快捷命令 'qiandao-bot'。"
    fi
    echo "✅ 安装完成！正在进入管理菜单..."
    exec bash "$INSTALL_PATH/start.sh"

elif [ "$1" == "uninstall" ]; then
    # --- 卸载流程 ---
    perform_uninstall

elif [ "$1" == "update" ]; then
    # --- 更新流程 ---
    perform_update

else
    # --- 管理流程 (默认) ---
    if [ ! -f "$SCRIPT_DIR/bot.py" ]; then
        echo "错误：机器人似乎未安装。"
        echo "请先使用 'curl... | sudo bash -s install' 命令进行安装。"
        exit 1
    fi
    run_management_menu
fi 
