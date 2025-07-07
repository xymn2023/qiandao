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
        if [ $? -ne 0 ]; then
            echo "❌ 升级pip失败，请检查网络或依赖文件"
            exit 1
        fi
        "$PYTHON_IN_VENV" -m pip install -r requirements.txt
        if [ $? -ne 0 ]; then
            echo "❌ 依赖安装失败，请检查网络或依赖文件"
            exit 1
        fi
        "$PYTHON_IN_VENV" -m pip install "python-telegram-bot[job-queue]"
        if [ $? -ne 0 ]; then
            echo "❌ 安装python-telegram-bot[job-queue]失败，请检查网络或依赖文件"
            exit 1
        fi
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
            if [ $? -ne 0 ]; then
                echo "❌ 升级pip失败，请检查网络或依赖文件"
                return 1
            fi
            "$PYTHON_IN_VENV" -m pip install -r requirements.txt
            if [ $? -ne 0 ]; then
                echo "❌ 依赖安装失败，请检查网络或依赖文件"
                return 1
            fi
            "$PYTHON_IN_VENV" -m pip install "python-telegram-bot[job-queue]"
            if [ $? -ne 0 ]; then
                echo "❌ 安装python-telegram-bot[job-queue]失败，请检查网络或依赖文件"
                return 1
            fi
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
                if [ $? -ne 0 ]; then
                    echo "❌ 升级pip失败，请检查网络或依赖文件"
                    return 1
                fi
                "$PYTHON_IN_VENV" -m pip install -r requirements.txt
                if [ $? -ne 0 ]; then
                    echo "❌ 依赖安装失败，请检查网络或依赖文件"
                    return 1
                fi
                "$PYTHON_IN_VENV" -m pip install "python-telegram-bot[job-queue]"
                if [ $? -ne 0 ]; then
                    echo "❌ 安装python-telegram-bot[job-queue]失败，请检查网络或依赖文件"
                    return 1
                fi
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
            # 可以添加更详细的冲突处理逻辑
        fi
        echo "✅ 更新完成。正在重新安装依赖..."
        "$PYTHON_IN_VENV" -m pip install --upgrade pip
        if [ $? -ne 0 ]; then
            echo "❌ 升级pip失败，请检查网络或依赖文件"
            return 1
        fi
        "$PYTHON_IN_VENV" -m pip install -r requirements.txt
        if [ $? -ne 0 ]; then
            echo "❌ 依赖安装失败，请检查网络或依赖文件"
            return 1
        fi
        "$PYTHON_IN_VENV" -m pip install "python-telegram-bot[job-queue]"
        if [ $? -ne 0 ]; then
            echo "❌ 安装python-telegram-bot[job-queue]失败，请检查网络或依赖文件"
            return 1
        fi
        echo "✅ 依赖重新安装完成"
    else
        echo "❌ 更新失败，请检查网络或仓库状态"
        return 1
    fi
}

# 后续代码保持不变
{insert\_element\_1\_YGBgCgojIyM=} 2. `bot.py` 文件优化

