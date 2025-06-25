#!/bin/bash
set -e

# ================== 项目介绍 ==================
echo "=============================================="
echo "  Telegram 多功能签到机器人一键部署脚本"
echo "  项目地址: https://github.com/xymn2023/qiandao"
echo "=============================================="
echo ""

# --- 1. 项目准备：确保位于正确的项目目录 ---
# 通过检查关键文件判断是否已在项目目录中
if [ -f "bot.py" ] && [ -d "Acck" ]; then
    echo "已在项目目录中: $(pwd)"
else
    # 如果不在项目目录，则执行克隆或进入操作
    echo "本脚本将自动下载项目、创建虚拟环境、安装依赖并进行配置。"
    echo ""
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
fi
# --- 至此，脚本确保当前工作目录是项目根目录 ---

echo ""
# --- 2. Python 和虚拟环境设置 ---
echo "按任意键开始配置和安装..."
read -n 1 -s -r < /dev/tty

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
read -p "请输入你的 Telegram Bot Token: " TELEGRAM_BOT_TOKEN < /dev/tty
read -p "请输入你的 Telegram Chat ID (管理员ID): " TELEGRAM_CHAT_ID < /dev/tty

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
    read -p "如何启动机器人？(y:前台运行, b:后台运行, n:退出): " ybn < /dev/tty
    case $ybn in
        [Yy]* )
            echo "正在前台启动机器人 (按 Ctrl+C 退出)..."
            $PYTHON_IN_VENV bot.py
            break;;
        [Bb]* )
            echo "正在后台启动机器人..."
            nohup $PYTHON_IN_VENV bot.py > bot.log 2>&1 &
            PID=$!
            sleep 2 # 等待一会，以便进程启动或失败

            if ps -p $PID > /dev/null; then
                echo "✅ 机器人已在后台启动成功 (PID: $PID)。"
                echo "   - 要停止机器人, 请运行: kill $PID"
                echo "   - 日志文件位于: $(pwd)/bot.log"
                echo ""

                while true; do
                    read -p "请选择操作 [1: 查看实时日志, 2: 检查进程状态, 0: 退出]: " action < /dev/tty
                    case $action in
                        1)
                            echo "--- 实时日志 (按 Ctrl+C 返回此菜单) ---"
                            (trap 'echo -e "\n--- 已返回菜单 ---"; exit' INT; tail -f bot.log)
                            echo ""
                            ;;
                        2)
                            echo "--- 检查进程状态 ---"
                            if ps -p $PID > /dev/null; then
                                echo "✅ 进程 (PID: $PID) 正在运行中。"
                                ps -p $PID -o comm,pid,etime,user
                            else
                                echo "❌ 进程 (PID: $PID) 已停止。请检查 'bot.log' 排查问题。"
                            fi
                            echo "--------------------"
                            echo ""
                            ;;
                        0)
                            echo "已退出管理脚本。机器人仍在后台运行。"
                            exit 0
                            ;;
                        *)
                            echo "无效输入，请输入 1, 2, 或 0。"
                            ;;
                    esac
                done
            else
                echo "❌ 启动失败! 请检查 'bot.log' 获取详细错误信息。"
                cat bot.log
            fi
            break;;
        [Nn]* )
            echo "安装完成，已退出脚本。如需启动，请进入项目目录后运行 'bash start.sh'。"
            exit;;
        * )
            echo "请输入 y, b, 或 n。";;
    esac
done 
