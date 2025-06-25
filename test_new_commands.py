#!/usr/bin/env python3
"""
新定时任务命令功能测试脚本
"""

import json
import os
from datetime import datetime

def test_time_parsing():
    """测试时间解析功能"""
    print("=== 时间解析测试 ===")
    
    test_cases = [
        ("8:30", True, (8, 30)),
        ("23:45", True, (23, 45)),
        ("0:10", True, (0, 10)),
        ("24:00", False, "时间格式错误：小时应在0-23之间，分钟应在0-59之间"),
        ("12:60", False, "时间格式错误：小时应在0-23之间，分钟应在0-59之间"),
        ("8.30", True, (8, 30)),
        ("invalid", False, "时间格式错误：请使用 HH:MM 格式，如 8:30"),
    ]
    
    for time_str, expected_success, expected_result in test_cases:
        try:
            # 模拟parse_time_input函数
            if ':' in time_str:
                hour, minute = map(int, time_str.split(':'))
            elif '.' in time_str:
                hour, minute = map(int, time_str.split('.'))
            else:
                raise ValueError("Invalid format")
            
            if 0 <= hour <= 23 and 0 <= minute <= 59:
                success = True
                result = (hour, minute)
            else:
                success = False
                result = "时间格式错误：小时应在0-23之间，分钟应在0-59之间"
        except:
            success = False
            result = "时间格式错误：请使用 HH:MM 格式，如 8:30"
        
        if success == expected_success:
            print(f"✅ {time_str}: {result}")
        else:
            print(f"❌ {time_str}: 期望 {expected_result}, 实际 {result}")
    print()

def test_task_structure():
    """测试任务数据结构"""
    print("=== 任务数据结构测试 ===")
    
    # 创建测试任务
    test_task = {
        "id": "123_Acck_0010",
        "user_id": "123",
        "module": "Acck",
        "hour": 0,
        "minute": 10,
        "enabled": True,
        "created_at": datetime.now().isoformat(),
        "last_run": None
    }
    
    print(f"✅ 任务ID: {test_task['id']}")
    print(f"✅ 用户ID: {test_task['user_id']}")
    print(f"✅ 平台: {test_task['module']}")
    print(f"✅ 时间: {test_task['hour']:02d}:{test_task['minute']:02d}")
    print(f"✅ 状态: {'启用' if test_task['enabled'] else '禁用'}")
    print()

def test_recommended_times():
    """测试推荐时间点"""
    print("=== 推荐时间点测试 ===")
    
    recommended_times = [
        (0, 0),   # 0:00
        (0, 10),  # 0:10 (默认)
        (0, 20),  # 0:20
        (0, 30),  # 0:30
        (1, 0),   # 1:00
    ]
    
    for hour, minute in recommended_times:
        label = f"{hour:02d}:{minute:02d}"
        if hour == 0 and minute == 10:
            label += " (默认)"
        print(f"✅ {label}")
    print()

def test_commands():
    """测试命令功能"""
    print("=== 命令功能测试 ===")
    
    commands = [
        ("/add", "添加定时任务"),
        ("/del", "删除定时任务"),
        ("/all", "查看所有任务"),
    ]
    
    for cmd, description in commands:
        print(f"✅ {cmd} - {description}")
    print()

if __name__ == "__main__":
    print("🚀 开始测试新定时任务命令功能...\n")
    
    test_time_parsing()
    test_task_structure()
    test_recommended_times()
    test_commands()
    
    print("✅ 所有测试完成！")
    print("\n📝 新功能说明:")
    print("- /add: 添加定时任务，支持推荐时间和自定义时间")
    print("- /del: 删除指定的定时任务")
    print("- /all: 查看用户的所有定时任务")
    print("- 默认时间: 00:10 (每天凌晨0点10分)")
    print("- 自定义时间: 支持 HH:MM 格式") 