```python
# ========== 重要配置 ==========
# 请在下方填写你的 Telegram Bot Token 和 Chat ID
from dotenv import load_dotenv
import os
load_dotenv()
TELEGRAM_BOT_TOKEN = os.getenv("TELEGRAM_BOT_TOKEN")
TELEGRAM_CHAT_ID = os.getenv("TELEGRAM_CHAT_ID")
if not TELEGRAM_BOT_TOKEN or not TELEGRAM_CHAT_ID:
    print("❌ 配置错误：请在项目根目录新建 .env 文件，并填写 TELEGRAM_BOT_TOKEN 和 TELEGRAM_CHAT_ID")
    exit(1)
# ==============================

import os
import json
import requests
import subprocess
from datetime import datetime, date, timedelta, timezone
import glob
from telegram import Update, ReplyKeyboardMarkup, ReplyKeyboardRemove, BotCommand, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import (
    Application, CommandHandler, MessageHandler, filters, ConversationHandler, ContextTypes, CallbackQueryHandler
)
from telegram.constants import ParseMode
from Acck.qiandao import main as acck_signin
from Akile.qiandao import main as akile_signin
import sys
import asyncio
import threading
import time
from croniter import croniter
import logging

# ========== 时区设置 ==========
# 设置时区为 Asia/Shanghai
import os
os.environ['TZ'] = 'Asia/Shanghai'
try:
    time.tzset()  # Linux系统设置时区
except AttributeError:
    pass  # Windows系统不支持tzset

# 定义获取上海时间的函数
def get_shanghai_time():
    """获取上海时区的当前时间"""
    shanghai_tz = timezone(timedelta(hours=8))  # UTC+8
    return datetime.now(shanghai_tz)

def get_shanghai_now():
    """获取上海时区的当前时间（不带时区信息，兼容原有代码）"""
    return get_shanghai_time().replace(tzinfo=None)

# ==============================

# 数据文件
ALLOWED_USERS_FILE = "allowed_users.json"
BANNED_USERS_FILE = "banned_users.json"
DAILY_USAGE_FILE = "daily_usage.json"
USAGE_STATS_FILE = "usage_stats.json"
ADMIN_LOG_FILE = "admin_log.json"
ADMIN_ATTEMPT_FILE = "admin_attempts.json"
SCHEDULED_TASKS_FILE = "scheduled_tasks.json"
TEMP_USERS_FILE = "temp_users.json"
USER_LIMITS_FILE = "user_limits.json"
SUMMARY_LOG_FILE = "summary_log.json"
SUMMARY_SIGNIN_FILE = "summary_signin.json"

# 默认每日次数限制
DEFAULT_DAILY_LIMIT = 3

# 日志文件名格式
LOG_TIME_FMT = '%Y-%m-%d_%H%M'

# 推荐时间点
RECOMMENDED_TIMES = [
    (0, 0),   # 0:00
    (0, 10),  # 0:10 (默认)
    (0, 20),  # 0:20
    (0, 30),  # 0:30
    (1, 0),   # 1:00
]

# 默认时间
DEFAULT_HOUR, DEFAULT_MINUTE = 0, 10

# ========== 工具函数 ==========

def load_json(filename, default):
    if os.path.exists(filename):
        try:
            with open(filename, "r", encoding="utf-8") as f:
                return json.load(f)
        except json.JSONDecodeError:
            print(f"❌ 读取 {filename} 文件时发生JSON解析错误，使用默认值")
            return default
    return default

def save_json(filename, data):
    try:
        with open(filename, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
    except Exception as e:
        print(f"❌ 保存 {filename} 文件时发生错误: {e}")

# 白名单

def load_allowed_users():
    return set(load_json(ALLOWED_USERS_FILE, []))

def save_allowed_users(users):
    save_json(ALLOWED_USERS_FILE, list(users))

# 黑名单

def load_banned_users():
    return set(load_json(BANNED_USERS_FILE, []))

def save_banned_users(users):
    save_json(BANNED_USERS_FILE, list(users))

# 日志

def log_admin_action(action, detail):
    logs = load_json(ADMIN_LOG_FILE, [])
    logs.append({
        "time": get_shanghai_now().isoformat(),
        "action": action,
        "detail": detail
    })
    save_json(ADMIN_LOG_FILE, logs)

# 统计

def load_usage_stats():
    return load_json(USAGE_STATS_FILE, {})

def save_usage_stats(stats):
    save_json(USAGE_STATS_FILE, stats)

# 每日次数

def load_daily_usage():
    return load_json(DAILY_USAGE_FILE, {})

def save_daily_usage(usage_data):
    save_json(DAILY_USAGE_FILE, usage_data)

# 权限判断

def is_admin(user_id):
    return str(user_id) == str(TELEGRAM_CHAT_ID)

def is_banned(user_id):
    return user_id in load_banned_users()

def is_allowed(user_id):
    # 只要不是黑名单都允许使用
    return not is_banned(user_id)

# 用户专属签到次数管理
def load_user_limits():
    return load_json(USER_LIMITS_FILE, {})

def save_user_limits(data):
    save_json(USER_LIMITS_FILE, data)

def get_daily_limit(user_id=None):
    # 优先查用户专属次数
    if user_id is not None:
        user_limits = load_user_limits()
        if str(user_id) in user_limits:
            return user_limits[str(user_id)]
        if is_temp_user(user_id):
            return 5
    stats = load_json("limit_config.json", {})
    return stats.get("limit", DEFAULT_DAILY_LIMIT)

# 统计记录

def record_usage(user_id):
    stats = load_usage_stats()
    now = get_shanghai_now().strftime('%Y-%m-%d %H:%M:%S')
    if str(user_id) not in stats:
        stats[str(user_id)] = {"count": 0, "last": now}
    stats[str(user_id)]["count"] += 1
    stats[str(user_id)]["last"] = now
    save_usage_stats(stats)

# 定时任务管理（新结构）
def load_scheduled_tasks():
    return load_json(SCHEDULED_TASKS_FILE, {})

def save_scheduled_tasks(tasks):
    save_json(SCHEDULED_TASKS_FILE, tasks)

def add_scheduled_task(user_id, module, username, hour, minute):
    tasks = load_scheduled_tasks()
    task_id = f"{user_id}_{module}_{username}_{hour:02d}{minute:02d}"
    task = {
        "id": task_id,
        "user_id": str(user_id),
        "module": module,
        "username": username,
        "hour": hour,
        "minute": minute,
        "enabled": True,
        "created_at": get_shanghai_now().isoformat(),
        "last_run": None
    }
    tasks[task_id] = task
    save_scheduled_tasks(tasks)
    return True, task_id

def remove_scheduled_task(task_id, user_id):
    tasks = load_scheduled_tasks()
    if task_id not in tasks:
        return False, "任务不存在"
    task = tasks[task_id]
    if str(task["user_id"]) != str(user_id) and not is_admin(int(user_id)):
        return False, "无权限删除此任务"
    del tasks[task_id]
    save_scheduled_tasks(tasks)
    return True, "任务已删除"

def get_user_tasks(user_id):
    tasks = load_scheduled_tasks()
    return {tid: t for tid, t in tasks.items() if str(t["user_id"]) == str(user_id)}

def parse_time_input(time_str):
    """解析时间输入，支持 HH:MM 格式"""
    try:
        if ':' in time_str:
            hour, minute = map(int, time_str.split(':'))
        else:
            hour, minute = map(int, time_str.split('.'))
        
        if 0 <= hour <= 23 and 0 <= minute <= 59:
            return (True, hour, minute)
        else:
            return (False, 0, "时间格式错误：小时应在0-23之间，分钟应在0-59之间")
    except:
        return (False, 0, "时间格式错误：请使用 HH:MM 格式，如 8:30")

# 日志保存函数

def save_task_log(module, username, status, message, error=None):
    now = get_shanghai_now().strftime('%Y%m%d_%H%M%S')
    log_dir = os.path.join(module)
    os.makedirs(log_dir, exist_ok=True)
    if status == 'success':
        log_file = os.path.join(log_dir, f"{now}_success.log")
    else:
        log_file = os.path.join(log_dir, f"{now}_error.log")
    try:
        with open(log_file, 'a', encoding='utf-8') as f:
            f.write(f"账号: {username}\n时间: {now}\n状态: {status}\n结果: {message}\n")
            if error:
                f.write(f"错误原因: {error}\n")
            f.write("-"*30+"\n")
    except Exception as e:
        print(f"❌ 保存任务日志时发生错误: {e}")

# 操作日志保存函数

def save_op_log(module, username, op_type, task_id, status, message, error=None):
    now = get_shanghai_now().strftime('%Y%m%d_%H%M%S')
    log_dir = os.path.join(module)
    os.makedirs(log_dir, exist_ok=True)
    log_file = os.path.join(log_dir, f"{now}_op.log")
    try:
        with open(log_file, 'a', encoding='utf-8') as f:
            f.write(f"操作: {op_type}\n账号: {username}\n任务ID: {task_id}\n时间: {now}\n状态: {status}\n结果: {message}\n")
            if error:
                f.write(f"错误原因: {error}\n")
            f.write("-"*30+"\n")
    except Exception as e:
        print(f"❌ 保存操作日志时发生错误: {e}")

# 定时任务执行器（新逻辑）
class TaskScheduler:
    def __init__(self, application, loop):
        self.application = application
        self.loop = loop
        self.running = False
        self.thread = None

    def start(self):
        if self.running:
            return
        self.running = True
        self.thread = threading.Thread(target=self._scheduler_loop, daemon=True)
        self.thread.start()
        print("✅ 定时任务调度器已启动")

    def stop(self):
        self.running = False
        if self.thread:
            self.thread.join(timeout=5)
        print("⏹️ 定时任务调度器已停止")

    def _scheduler_loop(self):
        while self.running:
            try:
                now = get_shanghai_now()
                tasks = load_scheduled_tasks()
                for task in tasks.values():
                    if not task.get("enabled", True):
                        continue
                    cron_expr = f"{task['minute']} {task['hour']} * * *"
                    cron = croniter(cron_expr, now)
                    next_time = cron.get_next(datetime)
                    if next_time <= now:
                        self._execute_task(task)
                time.sleep(60)
            except Exception as e:
                print(f"❌ 定时任务调度器错误: {e}")
                time.sleep(60)

    def _execute_task(self, task):
        try:
            print(f"🔄 执行定时任务: {task['module']} {task['hour']:02d}:{task['minute']:02d} (用户: {task['user_id']}, 账号: {task['username']})")
            user_id = int(task['user_id'])
            if is_banned(user_id):
                print(f"❌ 用户 {user_id} 已被封禁")
                return
            can_use, usage = check_daily_limit(user_id)
            if not can_use:
                print(f"❌ 用户 {user_id} 已达到每日使用限制")
                return
            module = task['module']
            # 执行签到任务的代码
        except Exception as e:
            print(f"❌ 执行定时任务时发生错误: {e}")
{insert\_element\_2\_CmBgYAoKIyMjIDMuIGBBY2M=}k/q{insert\_element\_3\_aWFuZGFvLnB5YCDlkowgYEFraWw=}e/qiandao.py{insert\_element\_4\_YCDmlofku7bkvJjljJYKCiMjIyMgYEFjYw==}k/qiandao.py`

