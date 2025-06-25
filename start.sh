#!/bin/bash

# ================== 项目介绍 ==================
echo "=============================================="
echo "  Telegram 多功能签到机器人一键启动脚本"
echo "  项目主页: https://github.com/你的项目地址"
echo "  功能：Acck/Akile自动签到、权限管理、统计、广播等"
echo "  作者：你的名字"
echo "=============================================="
echo ""
echo "本脚本将自动创建虚拟环境、安装依赖、配置Bot Token和Chat ID。"
echo ""
echo "按任意键开始..."
read -n 1 -s -r

# --- 1. Python 和虚拟环境设置 ---
echo ""
# 检测可用的 Python 解释器
if command -v python3 >/dev/null 2>&1; then
    PYTHON_CMD=python3
elif command -v python >/dev/null 2>&1; then
    PYTHON_CMD=python
else
    echo "未检测到 Python 解释器，请先安装 Python。"
    exit 1
fi
echo "使用解释器: $PYTHON_CMD"

# 设置并创建虚拟环境
VENV_DIR=".venv"
if [ ! -d "$VENV_DIR" ]; then
    echo "创建 Python 虚拟环境..."
    $PYTHON_CMD -m venv $VENV_DIR
    if [ $? -ne 0 ]; then
        echo "创建虚拟环境失败。请确保 'python3-venv' (或类似包) 已安装。"
        echo "例如：sudo apt install python3-venv"
        exit 1
    fi
fi
PYTHON_IN_VENV="$VENV_DIR/bin/python"

# --- 2. 依赖安装 ---
echo "正在虚拟环境中安装/升级依赖..."
$PYTHON_IN_VENV -m pip install --upgrade pip python-telegram-bot requests pyotp curl_cffi python-dotenv
if [ $? -ne 0 ]; then
    echo "依赖安装失败，请检查网络或错误信息。"
    exit 1
fi

# --- 3. 交互式输入 ---
echo ""
read -p "请输入你的 Telegram Bot Token: " TELEGRAM_BOT_TOKEN
read -p "请输入你的 Telegram Chat ID（管理员ID）: " TELEGRAM_CHAT_ID

# --- 4. 自动写入 bot.py ---
sed -i "s/^TELEGRAM_BOT_TOKEN = .*/TELEGRAM_BOT_TOKEN = \"${TELEGRAM_BOT_TOKEN}\"/" bot.py
sed -i "s/^TELEGRAM_CHAT_ID = .*/TELEGRAM_CHAT_ID = \"${TELEGRAM_CHAT_ID}\"/" bot.py
echo ""
echo "配置已写入 bot.py。"
echo ""

# --- 5. 询问是否运行项目 ---
while true; do
    read -p "是否现在启动机器人？(y/n): " yn
    case $yn in
        [Yy]* ) echo "正在启动机器人..."; $PYTHON_IN_VENV bot.py; break;;
        [Nn]* ) echo "已退出脚本。"; exit;;
        * ) echo "请输入 y 或 n。";;
    esac
done 