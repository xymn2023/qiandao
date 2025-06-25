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
# 找到脚本所在的真实目录
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

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


# --- 主逻辑：根据参数判断是安装、卸载还是管理 ---
case "$1" in
    install)
        # ================== 安装流程 ==================
        echo "开始一键安装..."

        # 1. 确保在主目录或临时目录执行
        cd /tmp

        # 2. 下载项目
        if ! command -v git &> /dev/null; then exit 1; fi
        if [ -d "$PROJECT_DIR_NAME" ]; then rm -rf "$PROJECT_DIR_NAME"; fi
        git clone "https://github.com/xymn2023/qiandao.git" "$PROJECT_DIR_NAME"
        # 注意：安装时，我们将项目移动到一个更永久的位置
        INSTALL_PATH="/opt/$PROJECT_DIR_NAME"
        if [ -d "$INSTALL_PATH" ]; then
            echo "发现旧的安装目录，正在覆盖..."
            rm -rf "$INSTALL_PATH"
        fi
        mv "$PROJECT_DIR_NAME" /opt/
        cd "$INSTALL_PATH" || exit

        # 3. 创建虚拟环境和安装依赖
        python3 -m venv .venv
        ./.venv/bin/python -m pip install --upgrade pip python-telegram-bot requests pyotp curl_cffi python-dotenv

        # 4. 交互式配置
        read -p "请输入你的 Telegram Bot Token: " TELEGRAM_BOT_TOKEN < /dev/tty
        read -p "请输入你的 Telegram Chat ID (管理员ID): " TELEGRAM_CHAT_ID < /dev/tty
        sed -i "s/^TELEGRAM_BOT_TOKEN = .*/TELEGRAM_BOT_TOKEN = \"$TELEGRAM_BOT_TOKEN\"/" bot.py
        sed -i "s/^TELEGRAM_CHAT_ID = .*/TELEGRAM_CHAT_ID = \"$TELEGRAM_CHAT_ID\"/" bot.py

        # 5. 创建快捷命令
        if [ "$(id -u)" -eq 0 ]; then
            ln -sf "$INSTALL_PATH/start.sh" /usr/local/bin/qiandao-bot
            echo "✅ 已创建系统快捷命令 'qiandao-bot'。"
        else
            echo "警告: 当前非root用户，无法创建系统快捷命令。"
        fi

        echo "✅ 安装完成！正在进入管理菜单..."
        # 切换到脚本自身的路径来执行管理菜单
        exec bash "$INSTALL_PATH/start.sh"
        ;;

    uninstall)
        # ================== 卸载流程 ==================
        INSTALL_PATH="/opt/$PROJECT_DIR_NAME"
        echo "警告：这将彻底卸载机器人，并删除所有相关文件！"
        echo "项目目录: $INSTALL_PATH"
        read -p "确认要卸载吗？请输入 'yes' 继续: " confirm_uninstall < /dev/tty
        if [ "$confirm_uninstall" == "yes" ]; then
            echo "正在开始卸载..."
            # 1. 停止机器人进程
            PID=$(pgrep -f "$INSTALL_PATH/.venv/bin/python -u bot.py" || true)
            if [ -n "$PID" ]; then
                echo "正在停止机器人进程 (PID: $PID)..."
                kill -9 "$PID"
            fi
            # 2. 删除快捷命令
            if [ -L "/usr/local/bin/qiandao-bot" ]; then
                echo "正在删除快捷命令..."
                rm -f "/usr/local/bin/qiandao-bot"
            fi
            # 3. 删除项目目录
            if [ -d "$INSTALL_PATH" ]; then
                echo "正在删除项目目录..."
                rm -rf "$INSTALL_PATH"
            fi
            echo "✅ 卸载完成。"
        else
            echo "卸载已取消。"
        fi
        ;;

    *)
        # ================== 管理流程 ==================
        INSTALL_PATH="/opt/$PROJECT_DIR_NAME"
        # 如果通过快捷命令调用，脚本自身路径就是安装路径
        if [ ! -f "$SCRIPT_DIR/bot.py" ] && [ -d "$INSTALL_PATH" ]; then
             # 如果当前脚本不是在安装目录中，就执行安装目录的脚本
            exec bash "$INSTALL_PATH/start.sh"
        elif [ -f "$SCRIPT_DIR/bot.py" ]; then
             run_management_menu
        else
            echo "错误：机器人似乎未安装。"
            echo "请先使用 'curl... | sudo bash -s install' 命令进行安装。"
            exit 1
        fi
        ;;
esac 
