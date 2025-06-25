#!/bin/bash
# 依赖管理功能测试脚本

echo "🧪 测试依赖管理功能..."

# 测试pip命令检测
echo "=== 测试pip命令检测 ==="
if command -v pip3 &>/dev/null; then
    echo "✅ 检测到 pip3"
elif command -v pip &>/dev/null; then
    echo "✅ 检测到 pip"
else
    echo "✅ 使用 python3 -m pip"
fi

# 测试requirements.txt文件
echo ""
echo "=== 测试requirements.txt文件 ==="
if [ -f "requirements.txt" ]; then
    echo "✅ requirements.txt 文件存在"
    echo "📋 依赖列表："
    cat requirements.txt
else
    echo "❌ requirements.txt 文件不存在"
fi

# 测试虚拟环境
echo ""
echo "=== 测试虚拟环境 ==="
if [ -d ".venv" ]; then
    echo "✅ 虚拟环境存在"
    if [ -f ".venv/bin/python" ]; then
        echo "✅ Python解释器存在"
    else
        echo "❌ Python解释器不存在"
    fi
else
    echo "❌ 虚拟环境不存在"
fi

echo ""
echo "📝 使用方法："
echo "1. 安装依赖: bash start.sh install-deps"
echo "2. 检查依赖: bash start.sh check-deps"
echo "3. 管理菜单: bash start.sh"
echo "4. 更新代码: bash start.sh update"
echo "5. 卸载程序: bash start.sh uninstall" 