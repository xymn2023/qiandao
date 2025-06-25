# ========== 重要配置 ==========
# 请在下方填写你的 Telegram Bot Token 和 Chat ID
TELEGRAM_BOT_TOKEN = "在这里填写你的Bot Token"
TELEGRAM_CHAT_ID = "在这里填写你的Chat ID"
# ==============================

import os
import json
import requests
import subprocess
from datetime import datetime, date
import glob
from telegram import Update, ReplyKeyboardMarkup, ReplyKeyboardRemove, BotCommand
from telegram.ext import (
    Application, CommandHandler, MessageHandler, filters, ConversationHandler, ContextTypes
)
from telegram.constants import ParseMode
from Acck.qiandao import main as acck_signin
from Akile.qiandao import main as akile_signin
import sys

# 数据文件
ALLOWED_USERS_FILE = "allowed_users.json"
BANNED_USERS_FILE = "banned_users.json"
DAILY_USAGE_FILE = "daily_usage.json"
USAGE_STATS_FILE = "usage_stats.json"
ADMIN_LOG_FILE = "admin_log.json"
ADMIN_ATTEMPT_FILE = "admin_attempts.json"

# 默认每日次数限制
DEFAULT_DAILY_LIMIT = 3

# 日志文件名格式
LOG_TIME_FMT = '%Y-%m-%d_%H%M'

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
        "time": datetime.now().isoformat(),
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
    now = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    if str(user_id) not in stats:
        stats[str(user_id)] = {"count": 0, "last": now}
    stats[str(user_id)]["count"] += 1
    stats[str(user_id)]["last"] = now
    save_usage_stats(stats)

# 用户解绑

def unbind_user(user_id):
    for module in ["Acck", "Akile"]:
        users_dir = os.path.join(module, 'users')
        user_file = os.path.join(users_dir, f"{user_id}.json")
        if os.path.exists(user_file):
            os.remove(user_file)

# 状态定义
SELECT_MODULE, INPUT_USERNAME, INPUT_PASSWORD, INPUT_TOTP = range(4)

# 主菜单
main_menu = [['acck签到', 'akile签到']]

# 各模块对应的目录和函数
MODULES = {
    'acck签到': ('Acck', acck_signin),
    'akile签到': ('Akile', akile_signin),
}

# 记录用户当前操作的模块
user_module = {}

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
    try:
        chat_id_int = int(CHAT_ID)
        if user_id != chat_id_int and user_id not in load_allowed_users():
            await update.message.reply_text("您不是此Bot的创建者或授权用户，无法使用此功能。")
            return ConversationHandler.END
    except ValueError:
        await update.message.reply_text("Chat ID格式错误，请联系管理员。")
        return ConversationHandler.END
    # 只显示欢迎和ID，不弹菜单
    await update.message.reply_text(f"欢迎使用签到系统，你的ID为：{user_id}\n请输入命令或点击菜单按钮进行操作。\n如需帮助请输入 /help")
    return ConversationHandler.END