```python
#!/usr/bin/env python3

import requests
import pyotp
import time
import sys
import os


class Color:
    GREEN = '\033[92m'
    RED = '\033[91m'
    YELLOW = '\033[93m'
    BLUE = '\033[94m'
    CYAN = '\033[96m'
    END = '\033[0m'

def send_telegram_message(token: str, chat_id: str, text: str):
    if not token or not chat_id:
        print(f"{Color.YELLOW}⚠️ Telegram配置未填写，跳过通知{Color.END}")
        return
    url = f"https://api.telegram.org/bot{token}/sendMessage"
    max_retries = 3
    for retry in range(max_retries):
        try:
            resp = requests.post(url, json={"chat_id": chat_id, "text": text}, timeout=20)
            if resp.status_code == 200:
                print(f"{Color.GREEN}✅ Telegram通知发送成功{Color.END}")
                return
            else:
                print(f"{Color.RED}❌ Telegram通知发送失败（第 {retry + 1} 次尝试）: {resp.text}{Color.END}")
        except requests.RequestException as e:
            print(f"{Color.RED}❌ 发送Telegram通知异常（第 {retry + 1} 次尝试）: {e}{Color.END}")
        if retry < max_retries - 1:
            time.sleep(5)
    print(f"{Color.RED}❌ 发送Telegram通知失败，已达到最大重试次数{Color.END}")

class ACCKAccount:
    def __init__(self, email, password, totp_secret=None):
        self.email = email
        self.password = password
        self.totp_secret = totp_secret
        self.session = requests.Session()
        self.token = None
        self._init_headers()

    def _init_headers(self):
        self.session.headers.update({
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                          "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/110.0.0.0 Safari/537.36",
            "Referer": "https://acck.io",
            "Origin": "https://acck.io",
            "Content-Type": "application/json;charset=UTF-8"
        })

    def login(self):
        payload = {
            "email": self.email,
            "password": self.password,
            "token": "",
            "verifyCode": ""
        }
        print(f"{Color.CYAN}ℹ️ 登录账户: {self.email}{Color.END}")
        max_retries = 3
        for retry in range(max_retries):
            try:
                resp = self.session.post("https://api.acck.io/api/v1/user/login", json=payload, timeout=20)
                resp.raise_for_status()
                data = resp.json()

                if data.get("status_code") == 0 and "二步验证" in data.get("status_msg", ""):
                    if not self.totp_secret:
                        raise Exception("需要TOTP但未配置密钥")
                    totp = pyotp.TOTP(self.totp_secret)
                    payload["token"] = totp.now()
                    print(f"{Color.YELLOW}⚠️ 使用TOTP验证码登录中...{Color.END}")
                    resp = self.session.post("https://api.acck.io/api/v1/user/login", json=payload, timeout=20)
                    resp.raise_for_status()
                    data = resp.json()
                    if data.get("status_code") != 0:
                        raise Exception("TOTP验证失败: " + data.get("status_msg", "未知错误"))

                if data.get("status_code") != 0:
                    raise Exception("登录失败: " + data.get("status_msg", "未知错误"))

                self.token = data["data"]["token"]
                print(f"{Color.GREEN}✅ 登录成功，Token: {self.token[:10]}...{Color.END}")
                return
            except requests.RequestException as e:
                print(f"{Color.RED}❌ 登录请求异常（第 {retry + 1} 次尝试）: {e}{Color.END}")
            except (KeyError, ValueError) as e:
                print(f"{Color.RED}❌ 登录数据解析错误（第 {retry + 1} 次尝试）: {e}{Color.END}")
            if retry < max_retries - 1:
                time.sleep(5)
        print(f"{Color.RED}❌ 登录失败，已达到最大重试次数{Color.END}")

    def checkin(self):
        if not self.token:
            raise Exception("未登录，无法签到")

        headers = {"Authorization": self.token}
        max_retries = 3
        for retry in range(max_retries):
            try:
                resp = self.session.get("https://sign-service.acck.io/api/acLogs/sign", headers=headers, timeout=20)
                resp.raise_for_status()
                try:
                    data = resp.json()
                except ValueError:
                    msg = f"签到接口返回非JSON，原始内容：{resp.text}"
                    print(f"{Color.RED}{msg}{Color.END}")
                    return False, msg

                if data.get("code") == 200:
                    msg = f"签到成功: {data.get('msg', '')}"
                    print(f"{Color.GREEN}✅ {msg}{Color.END}")
                    return True, msg
                elif data.get("msg") == "今日已签到":
                    msg = "今日已签到"
                    print(f"{Color.GREEN}ℹ️ 签到状态：{msg}{Color.END}")
                    return True, msg
                else:
                    msg = f"签到失败: {data}"
                    print(f"{Color.RED}❌ {msg}{Color.END}")
                    return False, msg
            except requests.RequestException as e:
                print(f"{Color.RED}❌ 签到请求异常（第 {retry + 1} 次尝试）: {e}{Color.END}")
            if retry < max_retries - 1:
                time.sleep(5)
        print(f"{Color.RED}❌ 签到失败，已达到最大重试次数{Color.END}")
        return False, "签到失败，已达到最大重试次数"

    def get_balance(self):
        if not self.token:
            return None

        headers = {"Authorization": self.token}
        max_retries = 3
        for retry in range(max_retries):
            try:
                resp = self.session.get("https://api.acck.io/api/v1/user/index", headers=headers, timeout=20)
                resp.raise_for_status()
                data = resp.json()
                if data.get("status_code") != 0:
                    msg = f"获取余额失败: {data.get('status_msg', '未知错误')}"
                    print(f"{Color.RED}❌ {msg}{Color.END}")
                    return None

                info = data.get("data", {})
                money = info.get("money", 0)
                try:
                    money = float(money) / 100
                except (TypeError, ValueError):
                    money = 0.0

                ak_coin = info.get("ak_coin", "N/A")
                balance_info = f"AK币: {ak_coin}，现金: ¥{money:.2f}"
                print(f"{Color.BLUE}💰 余额信息 - {balance_info}{Color.END}")
                return balance_info
            except requests.RequestException as e:
                print(f"{Color.RED}❌ 获取余额请求异常（第 {retry + 1} 次尝试）: {e}{Color.END}")
            if retry < max_retries - 1:
                time.sleep(5)
        print(f"{Color.RED}❌ 获取余额失败，已达到最大重试次数{Color.END}")
        return None

def parse_accounts(env_var: str):
    accounts = []
    if not env_var:
        print(f"{Color.RED}❌ 环境变量 ACCK_ACCOUNTS 未设置或为空{Color.END}")
        return accounts

    for idx, acc_str in enumerate(env_var.split("|"), 1):
        parts = acc_str.strip().split(":")
        if len(parts) < 2:
            print(f"{Color.YELLOW}⚠️ 跳过无效账户配置: {acc_str}{Color.END}")
            continue
        email = parts[0]
        password = parts[1]
        totp_secret = parts[2] if len(parts) > 2 else None
        accounts.append({"email": email, "password": password, "totp_secret": totp_secret})
    return accounts

def main(email, password, totp=None):
    try:
        acc = ACCKAccount(email, password, totp)
        acc.login()
        ok, msg = acc.checkin()
        balance = acc.get_balance()
        result = f"签到结果: {'成功' if ok else '失败'}\n信息: {msg}"
        if balance:
            result += f"\n{balance}"
        return result
    except Exception as e:
        return f"执行出错: {e}"

# 如需测试请在bot.py中调用main，不建议直接运行本{insert\_element\_5\_5paH5Lu2CgpgYGAKCiMjIyMgYEFraQ==}le/qiandao.py`

