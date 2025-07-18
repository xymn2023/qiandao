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
                if [ $? -ne 0 ]; then
                    echo "❌ python3-venv 安装失败，请手动检查并安装"
                    exit 1
                fi
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
                if [ $? -ne 0 ]; then
                    echo "❌ python3-venv 安装失败，请手动检查并安装"
                    exit 1
                fi
                echo "✅ python3-venv 安装完成"
            elif command -v dnf &>/dev/null; then
                dnf install -y python3-venv
                if [ $? -ne 0 ]; then
                    echo "❌ python3-venv 安装失败，请手动检查并安装"
                    exit 1
                fi
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
            if [ $? -ne 0 ]; then
                echo "❌ 时区设置失败，请手动设置"
                return 1
            fi
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
    if [ $? -ne 0 ]; then
        echo "❌ 升级pip失败，请检查网络或依赖文件"
        exit 1
    fi
    ./.venv/bin/python -m pip install -r requirements.txt
    if [ $? -ne 0 ]; then
        echo "❌ 依赖安装失败，请检查网络或依赖文件"
        exit 1
    fi
    ./.venv/bin/python -m pip install "python-telegram-bot[job-queue]"
    if [ $? -ne 0 ]; then
        echo "❌ 安装python-telegram-bot[job-queue]失败，请检查网络或依赖文件"
        exit 1
    fi
    echo "✅ 依赖安装完成"
    
    # 立即注册永久全局命令
    echo "🔗 正在注册永久全局命令..."
    if [ "$IS_ROOT" = "1" ]; then
        ln -sf "$INSTALL_PATH/start.sh" "$SHORTCUT"
        chmod +x "$SHORTCUT"
        echo "✅ 全局命令已注册：qiandao-bot"
        # 验证命令是否可用
        if command -v qiandao-bot >/dev/null 2>&1; then
            echo "✅ 命令验证成功：qiandao-bot 已可用"
        else
            echo "⚠️ 命令验证失败，请手动检查：ls -la /usr/local/bin/qiandao-bot"
        fi
    else
        # 检查是否已存在alias，避免重复添加
        if ! grep -q "alias qiandao-bot=" ~/.bashrc; then
            echo "$ALIAS_CMD" >> ~/.bashrc
            echo "✅ alias 已添加到 ~/.bashrc"
            echo "🔄 正在重新加载 ~/.bashrc..."
            source ~/.bashrc
            if command -v qiandao-bot >/dev/null 2>&1; then
                echo "✅ 命令验证成功：qiandao-bot 已可用"
            else
                echo "⚠️ 请手动执行：source ~/.bashrc 后使用 qiandao-bot"
            fi
        else
            echo "✅ alias 已存在，正在重新加载..."
            source ~/.bashrc
        fi
    fi
    
    read -p "请输入你的 Telegram Bot Token: " TOKEN < /dev/tty
    read -p "请输入你的 Telegram Chat ID (管理员ID): " CHAT_ID < /dev/tty
    cat > .env <<EOF
TELEGRAM_BOT_TOKEN=$TOKEN
TELEGRAM_CHAT_ID=$CHAT_ID
EOF
    chmod +x start.sh
    
    echo "✅ 安装完成！"
    echo "🎉 现在你可以在任意目录使用 'qiandao-bot' 命令启动机器人！"
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

# 检查虚拟环境是否存在，不存在时仅提示，不自动创建和启动bot.py
if [ ! -f "$PYTHON_IN_VENV" ]; then
    echo "⚠️ 检测到虚拟环境不存在，请先通过菜单4或5检测/修复依赖环境！"
fi

# ========== 命令行菜单 ==========
# 在菜单顶部动态显示机器人运行状态
show_menu() {
    local pid=$(find_bot_pid)
    if [ -n "$pid" ]; then
        STATUS_ICON="✔️"
        STATUS_TEXT="运行中 (PID: $pid)"
    else
        STATUS_ICON="❌"
        STATUS_TEXT="未运行"
    fi
    echo -e "\n====== 签到机器人管理菜单 ======"
    echo -e "机器人运行状态: $STATUS_ICON $STATUS_TEXT"
    echo "1. 启动/重启机器人"
    echo "2. 停止机器人"
    echo "3. 查看运行状态"
    echo "4. 查看实时日志"
    echo "5. 检测环境依赖"
    echo "6. 修复依赖环境"
    echo "7. 更新脚本"
    echo "8. 卸载(删除所有文件)"
    echo "0. 退出菜单(不影响后台运行)"
    echo "##.使用 qiandao-bot 唤醒脚本##"
    echo "**.     任意键返回主菜单"
    echo "==============================="
}