async def select_module(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if update.effective_chat.type != 'private':
        await send_md(update.message.reply_text, "请在与Bot的私聊中使用本功能。")
        return ConversationHandler.END
    user_id = update.effective_user.id
    if not is_allowed(user_id):
        await send_md(update.message.reply_text, "您不是此Bot的管理员或授权用户，请联系管理员授权后再使用。")
        return ConversationHandler.END
    can_use, current_usage = check_daily_limit(user_id)
    if not can_use:
        await send_md(update.message.reply_text, f"今日使用次数已达上限（{get_daily_limit()}次），您已使用{current_usage}次，请明天再试。")
        return ConversationHandler.END
    text = update.message.text
    if text not in MODULES:
        await send_md(update.message.reply_text, "请选择菜单中的功能。")
        return SELECT_MODULE
    
    user_module[user_id] = text
    await send_md(update.message.reply_text, "请输入账号：")
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
    await send_md(update.message.reply_text, "请输入密码：")
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
    await send_md(update.message.reply_text, "是否有TOTP二步验证？有请输入验证码，没有请回复'无'：")
    return INPUT_TOTP

async def input_totp(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if update.effective_chat.type != 'private':
        await update.message.reply_text("请在与Bot的私聊中使用本功能。")
        return ConversationHandler.END
    user_id = update.effective_user.id
    if not is_allowed(user_id):
        await update.message.reply_text("您不是此Bot的管理员或授权用户，请联系管理员授权后再使用。"); return ConversationHandler.END
    
    totp = update.message.text
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
        
    await update.message.reply_text(result_msg)
    
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
    await update.message.reply_text("\n".join(status))

async def unbind_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user_id = update.effective_user.id
    unbind_user(user_id)
    await update.message.reply_text("您的所有账号信息已清除。")

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
    await update.message.reply_text(f"已封禁用户 {target_id}")

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
        await update.message.reply_text(f"已解封用户 {target_id}")
    else:
        await update.message.reply_text(f"用户 {target_id} 不在黑名单。")

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
        await update.message.reply_text(f"已移除白名单用户 {target_id}")
    else:
        await update.message.reply_text(f"用户 {target_id} 不在白名单。")

async def stats_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user_id = update.effective_user.id
    if not is_admin(user_id):
        await send_md(update.message.reply_text, "只有管理员才能查看统计。"); return
    stats = load_usage_stats() or {}
    if not stats:
        await send_md(update.message.reply_text, "暂无任何用户统计数据。"); return
    
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
        
    await send_md(update.message.reply_text, "\n".join(msg))

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
    await send_md(update.message.reply_text, "\n".join(msg))

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
    now = datetime.now()
    log_file = f"broadcast_{now.strftime(LOG_TIME_FMT)}.txt"
    with open(log_file, "a", encoding="utf-8") as f:
        f.write(f"{now.isoformat()} 管理员{user_id} 广播: {msg}\n")
    await update.message.reply_text(f"广播已发送，记录于{log_file}。")
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
    now = datetime.now()
    export_file = f"export_{now.strftime(LOG_TIME_FMT)}.json"
    with open(export_file, "w", encoding="utf-8") as f:
        json.dump(export, f, ensure_ascii=False, indent=2)
    await update.message.reply_text(f"数据已导出到 {export_file}。")
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
        await update.message.reply_text(f"已设置每日签到次数上限为 {limit} 次。")
        log_admin_action("setlimit", f"设置每日签到次数上限为 {limit}")
    except Exception:
        await update.message.reply_text("参数错误。")

async def restart_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user_id = update.effective_user.id
    if not is_admin(user_id):
        await update.message.reply_text("只有管理员才能重启Bot。")
        return
    await update.message.reply_text("Bot正在重启...")
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
    await update.message.reply_text("Bot即将关闭...")
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
    await update.message.reply_text(help_text)

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
        f"{botfather_text}"
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
            update.message.reply_text(f"你不是管理员，已被自动拉黑。请勿反复尝试管理命令。")
        else:
            update.message.reply_text(f"你不是管理员，无权使用此命令。警告 {count}/3，超过3次将被拉黑。")
        return False
    return True

# ========== 管理员操作日志 ========== 
def log_admin_action_daily(user_id, command, args, result):
    now = datetime.now()
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
    user_id = update.effective_user.id
    if is_banned(user_id):
        await send_md(update.message.reply_text, "您已被封禁，无法使用此Bot。")
        return ConversationHandler.END
    if not is_allowed(user_id):
        await send_md(update.message.reply_text, "您未被授权使用此Bot，请联系管理员。")
        return ConversationHandler.END
    can_use, current_usage = check_daily_limit(user_id)
    if not can_use:
        await send_md(update.message.reply_text, f"今日使用次数已达上限（{get_daily_limit()}次），您已使用{current_usage}次，请明天再试。")
        return ConversationHandler.END
    await send_md(update.message.reply_text, "请输入账号：")
    context.user_data['module'] = 'Acck'
    context.user_data['step'] = 'username'
    user_module[user_id] = 'acck签到'
    return INPUT_USERNAME

async def akile_entry(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user_id = update.effective_user.id
    if is_banned(user_id):
        await send_md(update.message.reply_text, "您已被封禁，无法使用此Bot。")
        return ConversationHandler.END
    if not is_allowed(user_id):
        await send_md(update.message.reply_text, "您未被授权使用此Bot，请联系管理员。")
        return ConversationHandler.END
    can_use, current_usage = check_daily_limit(user_id)
    if not can_use:
        await send_md(update.message.reply_text, f"今日使用次数已达上限（{get_daily_limit()}次），您已使用{current_usage}次，请明天再试。")
        return ConversationHandler.END
    await send_md(update.message.reply_text, "请输入账号：")
    context.user_data['module'] = 'Akile'
    context.user_data['step'] = 'username'
    user_module[user_id] = 'akile签到'
    return INPUT_USERNAME

def save_user_info(user_id, module, info):
    """保存用户信息到对应模块的users目录"""
    module_dir = module
    users_dir = os.path.join(module_dir, 'users')
    os.makedirs(users_dir, exist_ok=True)
    user_file = os.path.join(users_dir, f"{user_id}.json")
    with open(user_file, 'w', encoding='utf-8') as f:
        json.dump(info, f, ensure_ascii=False, indent=2)

# ConversationHandler只保留acck、akile相关状态
conv_handler = ConversationHandler(
    entry_points=[
        CommandHandler('start', start),
        CommandHandler('acck', acck_entry),
        CommandHandler('akile', akile_entry),
    ],
    states={
        SELECT_MODULE: [MessageHandler(filters.TEXT & ~filters.COMMAND, select_module)],
        INPUT_USERNAME: [MessageHandler(filters.TEXT & ~filters.COMMAND, input_username)],
        INPUT_PASSWORD: [MessageHandler(filters.TEXT & ~filters.COMMAND, input_password)],
        INPUT_TOTP: [MessageHandler(filters.TEXT & ~filters.COMMAND, input_totp)],
    },
    fallbacks=[CommandHandler('cancel', cancel)],
)

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
    # 注册所有handler
    app.add_handler(conv_handler)
    app.add_handler(CommandHandler('allow', allow_user))
    app.add_handler(CommandHandler('acck', acck_entry))
    app.add_handler(CommandHandler('akile', akile_entry))
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
    
    print('🚀 Bot已启动...')
    app.run_polling(drop_pending_updates=True)

if __name__ == '__main__':
    main() 