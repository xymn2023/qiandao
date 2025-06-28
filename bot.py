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
        with open(filename, "r", encoding="utf-8") as f:
            return json.load(f)
    return default

def save_json(filename, data):
    with open(filename, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

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

def is_allowed(user_id):
    return is_admin(user_id) or user_id in load_allowed_users()

def is_banned(user_id):
    return user_id in load_banned_users()

# 每日次数限制

def get_daily_limit():
    stats = load_json("limit_config.json", {})
    return stats.get("limit", DEFAULT_DAILY_LIMIT)

def check_daily_limit(user_id):
    if is_admin(user_id):
        return True, 0
    today = date.today().isoformat()
    usage_data = load_daily_usage()
    if today not in usage_data:
        usage_data[today] = {}
    user_usage = usage_data[today].get(str(user_id), 0)
    return user_usage < get_daily_limit(), user_usage

def increment_daily_usage(user_id):
    if is_admin(user_id):
        return
    today = date.today().isoformat()
    usage_data = load_daily_usage()
    if today not in usage_data:
        usage_data[today] = {}
    if str(user_id) not in usage_data[today]:
        usage_data[today][str(user_id)] = 0
    usage_data[today][str(user_id)] += 1
    save_daily_usage(usage_data)

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
    with open(log_file, 'a', encoding='utf-8') as f:
        f.write(f"账号: {username}\n时间: {now}\n状态: {status}\n结果: {message}\n")
        if error:
            f.write(f"错误原因: {error}\n")
        f.write("-"*30+"\n")

# 操作日志保存函数

def save_op_log(module, username, op_type, task_id, status, message, error=None):
    now = get_shanghai_now().strftime('%Y%m%d_%H%M%S')
    log_dir = os.path.join(module)
    os.makedirs(log_dir, exist_ok=True)
    log_file = os.path.join(log_dir, f"{now}_op.log")
    with open(log_file, 'a', encoding='utf-8') as f:
        f.write(f"操作: {op_type}\n账号: {username}\n任务ID: {task_id}\n时间: {now}\n状态: {status}\n结果: {message}\n")
        if error:
            f.write(f"错误原因: {error}\n")
        f.write("-"*30+"\n")

# 定时任务执行器（新逻辑）
class TaskScheduler:
    def __init__(self, application):
        self.application = application
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
                    if now.hour == task["hour"] and now.minute == task["minute"]:
                        self._execute_task(task)
                time.sleep(60)
            except Exception as e:
                print(f"❌ 定时任务调度器错误: {e}")
                time.sleep(60)
    def _execute_task(self, task):
        try:
            print(f"🔄 执行定时任务: {task['module']} {task['hour']:02d}:{task['minute']:02d} (用户: {task['user_id']}, 账号: {task['username']})")
            user_id = int(task['user_id'])
            if not is_allowed(user_id):
                print(f"❌ 用户 {user_id} 无权限执行任务")
                return
            can_use, usage = check_daily_limit(user_id)
            if not can_use:
                print(f"❌ 用户 {user_id} 已达到每日使用限制")
                return
            module = task['module']
            username = task['username']
            user_file = os.path.join(module, 'users', f"{username}.json")
            if not os.path.exists(user_file):
                err_msg = f"❌ 用户 {user_id} 的 {module} 账号 {username} 凭证不存在"
                print(err_msg)
                save_task_log(module, username, 'error', '凭证不存在', error=err_msg)
                asyncio.run_coroutine_threadsafe(
                    self.application.bot.send_message(
                        chat_id=user_id,
                        text=err_msg,
                        parse_mode=ParseMode.HTML
                    ),
                    self.application.loop
                )
                return
            with open(user_file, 'r', encoding='utf-8') as f:
                user_info = json.load(f)
            try:
                if module == 'Acck':
                    result = acck_signin(user_info['username'], user_info['password'], user_info.get('totp'))
                elif module == 'Akile':
                    result = akile_signin(user_info['username'], user_info['password'], user_info.get('totp'))
                else:
                    raise Exception(f"未知模块: {module}")
                increment_daily_usage(user_id)
                record_usage(user_id)
                task['last_run'] = get_shanghai_now().isoformat()
                save_scheduled_tasks(load_scheduled_tasks())
                status = "success" if ("成功" in result or "已签到" in result) else "error"
                message = f"🕐 定时任务执行结果\n\n平台: {module}\n账号: {username}\n时间: {task['hour']:02d}:{task['minute']:02d}\n状态: {'✅ 成功' if status=='success' else '❌ 失败'}\n结果: {result}"
                save_task_log(module, username, status, result)
                asyncio.run_coroutine_threadsafe(
                    self.application.bot.send_message(
                        chat_id=user_id,
                        text=message,
                        parse_mode=ParseMode.HTML
                    ),
                    self.application.loop
                )
                print(f"✅ 定时任务执行完成: {task['module']} {task['hour']:02d}:{task['minute']:02d} 账号: {username}")
            except Exception as e:
                err_msg = f"❌ 执行定时任务错误 {task['id']}: {e}"
                save_task_log(module, username, 'error', '执行任务异常', error=str(e))
                asyncio.run_coroutine_threadsafe(
                    self.application.bot.send_message(
                        chat_id=user_id,
                        text=err_msg,
                        parse_mode=ParseMode.HTML
                    ),
                    self.application.loop
                )
                print(err_msg)
        except Exception as e:
            print(f"❌ 执行定时任务错误 {task['id']}: {e}")

task_scheduler = None

# 用户解绑

def unbind_user(user_id):
    for module in ["Acck", "Akile"]:
        users_dir = os.path.join(module, 'users')
        user_file = os.path.join(users_dir, f"{user_id}.json")
        if os.path.exists(user_file):
            os.remove(user_file)

# 状态定义
SELECT_MODULE, INPUT_USERNAME, INPUT_PASSWORD, INPUT_TOTP = range(4)
INPUT_SCHEDULE_NAME, INPUT_SCHEDULE_CRON, INPUT_SCHEDULE_CONFIRM = range(4, 7)

# 主菜单
main_menu = [['acck签到', 'akile签到'], ['🕐 定时任务', '📊 我的统计']]

# 各模块对应的目录和函数
MODULES = {
    'acck签到': ('Acck', acck_signin),
    'akile签到': ('Akile', akile_signin),
    'Acck': ('Acck', acck_signin),
    'Akile': ('Akile', akile_signin),
}

# 记录用户当前操作的模块
user_module = {}

# 全局定时任务调度器
task_scheduler = None

def get_bot_owner_id(token):
    """获取Bot创建者的用户ID"""
    try:
        url = f"https://api.telegram.org/bot{token}/getMe"
        response = requests.get(url, timeout=10)
        if response.status_code == 200:
            bot_info = response.json()
            if bot_info.get('ok'):
                print(f"✅ Bot信息验证成功: {bot_info['result']['first_name']} (@{bot_info['result']['username']})")
                # 由于Telegram API限制，无法直接获取Bot创建者
                # 我们使用配置的Chat ID进行验证
                return None
        return None
    except Exception as e:
        print(f"获取Bot信息失败: {e}")
        return None

def verify_bot_owner(token, chat_id):
    """验证Bot Token和Chat ID的匹配性"""
    try:
        # 获取Bot信息
        url = f"https://api.telegram.org/bot{token}/getMe"
        response = requests.get(url, timeout=10)
        if response.status_code != 200:
            return False, "无法获取Bot信息"
        
        bot_info = response.json()
        if not bot_info.get('ok'):
            return False, "Bot Token无效"
        
        bot_name = bot_info['result']['first_name']
        bot_username = bot_info['result']['username']
        
        # 尝试发送测试消息到指定Chat ID
        test_url = f"https://api.telegram.org/bot{token}/sendMessage"
        test_data = {
            "chat_id": chat_id,
            "text": "Bot验证测试消息"
        }
        
        test_response = requests.post(test_url, json=test_data, timeout=10)
        if test_response.status_code == 200:
            test_result = test_response.json()
            if test_result.get('ok'):
                # 删除测试消息
                if 'result' in test_result and 'message_id' in test_result['result']:
                    delete_url = f"https://api.telegram.org/bot{token}/deleteMessage"
                    delete_data = {
                        "chat_id": chat_id,
                        "message_id": test_result['result']['message_id']
                    }
                    requests.post(delete_url, json=delete_data, timeout=5)
                return True, f"验证成功 - Bot: {bot_name} (@{bot_username})"
            else:
                return False, f"无法发送消息到Chat ID: {test_result.get('description', '未知错误')}"
        else:
            return False, f"API请求失败: {test_response.status_code}"
            
    except Exception as e:
        return False, f"验证过程出错: {e}"

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if update.effective_chat.type != 'private':
        await update.message.reply_text("请在与Bot的私聊中使用本功能。")
        return ConversationHandler.END
    user_id = update.effective_user.id
    TOKEN = TELEGRAM_BOT_TOKEN
    CHAT_ID = TELEGRAM_CHAT_ID
    if TOKEN == '在这里填写你的Bot Token' and CHAT_ID == '在这里填写你的Chat ID':
        pass
    elif TOKEN == '在这里填写你的Bot Token' or CHAT_ID == '在这里填写你的Chat ID':
        await update.message.reply_text("Bot Token或Chat ID配置错误，请联系管理员。")
        return ConversationHandler.END
    is_valid, message = verify_bot_owner(TOKEN, CHAT_ID)
    if not is_valid:
        await update.message.reply_text(f"验证失败：{message}")
        return ConversationHandler.END
    if not is_allowed(user_id):
        await update.message.reply_text("您不是此Bot的管理员或授权用户，请联系管理员授权后再使用。")
        return ConversationHandler.END
    can_use, current_usage = check_daily_limit(user_id)
    if not can_use:
        await update.message.reply_text(f"今日使用次数已达上限（{get_daily_limit()}次），您已使用{current_usage}次，请明天再试。")
        return ConversationHandler.END
    
    # 发送启动欢迎消息
    welcome_msg = f"""🤖 **签到机器人已启动！**

👋 欢迎使用自动签到系统
🆔 您的用户ID：`{user_id}`
📊 今日剩余次数：{get_daily_limit() - current_usage}/{get_daily_limit()}

**可用命令：**
• `/acck` - Acck平台签到
• `/akile` - Akile平台签到  
• `/add` - 添加定时任务
• `/del` - 删除定时任务
• `/all` - 查看所有定时任务
• `/me` - 查看个人信息
• `/help` - 查看帮助信息

**快速开始：**
请选择要签到的平台，或直接使用 `/acck` 或 `/akile` 命令开始签到。

---
💡 机器人状态：✅ 正常运行中"""
    
    await update.message.reply_text(welcome_msg, parse_mode=ParseMode.MARKDOWN, reply_markup=ReplyKeyboardRemove())
    
    # 直接提示输入平台
    await update.message.reply_text(
        f"请输入要签到的平台(acck签到 或 akile签到)：",
        reply_markup=ReplyKeyboardRemove()
    )
    return SELECT_MODULE

async def select_module(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if update.effective_chat.type != 'private':
        await send_md(update.message.reply_text, "请在与Bot的私聊中使用本功能。", reply_markup=ReplyKeyboardRemove())
        return ConversationHandler.END
    user_id = update.effective_user.id
    if not is_allowed(user_id):
        await send_md(update.message.reply_text, "您不是此Bot的管理员或授权用户，请联系管理员授权后再使用。", reply_markup=ReplyKeyboardRemove())
        return ConversationHandler.END
    can_use, current_usage = check_daily_limit(user_id)
    if not can_use:
        await send_md(update.message.reply_text, f"今日使用次数已达上限（{get_daily_limit()}次），您已使用{current_usage}次，请明天再试。", reply_markup=ReplyKeyboardRemove())
        return ConversationHandler.END
    text = update.message.text
    if text not in MODULES:
        await send_md(update.message.reply_text, "请输入平台名称：acck签到 或 akile签到。", reply_markup=ReplyKeyboardRemove())
        return SELECT_MODULE
    user_module[user_id] = text
    await send_md(update.message.reply_text, "请输入账号：", reply_markup=ReplyKeyboardRemove())
    return INPUT_USERNAME

async def input_username(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if update.effective_chat.type != 'private':
        await send_md(update.message.reply_text, "请在与Bot的私聊中使用本功能。"); return ConversationHandler.END
    user_id = update.effective_user.id
    if not is_allowed(user_id):
        await send_md(update.message.reply_text, "您不是此Bot的管理员或授权用户，请联系管理员授权后再使用。"); return ConversationHandler.END
    context.user_data['username'] = update.message.text
    context.user_data['password'] = ''
    context.user_data['totp'] = ''
    await send_md(update.message.reply_text, "请输入密码：", reply_markup=ReplyKeyboardRemove())
    return INPUT_PASSWORD

async def input_password(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if update.effective_chat.type != 'private':
        await send_md(update.message.reply_text, "请在与Bot的私聊中使用本功能。")
        return ConversationHandler.END
    user_id = update.effective_user.id
    if not is_allowed(user_id):
        await send_md(update.message.reply_text, "您不是此Bot的管理员或授权用户，请联系管理员授权后再使用。")
        return ConversationHandler.END
    context.user_data['password'] = update.message.text
    await send_md(update.message.reply_text, "是否有TOTP二步验证？有请输入验证码，没有请回复'无'：", reply_markup=ReplyKeyboardRemove())
    return INPUT_TOTP

async def input_totp(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if update.effective_chat.type != 'private':
        await update.message.reply_text("请在与Bot的私聊中使用本功能。")
        return ConversationHandler.END
    user_id = update.effective_user.id
    if not is_allowed(user_id):
        await update.message.reply_text("您不是此Bot的管理员或授权用户，请联系管理员授权后再使用。"); return ConversationHandler.END
    
    totp = update.message.text.strip()
    context.user_data['totp'] = totp if totp != '无' else ''
    
    module_key = user_module.get(user_id)
    module_dir, module_func = MODULES[module_key]
    
    save_user_info(user_id, module_dir, {
        'username': context.user_data['username'],
        'password': context.user_data['password'],
        'totp': context.user_data['totp']
    })
    
    try:
        result = module_func(
            context.user_data['username'],
            context.user_data['password'],
            context.user_data['totp']
        )
    except Exception as e:
        result = f"执行出错：{e}"
        
    increment_daily_usage(user_id)
    record_usage(user_id)
    
    _, new_usage = check_daily_limit(user_id)
    
    if str(user_id) == str(TELEGRAM_CHAT_ID):
        result_msg = f"{module_dir} 执行结果：\n{result}"
    else:
        result_msg = f"{module_dir} 执行结果：\n{result}\n\n今日已使用：{new_usage}/{get_daily_limit()}次"
        
    await update.message.reply_text(result_msg, reply_markup=ReplyKeyboardRemove())
    
    # 清理本次会话的用户数据
    context.user_data.clear()
    
    await update.message.reply_text(
        "签到完成。如需再次签到，请使用 /acck 或 /akile 命令。使用 /cancel 可随时退出操作。",
        reply_markup=ReplyKeyboardRemove()
    )
    
    return ConversationHandler.END

async def cancel(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text('操作已取消。')
    return ConversationHandler.END

# 管理员授权命令
async def allow_user(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user_id = update.effective_user.id
    if not check_admin_and_warn(update, user_id, 'allow'):
        return
    if not context.args:
        await update.message.reply_text("用法：/allow <用户ID>")
        return
    try:
        target_id = int(context.args[0])
    except Exception:
        await update.message.reply_text("用户ID格式错误。")
        return
    allowed_users = load_allowed_users()
    allowed_users.add(target_id)
    save_allowed_users(allowed_users)
    await update.message.reply_text(f"已授权用户 {target_id} 使用Bot。")
    log_admin_action_daily(user_id, 'allow', context.args, f"授权用户 {target_id}")

# ========== 用户自助命令 ==========
async def me_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user_id = update.effective_user.id
    
    # 检查是否是首次使用（通过检查是否有启动提示记录）
    if not context.user_data.get('bot_started'):
        context.user_data['bot_started'] = True
        status_msg = f"""🤖 **机器人状态确认**

✅ 机器人正常运行中
🆔 用户ID：`{user_id}`
🎯 当前操作：查看个人信息

---
💡 机器人已准备就绪，开始处理您的请求..."""
        await update.message.reply_text(status_msg, parse_mode=ParseMode.MARKDOWN, reply_markup=ReplyKeyboardRemove())
    
    status = []
    if is_admin(user_id):
        status.append("身份：管理员")
    elif is_banned(user_id):
        status.append("身份：黑名单用户")
    elif is_allowed(user_id):
        status.append("身份：白名单用户")
    else:
        status.append("身份：未授权用户")
    can_use, current_usage = check_daily_limit(user_id)
    status.append(f"今日已用：{current_usage}/{get_daily_limit()}次")
    stats_all = load_usage_stats() or {}
    stats = stats_all.get(str(user_id), {})
    count = stats.get("count", 0)
    last = stats.get("last", "无记录")
    
    # 兼容并格式化旧的时间格式
    if last != "无记录":
        try:
            # 尝试解析ISO格式
            last_dt = datetime.fromisoformat(last)
            last = last_dt.strftime('%Y-%m-%d %H:%M:%S')
        except ValueError:
            # 如果已经是新格式或其他格式，则直接使用
            pass
            
    status.append(f"累计签到：{count} 次")
    status.append(f"最后签到时间：{last}")
    await update.message.reply_text("\n".join(status), reply_markup=ReplyKeyboardRemove())

async def unbind_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user_id = update.effective_user.id
    unbind_user(user_id)
    await update.message.reply_text("您的所有账号信息已清除。", reply_markup=ReplyKeyboardRemove())

# ========== 管理员命令 ==========
async def ban_user(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user_id = update.effective_user.id
    if not is_admin(user_id):
        await update.message.reply_text("只有管理员才能封禁用户。")
        return
    if not context.args:
        await update.message.reply_text("用法：/ban <用户ID>")
        return
    try:
        target_id = int(context.args[0])
    except Exception:
        await update.message.reply_text("用户ID格式错误。")
        return
    banned = load_banned_users()
    banned.add(target_id)
    save_banned_users(banned)
    log_admin_action("ban", f"封禁用户 {target_id}")
    await update.message.reply_text(f"已封禁用户 {target_id}", reply_markup=ReplyKeyboardRemove())

async def unban_user(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user_id = update.effective_user.id
    if not check_admin_and_warn(update, user_id, 'unban'):
        return
    if not context.args:
        await update.message.reply_text("用法：/unban <用户ID>")
        return
    try:
        target_id = int(context.args[0])
    except Exception:
        await update.message.reply_text("用户ID格式错误。")
        return
    banned = load_banned_users()
    if target_id in banned:
        banned.remove(target_id)
        save_banned_users(banned)
        log_admin_action("unban", f"解封用户 {target_id}")
        log_admin_action_daily(user_id, 'unban', context.args, f"解封用户 {target_id}")
        await update.message.reply_text(f"已解封用户 {target_id}", reply_markup=ReplyKeyboardRemove())
    else:
        await update.message.reply_text(f"用户 {target_id} 不在黑名单。", reply_markup=ReplyKeyboardRemove())

async def disallow_user(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user_id = update.effective_user.id
    if not is_admin(user_id):
        await update.message.reply_text("只有管理员才能移除白名单用户。")
        return
    if not context.args:
        await update.message.reply_text("用法：/disallow <用户ID>")
        return
    try:
        target_id = int(context.args[0])
    except Exception:
        await update.message.reply_text("用户ID格式错误。")
        return
    allowed = load_allowed_users()
    if target_id in allowed:
        allowed.remove(target_id)
        save_allowed_users(allowed)
        log_admin_action("disallow", f"移除白名单用户 {target_id}")
        await update.message.reply_text(f"已移除白名单用户 {target_id}", reply_markup=ReplyKeyboardRemove())
    else:
        await update.message.reply_text(f"用户 {target_id} 不在白名单。", reply_markup=ReplyKeyboardRemove())

async def stats_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user_id = update.effective_user.id
    if not is_admin(user_id):
        await send_md(update.message.reply_text, "只有管理员才能查看统计。", reply_markup=ReplyKeyboardRemove())
        return
    stats = load_usage_stats() or {}
    if not stats:
        await send_md(update.message.reply_text, "暂无任何用户统计数据。", reply_markup=ReplyKeyboardRemove())
        return
    
    msg = ["`用户ID         | 累计 | 最后签到时间`"]
    for uid, info in stats.items():
        count = info.get('count', 0)
        last = info.get('last', '无')
        
        # 兼容并格式化旧的时间格式
        if last != "无":
            try:
                # 尝试解析ISO格式
                last_dt = datetime.fromisoformat(last)
                last = last_dt.strftime('%Y-%m-%d %H:%M:%S')
            except ValueError:
                # 如果已经是新格式或其他格式，则直接使用
                pass
                
        msg.append(f"`{uid:<14}` | *{count:<4}* | `{last}`")
        
    await send_md(update.message.reply_text, "\n".join(msg), reply_markup=ReplyKeyboardRemove())

async def top_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user_id = update.effective_user.id
    if not is_admin(user_id):
        await update.message.reply_text("只有管理员才能查看排行。")
        return
    stats = load_usage_stats() or {}
    top_users = sorted(stats.items(), key=lambda x: x[1].get('count', 0), reverse=True)[:10]
    
    if not top_users:
        await update.message.reply_text("暂无任何用户排行数据。")
        return
        
    msg = ["*活跃用户排行 (前10)*"]
    for i, (uid, info) in enumerate(top_users, 1):
        msg.append(f"`{i}`. `{uid}` - *{info.get('count', 0)}* 次")
    await send_md(update.message.reply_text, "\n".join(msg), reply_markup=ReplyKeyboardRemove())

async def broadcast_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user_id = update.effective_user.id
    if not check_admin_and_warn(update, user_id, 'broadcast'):
        return
    if not context.args:
        await update.message.reply_text("用法：/broadcast <内容>")
        return
    msg = " ".join(context.args)
    allowed = load_allowed_users()
    for uid in allowed:
        try:
            await context.bot.send_message(chat_id=uid, text=f"[管理员广播]\n{msg}")
        except Exception:
            pass
    now = get_shanghai_now()
    log_file = f"broadcast_{now.strftime(LOG_TIME_FMT)}.txt"
    with open(log_file, "a", encoding="utf-8") as f:
        f.write(f"{now.isoformat()} 管理员{user_id} 广播: {msg}\n")
    await update.message.reply_text(f"广播已发送，记录于{log_file}。", reply_markup=ReplyKeyboardRemove())
    log_admin_action_daily(user_id, 'broadcast', context.args, f"广播内容见{log_file}")

async def export_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user_id = update.effective_user.id
    if not check_admin_and_warn(update, user_id, 'export'):
        return
    stats = load_usage_stats()
    allowed = list(load_allowed_users())
    banned = list(load_banned_users())
    export = {
        "stats": stats,
        "allowed": allowed,
        "banned": banned
    }
    now = get_shanghai_now()
    export_file = f"export_{now.strftime(LOG_TIME_FMT)}.json"
    with open(export_file, "w", encoding="utf-8") as f:
        json.dump(export, f, ensure_ascii=False, indent=2)
    await update.message.reply_text(f"数据已导出到 {export_file}。", reply_markup=ReplyKeyboardRemove())
    log_admin_action_daily(user_id, 'export', [], f"导出到{export_file}")

async def setlimit_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user_id = update.effective_user.id
    if not is_admin(user_id):
        await update.message.reply_text("只有管理员才能设置次数上限。")
        return
    if not context.args:
        await update.message.reply_text("用法：/setlimit <次数>")
        return
    try:
        limit = int(context.args[0])
        save_json("limit_config.json", {"limit": limit})
        await update.message.reply_text(f"已设置每日签到次数上限为 {limit} 次。", reply_markup=ReplyKeyboardRemove())
        log_admin_action("setlimit", f"设置每日签到次数上限为 {limit}")
    except Exception:
        await update.message.reply_text("参数错误。")

async def restart_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user_id = update.effective_user.id
    if not is_admin(user_id):
        await update.message.reply_text("只有管理员才能重启Bot。")
        return
    await update.message.reply_text("Bot正在重启...", reply_markup=ReplyKeyboardRemove())
    log_admin_action("restart", "管理员触发重启")
    # 创建重启标记文件
    with open('.restarting', 'w') as f:
        f.write('restarting')
    python = sys.executable
    script = os.path.abspath(__file__)
    os.execv(python, [python, script])

async def shutdown_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user_id = update.effective_user.id
    if not is_admin(user_id):
        await update.message.reply_text("只有管理员才能关闭Bot。")
        return
    await update.message.reply_text("Bot即将关闭...", reply_markup=ReplyKeyboardRemove())
    log_admin_action("shutdown", "关闭Bot")
    os._exit(0)

# ========== 帮助命令 ==========
async def help_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    help_text = (
        "签到Bot命令说明：\n"
        "/acck - 进入 Acck 签到流程\n"
        "/akile - 进入 Akile 签到流程\n"
        "/me - 查询我的状态和统计\n"
        "/unbind - 注销/解绑我的账号信息\n"
        "/help - 显示本帮助\n"
        "/cancel - 取消当前操作\n"
        "\n管理员专用：\n"
        "/allow <用户ID> - 授权用户（加入白名单）\n"
        "/disallow <用户ID> - 移除白名单\n"
        "/ban <用户ID> - 封禁用户（加入黑名单）\n"
        "/unban <用户ID> - 解封用户\n"
        "/stats - 查看所有用户使用统计\n"
        "/top - 查看活跃用户排行\n"
        "/broadcast <内容> - 向所有用户广播消息\n"
        "/export - 导出所有数据\n"
        "/setlimit <次数> - 设置每日签到次数上限\n"
        "/restart - 重启Bot\n"
        "/shutdown - 关闭Bot\n"
        "/menu - 获取/刷新命令菜单\n"
    )
    await update.message.reply_text(help_text, reply_markup=ReplyKeyboardRemove())

# ========== 注册命令 ==========

async def menu_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user_id = update.effective_user.id
    if not is_admin(user_id):
        await update.message.reply_text("只有管理员才能设置Bot命令菜单。")
        return
    all_commands = [
        ("acck", "Acck签到"),
        ("akile", "Akile签到"),
        ("me", "查询我的状态和统计"),
        ("unbind", "注销/解绑账号信息"),
        ("help", "帮助说明"),
        ("allow", "授权用户"),
        ("disallow", "移除白名单"),
        ("ban", "封禁用户"),
        ("unban", "解封用户"),
        ("stats", "使用统计"),
        ("top", "活跃排行"),
        ("broadcast", "广播消息"),
        ("export", "导出数据"),
        ("setlimit", "设置每日次数"),
        ("restart", "重启Bot"),
        ("shutdown", "关闭Bot"),
        ("menu", "获取/刷新命令菜单")
    ]
    await context.bot.set_my_commands(
        [BotCommand(cmd, desc) for cmd, desc in all_commands]
    )
    botfather_text = '\n'.join([f'/{cmd} - {desc}' for cmd, desc in all_commands])
    await update.message.reply_text(
        "✅ 已自动为Bot设置命令菜单！所有用户输入 / 均可见全部命令（Telegram API限制）。\n\n"
        "如需手动设置，也可复制以下内容粘贴到BotFather：\n\n"
        f"{botfather_text}",
        reply_markup=ReplyKeyboardRemove()
    )

# ========== 非管理员尝试管理命令计数与自动拉黑 ==========
def record_admin_attempt(user_id, command):
    data = load_json(ADMIN_ATTEMPT_FILE, {})
    today = date.today().isoformat()
    key = f"{user_id}_{today}"
    if key not in data:
        data[key] = {"count": 0, "last": []}
    data[key]["count"] += 1
    data[key]["last"].append(command)
    save_json(ADMIN_ATTEMPT_FILE, data)
    return data[key]["count"]

def check_admin_and_warn(update, user_id, command):
    if not is_admin(user_id):
        count = record_admin_attempt(user_id, command)
        if count >= 3:
            banned = load_banned_users()
            banned.add(user_id)
            save_banned_users(banned)
            update.message.reply_text(f"你不是管理员，已被自动拉黑。请勿反复尝试管理命令。", reply_markup=ReplyKeyboardRemove())
        else:
            update.message.reply_text(f"你不是管理员，无权使用此命令。警告 {count}/3，超过3次将被拉黑。", reply_markup=ReplyKeyboardRemove())
        return False
    return True

# ========== 管理员操作日志 ========== 
def log_admin_action_daily(user_id, command, args, result):
    now = get_shanghai_now()
    log_file = f"admin_log_{now.strftime(LOG_TIME_FMT)}.json"
    logs = load_json(log_file, [])
    logs.append({
        "time": now.isoformat(),
        "user_id": user_id,
        "command": command,
        "args": args,
        "result": result
    })
    save_json(log_file, logs)

# ========== 汇总日志命令 ========== 
async def send_md(message_func, text, **kwargs):
    try:
        await message_func(text, parse_mode=ParseMode.MARKDOWN, **kwargs)
    except Exception:
        await message_func(text, **kwargs)

async def summary_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user_id = update.effective_user.id
    if not is_admin(user_id):
        await send_md(update.message.reply_text, "只有管理员才能查看汇总数据。")
        return
    files = sorted(glob.glob("admin_log_*.json"))
    
    if not files:
        await send_md(update.message.reply_text, "未找到任何管理员日志文件。")
        return
        
    total = 0
    summary = []
    for f in files:
        logs = load_json(f, [])
        total += len(logs)
        summary.append(f"`{f}`: *{len(logs)}* 条记录")
    text = f"共*{len(files)}*个日志文件，*{total}*条操作记录：\n" + "\n".join(summary)
    await send_md(update.message.reply_text, text)

async def acck_entry(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Acck签到入口"""
    user_id = update.effective_user.id
    if not is_allowed(user_id):
        await check_admin_and_warn(update, user_id, "/acck")
        return
    if is_banned(user_id):
        await update.message.reply_text("❌ 您已被封禁，无法使用此功能", reply_markup=ReplyKeyboardRemove())
        return
    can_use, usage = check_daily_limit(user_id)
    if not can_use:
        await update.message.reply_text(f"❌ 您已达到每日使用限制 ({usage}/{get_daily_limit()})", reply_markup=ReplyKeyboardRemove())
        return
    
    # 检查是否是首次使用（通过检查是否有启动提示记录）
    if not context.user_data.get('bot_started'):
        context.user_data['bot_started'] = True
        status_msg = f"""🤖 **机器人状态确认**

✅ 机器人正常运行中
🆔 用户ID：`{user_id}`
📊 今日剩余次数：{get_daily_limit() - usage}/{get_daily_limit()}
🎯 当前操作：Acck平台签到

---
💡 机器人已准备就绪，开始处理您的请求..."""
        await update.message.reply_text(status_msg, parse_mode=ParseMode.MARKDOWN, reply_markup=ReplyKeyboardRemove())
    
    user_file = os.path.join("Acck", "users", f"{user_id}.json")
    if os.path.exists(user_file):
        try:
            with open(user_file, 'r', encoding='utf-8') as f:
                user_info = json.load(f)
            result = acck_signin(user_info['username'], user_info['password'], user_info.get('totp'))
            increment_daily_usage(user_id)
            record_usage(user_id)
            await update.message.reply_text(f"✅ Acck签到结果:\n{result}", reply_markup=ReplyKeyboardRemove())
        except Exception as e:
            await update.message.reply_text(f"❌ 签到失败: {e}", reply_markup=ReplyKeyboardRemove())
    else:
        user_module[user_id] = 'acck签到'
        await update.message.reply_text(
            "📝 请配置您的Acck账号信息\n\n请输入您的邮箱:",
            reply_markup=ReplyKeyboardRemove()
        )
        return INPUT_USERNAME

async def akile_entry(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Akile签到入口"""
    user_id = update.effective_user.id
    if not is_allowed(user_id):
        await check_admin_and_warn(update, user_id, "/akile")
        return
    if is_banned(user_id):
        await update.message.reply_text("❌ 您已被封禁，无法使用此功能", reply_markup=ReplyKeyboardRemove())
        return
    can_use, usage = check_daily_limit(user_id)
    if not can_use:
        await update.message.reply_text(f"❌ 您已达到每日使用限制 ({usage}/{get_daily_limit()})", reply_markup=ReplyKeyboardRemove())
        return
    
    # 检查是否是首次使用（通过检查是否有启动提示记录）
    if not context.user_data.get('bot_started'):
        context.user_data['bot_started'] = True
        status_msg = f"""🤖 **机器人状态确认**

✅ 机器人正常运行中
🆔 用户ID：`{user_id}`
📊 今日剩余次数：{get_daily_limit() - usage}/{get_daily_limit()}
🎯 当前操作：Akile平台签到

---
💡 机器人已准备就绪，开始处理您的请求..."""
        await update.message.reply_text(status_msg, parse_mode=ParseMode.MARKDOWN, reply_markup=ReplyKeyboardRemove())
    
    user_file = os.path.join("Akile", "users", f"{user_id}.json")
    if os.path.exists(user_file):
        try:
            with open(user_file, 'r', encoding='utf-8') as f:
                user_info = json.load(f)
            result = akile_signin(user_info['username'], user_info['password'], user_info.get('totp'))
            increment_daily_usage(user_id)
            record_usage(user_id)
            await update.message.reply_text(f"✅ Akile签到结果:\n{result}", reply_markup=ReplyKeyboardRemove())
        except Exception as e:
            await update.message.reply_text(f"❌ 签到失败: {e}", reply_markup=ReplyKeyboardRemove())
    else:
        # 首次配置，走账号配置流程，保存凭证
        user_module[user_id] = 'Akile'
        await update.message.reply_text(
            "📝 请配置您的Akile账号信息\n\n请输入您的邮箱:",
            reply_markup=ReplyKeyboardRemove()
        )
        return INPUT_USERNAME

# 定时任务相关命令

async def add_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user_id = str(update.effective_user.id)
    
    # 检查是否是首次使用（通过检查是否有启动提示记录）
    if not context.user_data.get('bot_started'):
        context.user_data['bot_started'] = True
        status_msg = f"""🤖 **机器人状态确认**

✅ 机器人正常运行中
🆔 用户ID：`{update.effective_user.id}`
🎯 当前操作：添加定时任务

---
💡 机器人已准备就绪，开始处理您的请求..."""
        await update.message.reply_text(status_msg, parse_mode=ParseMode.MARKDOWN, reply_markup=ReplyKeyboardRemove())
    
    buttons = [
        [InlineKeyboardButton("Acck", callback_data="add_Acck")],
        [InlineKeyboardButton("Akile", callback_data="add_Akile")]
    ]
    reply_markup = InlineKeyboardMarkup(buttons)
    await update.message.reply_text("请选择要添加定时任务的平台：", reply_markup=reply_markup)
    return "ADD_SELECT_MODULE"

async def add_select_time(update, context, edit=False):
    module = context.user_data['add_module']
    buttons = []
    for hour, minute in RECOMMENDED_TIMES:
        label = f"{hour:02d}:{minute:02d}"
        if hour == DEFAULT_HOUR and minute == DEFAULT_MINUTE:
            label += " (默认)"
        buttons.append([InlineKeyboardButton(label, callback_data=f"add_time_{hour}_{minute}")])
    buttons.append([InlineKeyboardButton("⏰ 自定义时间", callback_data="add_custom_time")])
    reply_markup = InlineKeyboardMarkup(buttons)
    # 判断是 callback_query 还是普通消息
    if hasattr(update, 'callback_query') and update.callback_query:
        await update.callback_query.edit_message_text("请选择定时任务时间：", reply_markup=reply_markup)
    else:
        await update.message.reply_text("请选择定时任务时间：", reply_markup=reply_markup)
    return "ADD_SELECT_TIME"

async def add_select_module(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    module = "Acck" if query.data == "add_Acck" else "Akile"
    context.user_data['add_module'] = module
    # 直接要求输入账号
    await query.edit_message_text(f"请输入{module}账号：")
    return "ADD_INPUT_USERNAME"

async def add_input_username(update: Update, context: ContextTypes.DEFAULT_TYPE):
    context.user_data['add_username'] = update.message.text.strip()
    await update.message.reply_text("请输入密码：")
    return "ADD_INPUT_PASSWORD"

async def add_input_password(update: Update, context: ContextTypes.DEFAULT_TYPE):
    context.user_data['add_password'] = update.message.text.strip()
    await update.message.reply_text("如有TOTP验证码请输入，没有请回复'无'：")
    return "ADD_INPUT_TOTP"

async def add_input_totp(update: Update, context: ContextTypes.DEFAULT_TYPE):
    totp = update.message.text.strip()
    if totp == '无':
        totp = ''
    module = context.user_data['add_module']
    user_id = str(update.effective_user.id)
    info = {
        'username': context.user_data['add_username'],
        'password': context.user_data['add_password'],
        'totp': totp
    }
    save_user_info(user_id, module, info)
    await update.message.reply_text(f"账号信息已保存，接下来请选择定时任务时间：")
    # 自动进入时间选择
    return await add_select_time(update, context, edit=False)

# /del命令 - 删除定时任务
async def del_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user_id = update.effective_user.id
    if not is_allowed(user_id):
        await update.message.reply_text("❌ 您未被授权使用此功能")
        return
    
    # 检查是否是首次使用（通过检查是否有启动提示记录）
    if not context.user_data.get('bot_started'):
        context.user_data['bot_started'] = True
        status_msg = f"""🤖 **机器人状态确认**

✅ 机器人正常运行中
🆔 用户ID：`{user_id}`
🎯 当前操作：删除定时任务

---
💡 机器人已准备就绪，开始处理您的请求..."""
        await update.message.reply_text(status_msg, parse_mode=ParseMode.MARKDOWN, reply_markup=ReplyKeyboardRemove())
    
    tasks = get_user_tasks(user_id)
    if not tasks:
        await update.message.reply_text("📋 您还没有添加任何定时任务")
        return
    
    # 构建删除选项
    buttons = []
    for task_id, task in tasks.items():
        label = f"{task['module']} {task['hour']:02d}:{task['minute']:02d}"
        buttons.append([InlineKeyboardButton(f"❌ {label}", callback_data=f"del_{task_id}")])
    
    reply_markup = InlineKeyboardMarkup(buttons)
    await update.message.reply_text("请选择要删除的定时任务：", reply_markup=reply_markup)
    return "DEL_SELECT_TASK"

async def del_confirm(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    
    task_id = query.data.split('_', 1)[1]
    user_id = update.effective_user.id
    
    success, result = remove_scheduled_task(task_id, user_id)
    if success:
        await query.edit_message_text(f"✅ 定时任务删除成功！\n{result}")
        save_op_log(user_module[user_id], context.user_data['add_username'], '删除任务', task_id, 'success', result)
    else:
        await query.edit_message_text(f"❌ 删除失败: {result}")
        save_op_log(user_module[user_id], context.user_data['add_username'], '删除任务', task_id, 'error', result, error=task_id)
    return ConversationHandler.END

# /all命令 - 查看所有定时任务
async def all_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user_id = update.effective_user.id
    if not is_allowed(user_id):
        await update.message.reply_text("❌ 您未被授权使用此功能")
        return
    
    # 检查是否是首次使用（通过检查是否有启动提示记录）
    if not context.user_data.get('bot_started'):
        context.user_data['bot_started'] = True
        status_msg = f"""🤖 **机器人状态确认**

✅ 机器人正常运行中
🆔 用户ID：`{user_id}`
🎯 当前操作：查看定时任务

---
💡 机器人已准备就绪，开始处理您的请求..."""
        await update.message.reply_text(status_msg, parse_mode=ParseMode.MARKDOWN, reply_markup=ReplyKeyboardRemove())
    
    tasks = get_user_tasks(user_id)
    if not tasks:
        await update.message.reply_text("📋 您还没有添加任何定时任务\n使用 /add 添加定时任务")
        return
    
    message = "📋 您的定时任务列表：\n\n"
    for task_id, task in tasks.items():
        status = "✅ 启用" if task.get('enabled', True) else "❌ 禁用"
        last_run = "从未运行"
        if task.get('last_run'):
            try:
                last_run = datetime.fromisoformat(task['last_run']).strftime('%Y-%m-%d %H:%M:%S')
            except:
                pass
        
        message += f"🔹 {task['module']} {task['hour']:02d}:{task['minute']:02d} 账号: {task.get('username','')}\n"
        message += f"   状态: {status}\n"
        message += f"   最后运行: {last_run}\n"
        message += f"   任务ID: {task_id}\n\n"
    
    # 显示当天日志摘要
    today = get_shanghai_now().strftime('%Y%m%d')
    log_summary = "\n📑 今日签到日志摘要：\n"
    for module in ['Acck', 'Akile']:
        log_dir = module
        success_logs = glob.glob(os.path.join(log_dir, f"{today}_*_success.log"))
        error_logs = glob.glob(os.path.join(log_dir, f"{today}_*_error.log"))
        if not success_logs and not error_logs:
            continue
        log_summary += f"\n【{module}】\n"
        for log_file in success_logs:
            with open(log_file, 'r', encoding='utf-8') as f:
                lines = f.readlines()
                log_summary += f"✅ 成功：{''.join(lines)}\n"
        for log_file in error_logs:
            with open(log_file, 'r', encoding='utf-8') as f:
                lines = f.readlines()
                log_summary += f"❌ 失败：{''.join(lines)}\n"
    message += log_summary
    await update.message.reply_text(message, reply_markup=ReplyKeyboardRemove())

# 1. add_confirm
async def add_confirm(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    if query.data == "add_custom_time":
        await query.edit_message_text("请输入自定义时间（格式：HH:MM，如 8:30）：")
        return "ADD_CUSTOM_TIME"
    # 推荐时间
    data = query.data.split('_')
    hour, minute = int(data[2]), int(data[3])
    module = context.user_data['add_module']
    username = context.user_data['add_username']
    user_id = str(query.from_user.id)
    success, task_id = add_scheduled_task(user_id, module, username, hour, minute)
    if success:
        msg = f"✅ 定时任务添加成功！\n平台: {module}\n账号: {username}\n时间: {hour:02d}:{minute:02d}\n任务ID: {task_id}"
        await query.edit_message_text(msg)
        save_op_log(module, username, '添加任务', task_id, 'success', msg)
    else:
        msg = f"❌ 添加失败: {task_id}"
        await query.edit_message_text(msg)
        save_op_log(module, username, '添加任务', task_id, 'error', msg, error=task_id)
    return ConversationHandler.END

# 2. add_custom_time_confirm
async def add_custom_time_confirm(update: Update, context: ContextTypes.DEFAULT_TYPE):
    time_str = update.message.text.strip()
    result = parse_time_input(time_str)
    if not result[0]:
        await update.message.reply_text(f"❌ {result[2]}\n请重新输入时间（格式：HH:MM）：")
        return "ADD_CUSTOM_TIME"
    success, hour, minute = result
    module = context.user_data['add_module']
    username = context.user_data['add_username']
    user_id = str(update.effective_user.id)
    success, task_id = add_scheduled_task(user_id, module, username, hour, minute)
    if success:
        msg = f"✅ 定时任务添加成功！\n平台: {module}\n账号: {username}\n时间: {hour:02d}:{minute:02d}\n任务ID: {task_id}"
        await update.message.reply_text(msg, reply_markup=ReplyKeyboardRemove())
        save_op_log(module, username, '添加任务', task_id, 'success', msg)
    else:
        msg = f"❌ 添加失败: {task_id}"
        await update.message.reply_text(msg, reply_markup=ReplyKeyboardRemove())
        save_op_log(module, username, '添加任务', task_id, 'error', msg, error=task_id)
    return ConversationHandler.END

# ConversationHandler注册
add_conv_handler = ConversationHandler(
    entry_points=[CommandHandler('add', add_cmd)],
    states={
        "ADD_SELECT_MODULE": [CallbackQueryHandler(add_select_module, pattern="^add_.*$")],
        "ADD_INPUT_USERNAME": [MessageHandler(filters.TEXT & ~filters.COMMAND, add_input_username)],
        "ADD_INPUT_PASSWORD": [MessageHandler(filters.TEXT & ~filters.COMMAND, add_input_password)],
        "ADD_INPUT_TOTP": [MessageHandler(filters.TEXT & ~filters.COMMAND, add_input_totp)],
        "ADD_SELECT_TIME": [CallbackQueryHandler(add_confirm, pattern="^add_time_\\d+_\\d+$|^add_custom_time$")],
        "ADD_CUSTOM_TIME": [MessageHandler(filters.TEXT & ~filters.COMMAND, add_custom_time_confirm)],
    },
    fallbacks=[CommandHandler('cancel', cancel)],
)

del_conv_handler = ConversationHandler(
    entry_points=[CommandHandler('del', del_cmd)],
    states={
        "DEL_SELECT_TASK": [CallbackQueryHandler(del_confirm, pattern="^del_.*$")],
    },
    fallbacks=[CommandHandler('cancel', cancel)],
)

# main函数注册
def main():
    import sys
    TOKEN = TELEGRAM_BOT_TOKEN
    CHAT_ID = TELEGRAM_CHAT_ID
    
    if TOKEN == '在这里填写你的Bot Token' or CHAT_ID == '在这里填写你的Chat ID':
        print('❌ 配置错误：请先在代码顶部填写TELEGRAM_BOT_TOKEN和TELEGRAM_CHAT_ID')
        sys.exit(1)
    
    print('🔍 正在验证Bot Token和Chat ID的匹配性...')
    is_valid, message = verify_bot_owner(TOKEN, CHAT_ID)
    if not is_valid:
        print(f'❌ 验证失败：{message}')
        sys.exit(1)
    
    print('✅ 验证成功！Bot Token和Chat ID匹配')
    print(f'   {message}')
    print('-' * 50)
    
    app = Application.builder().token(TOKEN).build()
    # 检查是否为重启
    if os.path.exists('.restarting'):
        try:
            import asyncio
            async def notify_admin():
                await app.bot.send_message(chat_id=CHAT_ID, text="🚀 Bot已启动，重启成功！")
            try:
                asyncio.get_event_loop().run_until_complete(notify_admin())
            except Exception:
                asyncio.run(notify_admin())
        except Exception as e:
            print(f"[启动通知失败] {e}")
        os.remove('.restarting')
    # 注册所有handler（ConversationHandler必须最前面）
    app.add_handler(add_conv_handler)
    app.add_handler(del_conv_handler)
    
    # 添加账号配置流程的对话处理器
    conv_handler = ConversationHandler(
        entry_points=[
            CommandHandler('start', start),
            CommandHandler('acck', acck_entry),
            CommandHandler('akile', akile_entry)
        ],
        states={
            SELECT_MODULE: [MessageHandler(filters.Regex('^(acck签到|akile签到)$'), select_module)],
            INPUT_USERNAME: [MessageHandler(filters.TEXT & ~filters.COMMAND, input_username)],
            INPUT_PASSWORD: [MessageHandler(filters.TEXT & ~filters.COMMAND, input_password)],
            INPUT_TOTP: [MessageHandler(filters.TEXT & ~filters.COMMAND, input_totp)],
        },
        fallbacks=[CommandHandler('cancel', cancel)],
    )
    app.add_handler(conv_handler)
    
    app.add_handler(CommandHandler('allow', allow_user))
    app.add_handler(CommandHandler('me', me_cmd))
    app.add_handler(CommandHandler('unbind', unbind_cmd))
    app.add_handler(CommandHandler('help', help_cmd))
    app.add_handler(CommandHandler('ban', ban_user))
    app.add_handler(CommandHandler('unban', unban_user))
    app.add_handler(CommandHandler('disallow', disallow_user))
    app.add_handler(CommandHandler('stats', stats_cmd))
    app.add_handler(CommandHandler('top', top_cmd))
    app.add_handler(CommandHandler('broadcast', broadcast_cmd))
    app.add_handler(CommandHandler('export', export_cmd))
    app.add_handler(CommandHandler('setlimit', setlimit_cmd))
    app.add_handler(CommandHandler('restart', restart_cmd))
    app.add_handler(CommandHandler('shutdown', shutdown_cmd))
    app.add_handler(CommandHandler('menu', menu_cmd))
    app.add_handler(CommandHandler('summary', summary_cmd))
    app.add_handler(CommandHandler('add', add_cmd))
    app.add_handler(CommandHandler('del', del_cmd))
    app.add_handler(CommandHandler('all', all_cmd))
    
    # 启动定时任务调度器
    global task_scheduler
    task_scheduler = TaskScheduler(app)
    task_scheduler.start()
    
    print('🚀 Bot已启动...')
    print('🕐 定时任务调度器已启动...')
    app.run_polling(drop_pending_updates=True)

def save_user_info(user_id, module, info):
    """保存用户信息到对应模块的users目录，文件名为账号.json"""
    module_dir = module
    users_dir = os.path.join(module_dir, 'users')
    os.makedirs(users_dir, exist_ok=True)
    username = info['username']
    info['user_id'] = user_id  # 记录归属用户
    user_file = os.path.join(users_dir, f"{username}.json")
    with open(user_file, 'w', encoding='utf-8') as f:
        json.dump(info, f, ensure_ascii=False, indent=2)

if __name__ == '__main__':
    main() 