# 检查bot.py是否运行，返回PID
find_bot_pid() {
    pgrep -f "$PYTHON_IN_VENV -u bot.py" || pgrep -f "python.*bot.py" || true
}

# 等待任意键返回主菜单
wait_any_key() {
    echo -e "\n[INFO] 按任意键返回主菜单..."
    read -n 1 -s _
}

# 启动/重启机器人
start_bot() {
    cd "$SCRIPT_DIR"
    local pid=$(find_bot_pid)
    if [ -n "$pid" ]; then
        echo "[INFO] 检测到bot.py正在运行(PID: $pid)，正在重启..."
        kill "$pid"
        sleep 2
    fi
    echo "[INFO] 启动bot.py..."
    nohup "$PYTHON_IN_VENV" -u bot.py > bot.log 2>&1 &
    sleep 1
    newpid=$(find_bot_pid)
    if [ -n "$newpid" ]; then
        echo "[SUCCESS] bot.py已启动(PID: $newpid)"
    else
        echo "[ERROR] 启动失败，请检查日志"
    fi
    wait_any_key
}

# 停止机器人
stop_bot() {
    cd "$SCRIPT_DIR"
    local pid=$(find_bot_pid)
    if [ -n "$pid" ]; then
        echo "[INFO] 停止bot.py (PID: $pid)..."
        kill "$pid"
        sleep 2
        if ps -p "$pid" > /dev/null 2>&1; then
            echo "[WARNING] 强制停止..."
            kill -9 "$pid" 2>/dev/null
        fi
        echo "[SUCCESS] 已停止"
    else
        echo "[INFO] bot.py未在运行"
    fi
    wait_any_key
}

# 查看实时日志
show_log() {
    cd "$SCRIPT_DIR"
    if [ ! -f bot.log ]; then
        echo "[WARNING] 日志文件不存在，请先启动机器人！"
        wait_any_key
        return
    fi
    echo "[INFO] 按任意键返回主菜单"
    tail -n 50 -f bot.log &
    TAIL_PID=$!
    read -n 1 -s _
    kill $TAIL_PID 2>/dev/null
}

# 检测环境依赖
check_env() {
    echo "[检测环境]"
    check_and_install_venv
    if [ ! -f "$PYTHON_IN_VENV" ]; then
        echo "[ERROR] 虚拟环境不存在"
        wait_any_key
        return 1
    fi
    "$PYTHON_IN_VENV" -m pip --version && "$PYTHON_IN_VENV" -m pip check
    if [ $? -eq 0 ]; then
        echo "[SUCCESS] 依赖环境完整"
    else
        echo "[WARNING] 依赖环境可能不完整"
    fi
    wait_any_key
}

# 修复依赖环境
fix_env() {
    if [ -f "$PYTHON_IN_VENV" ]; then
        echo "[INFO] 虚拟环境已存在，跳过重建"
    else
        echo "[INFO] 正在创建虚拟环境..."
        python3 -m venv .venv || { echo "[ERROR] 创建虚拟环境失败"; wait_any_key; return 1; }
    fi
    "$PYTHON_IN_VENV" -m pip install --upgrade pip
    "$PYTHON_IN_VENV" -m pip install -r requirements.txt
    "$PYTHON_IN_VENV" -m pip install "python-telegram-bot[job-queue]"
    echo "[SUCCESS] 依赖修复完成"
    
    # 检查并修复全局命令注册
    echo "[INFO] 检查qiandao-bot全局命令注册..."
    if [ "$IS_ROOT" = "1" ]; then
        # 检查软链接是否存在且正确
        if [ ! -L /usr/local/bin/qiandao-bot ] || [ "$(readlink -f /usr/local/bin/qiandao-bot 2>/dev/null)" != "$(readlink -f "$SCRIPT_DIR/start.sh")" ]; then
            echo "[INFO] 软链接不存在或错误，正在修复..."
            rm -f /usr/local/bin/qiandao-bot
            ln -sf "$SCRIPT_DIR/start.sh" /usr/local/bin/qiandao-bot
            chmod +x /usr/local/bin/qiandao-bot
            echo "[SUCCESS] 已修复全局命令(软链)：qiandao-bot"
        else
            echo "[INFO] 全局命令(软链)已存在且正确"
        fi
        # 验证命令是否可用
        if command -v qiandao-bot >/dev/null 2>&1; then
            echo "[SUCCESS] 命令验证成功：qiandao-bot 已可用"
        else
            echo "[WARNING] 命令验证失败，请检查PATH设置"
        fi
    else
        # 检查alias是否存在且正确
        if ! grep -q "alias qiandao-bot=" ~/.bashrc; then
            echo "[INFO] alias不存在，正在添加..."
            echo "$ALIAS_CMD" >> ~/.bashrc
            echo "[SUCCESS] 已添加alias到 ~/.bashrc"
        else
            # 检查alias是否正确
            current_alias=$(grep "alias qiandao-bot=" ~/.bashrc | head -1)
            if [ "$current_alias" != "$ALIAS_CMD" ]; then
                echo "[INFO] alias不正确，正在修复..."
                # 删除旧的alias
                sed -i '/alias qiandao-bot=/d' ~/.bashrc
                # 添加新的alias
                echo "$ALIAS_CMD" >> ~/.bashrc
                echo "[SUCCESS] 已修复alias"
            else
                echo "[INFO] alias已存在且正确"
            fi
        fi
        # 重新加载bashrc
        source ~/.bashrc
        if command -v qiandao-bot >/dev/null 2>&1; then
            echo "[SUCCESS] 命令验证成功：qiandao-bot 已可用"
        else
            echo "[WARNING] 请手动执行：source ~/.bashrc 后使用 qiandao-bot"
        fi
    fi
    wait_any_key
}

