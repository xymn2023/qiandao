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
                verify_data = verify_response.json()
                
                if verify_data.get("status_code") == 0:
                    return verify_data.get("data", {}).get("token"), None
                return None, verify_data.get("status_msg", "TOTP验证失败")
            
            if data.get("status_code") == 0:
                return data.get("data", {}).get("token"), None
                
            return None, data.get("status_msg", "登录失败")
            
        except Exception as e:
            return None, f"登录异常: {str(e)}"

    def get_real_balance(self, token: str) -> Dict:
        """获取真实余额信息（自动转换单位为元）"""
        try:
            headers = {"Authorization": token}
            response = self.session.get(
                "https://api.akile.io/api/v1/user/index",
                headers=headers,
                timeout=20
            )
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
            
        except Exception as e:
            return {"error": f"余额请求异常: {str(e)}"}

    def checkin(self, token: str) -> Tuple[bool, str]:
        """执行签到"""
        try:
            headers = {"Authorization": token}
            response = self.session.get(
                "https://api.akile.io/api/v1/user/Checkin",
                headers=headers,
                timeout=20
            )
            data = response.json()
            
            if data.get("status_code") == 0 or "已签到" in data.get("status_msg", ""):
                return True, data.get("status_msg", "签到成功")
            return False, data.get("status_msg", "签到失败")
            
        except Exception as e:
            return False, f"签到异常: {str(e)}"

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
