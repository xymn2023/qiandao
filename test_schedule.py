#!/usr/bin/env python3
"""
定时任务功能测试脚本
"""

import json
import os
from datetime import datetime
from croniter import croniter

def test_cron_expression():
    """测试Cron表达式解析"""
    print("=== Cron表达式测试 ===")
    
    test_cases = [
        ("0 8 * * *", "每天上午8点"),
        ("0 9,18 * * *", "每天上午9点和下午6点"),
        ("30 7 * * 1-5", "工作日早上7:30"),
        ("0 0 1 * *", "每月1号0点"),
        ("*/15 * * * *", "每15分钟"),
    ]
    
    for cron_expr, description in test_cases:
        try:
            cron = croniter(cron_expr, datetime.now())
            next_run = cron.get_next(datetime)
            print(f"✅ {description}: {cron_expr}")
            print(f"   下次运行: {next_run.strftime('%Y-%m-%d %H:%M:%S')}")
        except Exception as e:
            print(f"❌ {description}: {cron_expr} - 错误: {e}")
        print()

def test_scheduled_tasks_file():
    """测试定时任务文件操作"""
    print("=== 定时任务文件测试 ===")
    
    # 创建测试任务数据
    test_tasks = {
        "test_user_123": {
            "id": "test_user_123",
            "user_id": "123",
            "task_name": "测试任务",
            "cron_expression": "0 8 * * *",
            "module": "Acck",
            "enabled": True,
            "created_at": datetime.now().isoformat(),
            "last_run": None,
            "next_run": None
        }
    }
    
    # 保存测试数据
    with open("scheduled_tasks.json", "w", encoding="utf-8") as f:
        json.dump(test_tasks, f, ensure_ascii=False, indent=2)
    
    print("✅ 测试任务文件创建成功")
    
    # 读取测试数据
    with open("scheduled_tasks.json", "r", encoding="utf-8") as f:
        loaded_tasks = json.load(f)
    
    print(f"✅ 读取到 {len(loaded_tasks)} 个任务")
    
    # 清理测试文件
    os.remove("scheduled_tasks.json")
    print("✅ 测试文件清理完成")
    print()

def test_user_directories():
    """测试用户目录结构"""
    print("=== 用户目录结构测试 ===")
    
    modules = ["Acck", "Akile"]
    
    for module in modules:
        users_dir = os.path.join(module, "users")
        os.makedirs(users_dir, exist_ok=True)
        print(f"✅ 创建目录: {users_dir}")
        
        # 创建测试用户文件
        test_user_file = os.path.join(users_dir, "test_user.json")
        test_user_data = {
            "username": "test@example.com",
            "password": "testpassword",
            "totp": None
        }
        
        with open(test_user_file, "w", encoding="utf-8") as f:
            json.dump(test_user_data, f, ensure_ascii=False, indent=2)
        
        print(f"✅ 创建测试用户文件: {test_user_file}")
    
    print()

if __name__ == "__main__":
    print("🚀 开始测试定时任务功能...\n")
    
    test_cron_expression()
    test_scheduled_tasks_file()
    test_user_directories()
    
    print("✅ 所有测试完成！")
    print("\n📝 测试说明:")
    print("- Cron表达式测试: 验证时间解析功能")
    print("- 文件操作测试: 验证数据持久化功能")
    print("- 目录结构测试: 验证用户数据存储结构") 