# 更新脚本（保留.env）
update_script() {
    echo "[INFO] 检查更新方式..."
    
    # 检查是否为Git仓库
    if [ -d ".git" ]; then
        echo "[INFO] 检测到Git仓库，使用Git方式更新..."
        update_via_git
    else
        echo "[INFO] 检测到非Git仓库，使用下载方式更新..."
        update_via_download
    fi
    
    echo "[SUCCESS] 更新完成"
    wait_any_key
}

# Git方式更新
update_via_git() {
    echo "[INFO] 正在从GitHub拉取最新代码..."
    
    # 先备份.env文件（如果存在）
    if [ -f .env ]; then
        echo "[INFO] 备份.env配置文件..."
        cp .env /tmp/qiandao_env_backup
    fi
    
    # 拉取最新代码
    if git fetch origin main; then
        if git reset --hard origin/main; then
            echo "[SUCCESS] Git更新成功"
        else
            echo "[ERROR] Git重置失败"
            exit 1
        fi
    else
        echo "[ERROR] Git拉取失败"
        exit 1
    fi
    
    # 恢复.env文件（如果之前存在）
    if [ -f /tmp/qiandao_env_backup ]; then
        echo "[INFO] 恢复.env配置文件..."
        mv /tmp/qiandao_env_backup .env
        echo "[SUCCESS] .env配置已保留"
    fi
}

