#!/bin/bash
set -e

# ================== 项目介绍 ==================
echo "=============================================="
echo "  Telegram 多功能签到机器人一键部署脚本"
echo "  项目地址: https://github.com/xymn2023/qiandao"
echo "=============================================="
echo ""
echo "本脚本将自动下载项目、创建虚拟环境、安装依赖并进行配置。"
echo ""

# --- 1. 下载项目 ---
REPO_URL="https://github.com/xymn2023/qiandao.git"
PROJECT_DIR="qiandao"

if ! command -v git &> /dev/null; then
    echo "错误：需要 'git' 来下载项目文件。请先安装git。"
    echo "Debian/Ubuntu: sudo apt update && sudo apt install -y git"
    echo "CentOS/RHEL: sudo yum install -y git"
    exit 1
fi

if [ -d "$PROJECT_DIR" ]; then
    echo "项目目录 '$PROJECT_DIR' 已存在，进入目录..."
else
    echo "正在从 GitHub 克隆项目..."
    git clone "$REPO_URL" "$PROJECT_DIR"
fi

cd "$PROJECT_DIR" || exit
echo "项目文件已准备就绪，当前位于: $(pwd)"
echo ""

# --- 2. Python 和虚拟环境设置 ---
echo "按任意键开始配置和安装..."
read -n 1 -s -r

echo ""
if command -v python3 &> /dev/null; then
    PYTHON_CMD=python3
elif command -v python &> /dev/null; then
    PYTHON_CMD=python
else
    echo "错误：未检测到 Python 解释器，请先安装 Python。"
    exit 1
fi
echo "使用解释器: $PYTHON_CMD"

VENV_DIR=".venv"
if [ ! -d "$VENV_DIR" ]; then
    echo "正在创建 Python 虚拟环境..."
    $PYTHON_CMD -m venv $VENV_DIR
    if [ $? -ne 0 ]; then
        echo "创建虚拟环境失败，请确保 'python3-venv' (或类似包) 已安装。"
        exit 1
    fi
fi
PYTHON_IN_VENV="$VENV_DIR/bin/python"

# --- 3. 依赖安装 ---
echo "正在虚拟环境中安装/升级所有依赖..."
$PYTHON_IN_VENV -m pip install --upgrade pip python-telegram-bot requests pyotp curl_cffi python-dotenv
if [ $? -ne 0 ]; then
    echo "依赖安装失败，请检查网络或错误信息。"
    exit 1
fi

# --- 4. 交互式输入 ---
echo ""
read -p "请输入你的 Telegram Bot Token: " TELEGRAM_BOT_TOKEN
read -p "请输入你的 Telegram Chat ID (管理员ID): " TELEGRAM_CHAT_ID

# --- 5. 自动写入 bot.py ---
# 兼容Linux和macOS的sed命令
if [[ "$(uname)" == "Darwin" ]]; then
    # macOS
    sed -i '' "s/^TELEGRAM_BOT_TOKEN = .*/TELEGRAM_BOT_TOKEN = \"${TELEGRAM_BOT_TOKEN}\"/" bot.py
    sed -i '' "s/^TELEGRAM_CHAT_ID = .*/TELEGRAM_CHAT_ID = \"${TELEGRAM_CHAT_ID}\"/" bot.py
else
    # Linux
    sed -i "s/^TELEGRAM_BOT_TOKEN = .*/TELEGRAM_BOT_TOKEN = \"${TELEGRAM_BOT_TOKEN}\"/" bot.py
    sed -i "s/^TELEGRAM_CHAT_ID = .*/TELEGRAM_CHAT_ID = \"${TELEGRAM_CHAT_ID}\"/" bot.py
fi

echo ""
echo "配置已成功写入 bot.py。"
echo ""

# --- 6. 询问是否运行项目 ---
while true; do
    read -p "是否现在启动机器人？(y/n): " yn
    case $yn in
        [Yy]* ) echo "正在启动机器人..."; $PYTHON_IN_VENV bot.py; break;;
        [Nn]* ) echo "安装完成，已退出脚本。如需启动，请进入 '$PROJECT_DIR' 目录后运行 'bash start.sh'。"; exit;;
        * ) echo "请输入 y 或 n。";;
    esac
done 
