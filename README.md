# CC MiMo Rescue

一个本地运行的 macOS 小工具，用来辅助 Claude Code + CC Switch + 小米 MiMo 工作流：

- 先给 Claude 聊天记录做本地全量备份；
- 检查 Claude Code、CC Switch、Claude memory 等路径；
- 把图片/绘画任务路由到 MiMo 2.5 助手模型；
- 给 Claude 写入一段可管理的记忆规则，避免它直接读取图片/base64 导致对话卡死；
- 找出包含嵌入媒体/base64 的危险会话；
- 在写入前预览修复内容，并自动生成可恢复备份。

界面默认中文，也可以在右上角切换到 English。

![CC MiMo Rescue icon](frontend/Resources/app-icon-source.png)

## 下载和安装

从 GitHub Releases 下载最新的 `.dmg` 文件：

```text
CC-MiMo-Rescue-0.1.0.dmg
```

安装方式：

1. 双击打开 DMG。
2. 把 `CC MiMo Rescue.app` 拖到 `Applications`。
3. 从 Applications 启动。

当前版本没有 Apple Developer ID 签名和 notarization。如果 macOS 提示无法打开：

1. 在 Finder 里右键点击 `CC MiMo Rescue.app`。
2. 选择 `打开`。
3. 再确认一次打开。

这是 macOS 对未公证开源 App 的常见提示。

## 隐私承诺

本软件只在本机运行。

- 不联网传输聊天记录；
- 不上传备份；
- 不做遥测；
- 不需要账号；
- 不采集隐私数据；
- 备份、审计日志、修复后的文件都保存在你的电脑上。

详细说明见 [PRIVACY.md](PRIVACY.md)。

## 安全设计

软件打开时不会自动做全盘扫描，也不会自动创建全量备份。

所有写入操作都需要用户明确确认：

- 创建聊天记录全量备份；
- 修复某个会话记录；
- 修改 CC Switch 模型路由；
- 写入或复位 Claude memory 规则；
- 恢复单文件备份。

写入前会在本机备份目录中保存备份：

```text
~/.local/share/cc-mimo-rescue/backups
```

全量聊天记录备份会复制：

```text
~/.claude/projects
~/.claude/sessions
```

## 它解决什么问题

Claude Code 会话里如果混入图片、PDF 图片块、大段 base64 或嵌入媒体内容，可能让主对话变慢、卡死，甚至难以继续打开。

CC MiMo Rescue 的思路是：

1. 先备份聊天记录；
2. 让图片/绘画任务走更轻的助手模型；
3. 把 Claude memory 写清楚，避免主对话直接读取图片/二进制；
4. 对已经出问题的危险会话，只在预览后做最小修复。

## 功能

- 原生 SwiftUI macOS App；
- 中文/英文双语界面；
- 本地路径自动发现；
- 本地全量聊天记录备份；
- 备份列表和单文件恢复；
- 会话危险程度筛选；
- 媒体/base64 清理预览；
- 确认后带备份修复；
- CC Switch 每个 Claude 模型槽位单独配置；
- Claude memory 规则预览、应用、复位；
- 本地审计日志。

## 从源码运行

后端：

```bash
cd backend
PYTHONPATH=src python3 -m cc_mimo_rescue doctor --json
```

前端：

```bash
cd frontend
swift run CCMimoRescueUI
```

## 本地打包

打包 `.app`：

```bash
cd frontend
scripts/package-app.sh
```

打包 `.dmg`：

```bash
cd frontend
scripts/package-dmg.sh
```

输出位置：

```text
frontend/dist/CC MiMo Rescue.app
frontend/dist/CC-MiMo-Rescue-0.1.0.dmg
```

## 系统要求

- macOS；
- Python 3.9+；
- Swift Package Manager / Xcode Command Line Tools；
- 本机已有 Claude Code 配置；
- 如需修改模型路由，需要本机已有 CC Switch 数据库。

打包后的 App 会携带 Python 后端源码，但仍使用系统 Python 运行。

## 仓库结构

```text
backend/     Python CLI 后端
frontend/    SwiftUI macOS 前端
```

## 当前限制

- 还没有 Apple Developer ID 签名和 notarization；
- 还不是正式安装器 `.pkg`；
- OCR/图片内容总结能力目前依赖 Claude/本地工具链，不内置云服务；
- 不会自动修复所有 warning，会优先处理真正危险的媒体/base64 会话。

## License

License not selected yet.