# 下载方式更新
update_via_download() {
    echo "[INFO] 正在从GitHub下载最新代码..."
    
    # 创建备份目录
    BACKUP_DIR="/tmp/qiandao_backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    echo "[INFO] 创建备份目录: $BACKUP_DIR"
    
    # 备份重要文件
    echo "[INFO] 备份重要文件..."
    
    # 备份.env文件
    if [ -f .env ]; then
        cp .env "$BACKUP_DIR/"
        echo "[SUCCESS] 已备份 .env"
    fi
    
    # 备份用户数据目录
    for dir in "Acck_users" "Akile_users"; do
        if [ -d "$dir" ]; then
            cp -r "$dir" "$BACKUP_DIR/"
            echo "[SUCCESS] 已备份 $dir"
        fi
    done
    
    # 备份日志目录
    for dir in "Acck_logs" "Akile_logs"; do
        if [ -d "$dir" ]; then
            cp -r "$dir" "$BACKUP_DIR/"
            echo "[SUCCESS] 已备份 $dir"
        fi
    done
    
    # 备份其他重要文件
    for file in "scheduled_tasks.json" "allowed_users.json" "banned_users.json" "daily_usage.json" "usage_stats.json"; do
        if [ -f "$file" ]; then
            cp "$file" "$BACKUP_DIR/"
            echo "[SUCCESS] 已备份 $file"
        fi
    done
    
    # 下载最新代码
    echo "[INFO] 下载最新代码..."
    cd ..
    CURRENT_DIR_NAME=$(basename "$SCRIPT_DIR")
    
    # 重命名当前目录
    mv "$CURRENT_DIR_NAME" "${CURRENT_DIR_NAME}_old"
    
    # 克隆最新代码
    if git clone "$REPO_URL" "$CURRENT_DIR_NAME"; then
        echo "[SUCCESS] 代码下载成功"
        
        # 进入新目录
        cd "$CURRENT_DIR_NAME"
        
        # 恢复备份的文件
        echo "[INFO] 恢复备份文件..."
        
        # 恢复.env文件
        if [ -f "$BACKUP_DIR/.env" ]; then
            cp "$BACKUP_DIR/.env" .
            echo "[SUCCESS] 已恢复 .env"
        fi
        
        # 恢复用户数据目录
        for dir in "Acck_users" "Akile_users"; do
            if [ -d "$BACKUP_DIR/$dir" ]; then
                cp -r "$BACKUP_DIR/$dir" .
                echo "[SUCCESS] 已恢复 $dir"
            fi
        done
        
        # 恢复日志目录
        for dir in "Acck_logs" "Akile_logs"; do
            if [ -d "$BACKUP_DIR/$dir" ]; then
                cp -r "$BACKUP_DIR/$dir" .
                echo "[SUCCESS] 已恢复 $dir"
            fi
        done
        
        # 恢复其他重要文件
        for file in "scheduled_tasks.json" "allowed_users.json" "banned_users.json" "daily_usage.json" "usage_stats.json"; do
            if [ -f "$BACKUP_DIR/$file" ]; then
                cp "$BACKUP_DIR/$file" .
                echo "[SUCCESS] 已恢复 $file"
            fi
        done
        
        # 删除旧目录
        echo "[INFO] 清理旧文件..."
        rm -rf "../${CURRENT_DIR_NAME}_old"
        
        # 清理备份目录
        rm -rf "$BACKUP_DIR"
        
        echo "[SUCCESS] 更新完成！"
        
    else
        echo "[ERROR] 代码下载失败"
        
        # 恢复原目录
        cd ..
        mv "${CURRENT_DIR_NAME}_old" "$CURRENT_DIR_NAME"
        cd "$CURRENT_DIR_NAME"
        
        echo "[INFO] 已恢复到原始状态"
        exit 1
    fi
}

# 卸载（删除所有文件）
uninstall_all() {
    echo "[WARNING] 即将删除本项目所有文件，包括缓存和日志！"
    read -p "确认卸载？(y/n): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        cd ..
        rm -rf "$SCRIPT_DIR"
        echo "[SUCCESS] 已卸载并删除全部文件"
        wait_any_key
        exit 0
    else
        echo "[INFO] 已取消卸载"
        wait_any_key
    fi
}

# 注册全局命令
register_global() {
    if [ "$IS_ROOT" = "1" ]; then
        ln -sf "$SCRIPT_DIR/start.sh" /usr/local/bin/qiandao-bot
        chmod +x /usr/local/bin/qiandao-bot
        echo "[SUCCESS] 已注册全局命令：qiandao-bot"
    else
        if ! grep -q "alias qiandao-bot=" ~/.bashrc; then
            echo "$ALIAS_CMD" >> ~/.bashrc
            echo "alias 已添加到 ~/.bashrc，请运行 source ~/.bashrc 后使用 qiandao-bot"
        fi
        echo "[SUCCESS] 已注册全局命令：qiandao-bot (alias)"
    fi
    wait_any_key
}

# 检查运行状态
check_status() {
    cd "$SCRIPT_DIR"
    local pid=$(find_bot_pid)
    if [ -n "$pid" ]; then
        echo "[STATUS] bot.py 正在运行 (PID: $pid)"
        ps -p "$pid" -o pid,etime,cmd
    else
        echo "[STATUS] bot.py 未在运行"
    fi
    wait_any_key
}

# 主菜单循环
while true; do
    show_menu
    read -p "请选择操作 [0-8]: " choice
    case $choice in
        1) start_bot ;;
        2) stop_bot ;;
        3) check_status ;;
        4) show_log ;;
        5) check_env ;;
        6) fix_env ;;
        7) update_script ;;
        8) uninstall_all ;;
        0) echo "[INFO] 退出菜单，bot.py继续后台运行"; exit 0 ;;
        ##|**)
        9|10) ;; # 占位，防止误触
        *) echo "[ERROR] 无效选择，请重试" ;;
    esac
    echo ""
done
