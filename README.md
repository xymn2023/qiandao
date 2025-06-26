# Telegram 多功能签到机器人

## 一、项目简介

这是一个基于 `python-telegram-bot` 构建的多功能签到机器人，旨在集成并自动化多个网站的每日签到任务。项目目前已集成 `Acck` 和 `Akile` 两个平台的签到功能，并包含了一套完整的管理员与多用户权限管理系统，灵感来自于：https://github.com/QiQuWa/QingLong。
---

## ✨ 项目特色

-   **多平台集成**: 目前支持 `Acck` 和 `Akile` 平台的自动签到。
-   **沉浸式对话**: 通过独立的命令（如 `/acck`, `/akile`）引导用户完成账号配置，体验流畅。
-   **权限管理**:
    -   严格区分**管理员**和**普通用户**。
    -   管理员拥有所有权限，包括授权、禁用、统计、广播等。
    -   普通用户需要管理员通过 `/allow <用户ID>` 授权后才能使用。
-   **数据持久化**:
    -   用户凭证（账号、密码、TOTP）在首次配置后将加密保存在服务器，后续可实现"一键签到"。
    -   所有用户数据按模块和用户ID隔离存储，确保安全。
-   **安全与控制**:
    -   **黑名单系统**: 管理员可通过 `/ban` 命令封禁恶意用户。
    -   **每日次数限制**: 可为普通用户设置每日签到次数上限，防止滥用。
    -   **防滥用机制**: 普通用户尝试执行管理员命令达到一定次数后会自动被拉黑。
-   **强大的管理员功能**:
    -   **/allow, /disallow**: 管理用户白名单。
    -   **/ban, /unban**: 管理用户黑名单。
    -   **/stats, /top**: 查看详细的使用统计和活跃用户排行。
    -   **/broadcast**: 向所有授权用户广播消息。
    -   **/export**: 导出所有用户数据和统计信息。
    -   **/setlimit**: 动态设置普通用户的每日使用上限。
    -   **/restart, /shutdown**: 通过指令远程控制Bot的运行状态。
-   **详细日志**:
    -   管理员的所有操作都会被记录在每日日志中 (`admin_log_YYYY-MM-DD_HHMM.json`)。
    -   管理员可通过 `/summary` 命令快速查看所有日志文件的概览。

## 二、一键安装命令

**推荐使用如下命令一键安装/管理（自动适配全局/本地）：**

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/xymn2023/qiandao/main/start.sh)
```

- 首次运行会自动下载项目、安装依赖、注册快捷命令，并提示输入 Bot Token 和 Chat ID。
- 后续只需输入 `qiandao-bot`（全局）或 `bash start.sh`（本地）即可进入管理菜单。
- 一键脚本默认安装在python虚拟环境下，避免不必要的错误。
---

## 三、配置方式（.env 文件）

### 1. 自动生成

- 安装脚本会提示输入 Bot Token 和 Chat ID，并自动写入项目根目录的 `.env` 文件。

### 2. 手动修改

- 如需更换配置，直接编辑 `.env` 文件：

```
TELEGRAM_BOT_TOKEN=你的BotToken
TELEGRAM_CHAT_ID=你的ChatID
```

- **注意：** `.env` 文件不会被升级/重装/更新覆盖，配置永久有效。
  **注意：**  建议使用脚本的退出功能，默认脚本安装成功界面已屏蔽ctrl+c，之前使用ctrl+c退出会产生莫名其妙的bug.
---

## 四、bot.py 自动读取配置

- `bot.py` 顶部自动加载 `.env` 文件，无需手动修改代码：

```python
from dotenv import load_dotenv
import os
load_dotenv()
TELEGRAM_BOT_TOKEN = os.getenv("TELEGRAM_BOT_TOKEN")
TELEGRAM_CHAT_ID = os.getenv("TELEGRAM_CHAT_ID")
if not TELEGRAM_BOT_TOKEN or not TELEGRAM_CHAT_ID:
    print("❌ 配置错误：请在项目根目录新建 .env 文件，并填写 TELEGRAM_BOT_TOKEN 和 TELEGRAM_CHAT_ID")
    exit(1)
```

- **如缺少 .env 或配置为空，程序会自动报错并退出。**

---
更多功能具体以bot为准。

## 五、升级/重装/迁移说明

- **升级/重装/拉取新代码时，.env 文件不会被覆盖，配置始终有效。**
- 如需迁移到新服务器，只需拷贝 `.env` 文件和数据文件（如 allowed_users.json 等）即可。
- 更换 Bot Token/Chat ID 只需编辑 `.env` 文件，无需修改任何代码。

---

## 六、常见问题与解决方案

### 1. 启动时报"配置错误"

- 检查 `.env` 文件是否存在于项目根目录，内容是否填写正确。

### 2. 如何更换 Bot Token 或 Chat ID？

- 直接编辑 `.env` 文件，保存后重启机器人即可。

### 3. 更新代码后配置丢失？

- **不会丢失**，.env 文件不会被覆盖。

### 4. 依赖缺失或启动失败？

- 进入管理菜单选择"检查并安装更新"，或手动激活虚拟环境后 `pip install -r requirements.txt`。

### 5. 怎么会想着做这个项目？

- 当时就是闲得发慌没事做想找个东西琢磨琢磨，俗称闲得蛋疼。

---
更新内容：

更新时间2026-06-06 9:15:21

1.新增/add添加定时任务，/del删除定时任务，/all查看所有定时任务，不限任务数量，具体以bot提示为准

2.定时任务成功与否都会有日志都会将信息打印发送至bot

3.定时任务代码逻辑无误，至于是否会自动运行签到功能这个未知，具体的自测

4.闲了修复不可用功能


## 📁 目录结构

```
.
├── Acck/
│   ├── qiandao.py
│   └── users/      # 存储Acck平台的用户凭证
├── Akile/
│   ├── qiandao.py
│   └── users/      # 存储Akile平台的用户凭证
└── bot.py          # 机器人主逻辑文件
```

## 🤝 贡献

欢迎通过 Pull Request 或 Issues 为此项目做出贡献。如果你有想要集成的新签到模块，也欢迎提出！

## 📄 开源许可

本项目采用 [MIT License](LICENSE) 开源。 
- 如有问题可在 GitHub 提 issue 或联系开发者。

---

