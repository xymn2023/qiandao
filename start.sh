#!/bin/bash
set -e

# ================== Telegram 多功能签到机器人 ==================
#   Acck 和 Akile 两个平台的签到功能，一键脚本傻瓜式操作简单易上手  欢迎二开
#   用作安装器: bash <(curl -fsSL https://raw.githubusercontent.com/xymn2023/qiandao/main/start.sh)
#   用作管理器: qiandao-bot (或在项目目录中 bash start.sh)
#   Github地址：https://github.com/xymn2023/qiandao
#   作者：https://github.com/xymn2023/
#   灵感来自于：https://github.com/QiQuWa/QingLong
# =============================================================

REPO_URL="https://github.com/xymn2023/qiandao.git"
INSTALL_PATH_GLOBAL="/opt/qiandao"
INSTALL_PATH_LOCAL="$HOME/qiandao"
ALIAS_CMD="alias qiandao-bot='bash $INSTALL_PATH_LOCAL/start.sh'"

# 检查依赖
for cmd in git python3 curl; do
    if ! command -v $cmd &>/dev/null; then
        echo "缺少依赖: $cmd，请先安装！"
        exit 1
    fi
done

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
    python3 -m venv .venv
    ./.venv/bin/python -m pip install --upgrade pip python-telegram-bot requests pyotp curl_cffi python-dotenv
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

# --- 函数定义区 ---
find_bot_pid() {
    pgrep -f "$PYTHON_IN_VENV -u bot.py" || true
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
        "$PYTHON_IN_VENV" -m pip install --upgrade pip python-telegram-bot requests pyotp curl_cffi python-dotenv
        echo "依赖更新完成。"
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
            1)
                [ -n "$PID" ] && echo "正在重启..." && kill "$PID" && sleep 2 || echo "正在启动..."
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
            6) perform_uninstall ;;
            0) echo "已退出。" && trap - INT && exit 0 ;;
            *) echo "无效输入。" ;;
        esac
    done
}

export -f perform_update
export -f perform_uninstall

# --- 主逻辑 ---
if [ "$1" == "uninstall" ]; then
    perform_uninstall
elif [ "$1" == "update" ]; then
    perform_update
else
    run_management_menu
fi 