```python
#!/usr/bin/env python3

import os
import time
import pyotp
from curl_cffi import requests
from dotenv import load_dotenv
from typing import Dict, List, Optional, Tuple

# 初始化环境变量
load_dotenv()

class Color:
    """控制台颜色"""
    GREEN = '\033[92m'
    RED = '\033[91m'
    YELLOW = '\033[93m'
    BLUE = '\033[94m'
    CYAN = '\033[96m'
    END = '\033[0m'

class AkileSession:
    """独立会话环境"""
    def __init__(self):
        self.session = requests.Session(
            impersonate="chrome110",
            allow_redirects=False
        )
        self._init_headers()
        self.session.cookies.clear()
        
    def _init_headers(self):
        self.session.headers = {
            "Host": "api.akile.io",
            "Accept": "application/json, text/plain, */*",
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36",
            "Referer": "https://akile.io/",
            "Origin": "https://akile.io",
            "Content-Type": "application/json;charset=UTF-8"
        }

class AkileAccount:
    def __init__(self, email: str, password: str, totp_secret: str = None):
        self.email = email
        self.password = password
        self.totp_secret = totp_secret
        self.session = AkileSession().session
        
    def login(self) -> Tuple[Optional[str], Optional[str]]:
        """登录流程"""
        max_retries = 3
        for retry in range(max_retries):
            try:
                payload = {
                    "email": self.email,
                    "password": self.password,
                    "token": "",
                    "verifyCode": ""
                }
                
                print(f"{Color.CYAN} 登录账号: {self.email}{Color.END}")
                response = self.session.post(
                    "https://api.akile.io/api/v1/user/login",
                    json=payload,
                    timeout=20
                )
                response.raise_for_status()
                data = response.json()
                
                # TOTP验证
                if data.get("status_code") == 0 and "二步验证" in data.get("status_msg", ""):
                    if not self.totp_secret:
                        return None, "需要TOTP但未配置密钥"
                    
                    totp = pyotp.TOTP(self.totp_secret)
                    payload["token"] = totp.now()
                    print(f"{Color.YELLOW} 生成TOTP验证码{Color.END}")
                    
                    verify_response = self.session.post(
                        "https://api.akile.io/api/v1/user/login",
                        json=payload,
                        timeout=20
                    )
                    verify_response.raise_for_status()
                    verify_data = verify_response.json()
                    
                    if verify_data.get("status_code") == 0:
                        return verify_data.get("data", {}).get("token"), None
                    return None, verify_data.get("status_msg", "TOTP验证失败")
                
                if data.get("status_code") == 0:
                    return data.get("data", {}).get("token"), None
                    
                return None, data.get("status_msg", "登录失败")
            except requests.RequestException as e:
                print(f"{Color.RED}❌ 登录请求异常（第 {retry + 1} 次尝试）: {e}{Color.END}")
            except (KeyError, ValueError) as e:
                print(f"{Color.RED}❌ 登录数据解析错误（第 {retry + 1} 次尝试）: {e}{Color.END}")
            if retry < max_retries - 1:
                time.sleep(5)
        return None, "登录失败，已达到最大重试次数"

    def get_real_balance(self, token: str) -> Dict:
        """获取真实余额信息（自动转换单位为元）"""
        max_retries = 3
        for retry in range(max_retries):
            try:
                headers = {"Authorization": token}
                response = self.session.get(
                    "https://api.akile.io/api/v1/user/index",
                    headers=headers,
                    timeout=20
                )
                response.raise_for_status()
                data = response.json()
                
                if data.get("status_code") != 0:
                    return {"error": "获取余额失败: " + data.get("status_msg", "未知错误")}
                    
                balance_data = data.get("data", {})
                
                # 转换现金单位为元（除以100）
                money = balance_data.get("money", 0)
                try:
                    money_yuan = float(money) / 100
                except (TypeError, ValueError):
                    money_yuan = 0.0
                    
                return {
                    "ak_coin": balance_data.get("ak_coin", "N/A"),
                    "money": f"{money_yuan:.2f}",  # 保留两位小数
                    "raw_data": balance_data
                }
            except requests.RequestException as e:
                print(f"{Color.RED}❌ 获取余额请求异常（第 {retry + 1} 次尝试）: {e}{Color.END}")
            except (KeyError, ValueError) as e:
                print(f"{Color.RED}❌ 获取余额数据解析错误（第 {retry + 1} 次尝试）: {e}{Color.END}")
            if retry < max_retries - 1:
                time.sleep(5)
        return {"error": "获取余额失败，已达到最大重试次数"}

    def checkin(self, token: str) -> Tuple[bool, str]:
        """执行签到"""
        max_retries = 3
        for retry in range(max_retries):
            try:
                headers = {"Authorization": token}
                response = self.session.get(
                    "https://api.akile.io/api/v1/user/Checkin",
                    headers=headers,
                    timeout=20
                )
                response.raise_for_status()
                data = response.json()
                
                if data.get("status_code") == 0 or "已签到" in data.get("status_msg", ""):
                    return True, data.get("status_msg", "签到成功")
                return False, data.get("status_msg", "签到失败")
            except requests.RequestException as e:
                print(f"{Color.RED}❌ 签到请求异常（第 {retry + 1} 次尝试）: {e}{Color.END}")
            except (KeyError, ValueError) as e:
                print(f"{Color.RED}❌ 签到数据解析错误（第 {retry + 1} 次尝试）: {e}{Color.END}")
            if retry < max_retries - 1:
                time.sleep(5)
        return False, "签到失败，已达到最大重试次数"

class AccountManager:
    def __init__(self):
        self.accounts = self._load_accounts()
        
    def _parse_accounts(self, config_str: str) -> List[Dict]:
        """解析多账户配置字符串"""
        accounts = []
        # 用 | 分隔不同账户
        account_strings = config_str.split("|")
        
        for i, acc_str in enumerate(account_strings, 1):
            if not acc_str.strip():
                continue
                
            # 用 : 分隔账户信息
            parts = acc_str.split(":")
            if len(parts) < 2:
                print(f"{Color.YELLOW} 忽略无效账号配置: {acc_str}{Color.END}")
                continue
                
            email = parts[0].strip()
            password = parts[1].strip()
            totp_secret = parts[2].strip() if len(parts) > 2 else None
            
            accounts.append({
                "name": f"账号{i}",
                "email": email,
                "password": password,
                "totp_secret": totp_secret
            })
            
        return accounts
        
    def _load_accounts(self) -> Dict[str, Dict]:
        """从环境变量加载所有账户"""
        # 从 AKILE_ACCOUNTS 环境变量读取配置
        config_str = os.getenv("AKILE_ACCOUNTS", "")
        if not config_str:
            print(f"{Color.RED} 未配置AKILE_ACCOUNTS环境变量{Color.END}")
            return {}
            
        return {acc["name"]: acc for acc in self._parse_accounts(config_str)}
    
    def run(self):
        if not self.accounts:
            print(f"{Color.RED} 未找到有效账号配置{Color.END}")
            return

        print(f"{Color.YELLOW} 发现 {len(self.accounts)} 个账号{Color.END}")

        for name, acc in self.accounts.items():
            print(f"\n{Color.CYAN} ➤ 处理 {name}{Color.END}")
            
            account = AkileAccount(
                email=acc["email"],
                password=acc["password"],
                totp_secret=acc.get("totp_secret")
            )
            
            # 登录
            token, error = account.login()
            if error:
                print(f"{Color.RED} 登录失败: {error}{Color.END}")
                continue
                
            print(f"{Color.GREEN} 登录成功{Color.END}")
            
            # 签到
            success, msg = account.checkin(token)
            if success:
                print(f"{Color.GREEN} {msg}{Color.END}")
            else:
                print(f"{Color.RED} 签到失败: {msg}{Color.END}")
            
            # 获取并显示真实余额
            balance = account.get_real_balance(token)
            if "error" in balance:
                print(f"{Color.RED} {balance['error']}{Color.END}")
                print(f"{Color.YELLOW} 原始响应: {balance.get('raw_data', '无')}{Color.END}")
            else:
                print(f"{Color.BLUE} 💰 真实账号余额:")
                print(f"   AK币: {balance['ak_coin']}")
                print(f"   现金: ￥{balance['money']}")
            
            time.sleep(1)

def main(email, password, totp_secret=None):
    try:
        acc = AkileAccount(email, password, totp_secret)
        token, err = acc.login()
        if not token:
            return f"登录失败: {err}"
        ok, msg = acc.checkin(token)
        balance = acc.get_real_balance(token)
        result = f"签到结果: {'成功' if ok else '失败'}\n信息: {msg}"
        # 格式化余额信息
        if isinstance(balance, dict) and "ak_coin" in balance and "money" in balance:
            result += f"\nAK币: {balance['ak_coin']}，现金: ¥{balance['money']}"
        elif isinstance(balance, dict) and "error" in balance:
            result += f"\n{balance['error']}"
        return result
    except Exception as e:
        return f"执行出错: {e}"

# 如需测试请在bot.py中调用main，不建议直接运行本文件