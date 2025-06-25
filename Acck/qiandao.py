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
    try:
        resp = requests.post(url, json={"chat_id": chat_id, "text": text})
        if resp.status_code == 200:
            print(f"{Color.GREEN}✅ Telegram通知发送成功{Color.END}")
        else:
            print(f"{Color.RED}❌ Telegram通知发送失败: {resp.text}{Color.END}")
    except Exception as e:
        print(f"{Color.RED}❌ 发送Telegram通知异常: {e}{Color.END}")

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
        resp = self.session.post("https://api.acck.io/api/v1/user/login", json=payload, timeout=20)
        data = resp.json()

        if data.get("status_code") == 0 and "二步验证" in data.get("status_msg", ""):
            if not self.totp_secret:
                raise Exception("需要TOTP但未配置密钥")
            totp = pyotp.TOTP(self.totp_secret)
            payload["token"] = totp.now()
            print(f"{Color.YELLOW}⚠️ 使用TOTP验证码登录中...{Color.END}")
            resp = self.session.post("https://api.acck.io/api/v1/user/login", json=payload, timeout=20)
            data = resp.json()
            if data.get("status_code") != 0:
                raise Exception("TOTP验证失败: " + data.get("status_msg", "未知错误"))

        if data.get("status_code") != 0:
            raise Exception("登录失败: " + data.get("status_msg", "未知错误"))

        self.token = data["data"]["token"]
        print(f"{Color.GREEN}✅ 登录成功，Token: {self.token[:10]}...{Color.END}")

    def checkin(self):
        if not self.token:
            raise Exception("未登录，无法签到")

        headers = {"Authorization": self.token}
        resp = self.session.get("https://sign-service.acck.io/api/acLogs/sign", headers=headers, timeout=20)
        try:
            data = resp.json()
        except Exception:
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

    def get_balance(self):
        if not self.token:
            return None

        headers = {"Authorization": self.token}
        resp = self.session.get("https://api.acck.io/api/v1/user/index", headers=headers, timeout=20)
        data = resp.json()
        if data.get("status_code") != 0:
            msg = f"获取余额失败: {data.get('status_msg', '未知错误')}"
            print(f"{Color.RED}❌ {msg}{Color.END}")
            return None

        info = data.get("data", {})
        money = info.get("money", 0)
        try:
            money = float(money) / 100
        except Exception:
            money = 0.0

        ak_coin = info.get("ak_coin", "N/A")
        balance_info = f"AK币: {ak_coin}，现金: ¥{money:.2f}"
        print(f"{Color.BLUE}💰 余额信息 - {balance_info}{Color.END}")
        return balance_info

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

# 如需测试请在bot.py中调用main，不建议直接运行本文件
