---
name: wechat-gzh-analyzer
description: "分析微信公众号后台数据，包括文章阅读量、评论、点赞等统计。当用户需要分析微信公众号数据、导出公众号文章统计报表时调用此技能。"
---

# 微信公众号数据分析器 (Playwright 版)

自动登录微信公众平台，分析文章数据并生成 Excel 报告和可视化图表。

## 📋 完整工作流程

### 步骤 1: 运行脚本（后台模式）
当用户请求分析公众号数据时，AI 助手**必须以后台模式**执行脚本：

**⚠️ 关键：不要用 `&` 后台化！** Hermes terminal 工具不支持 `&` 后台化（会报错 `command uses '&' backgrounding`），正确方式是用 `background=true` 参数：

```bash
# ✅ 正确方式：后台运行，避免阻塞
terminal(background=true, command="cd /root/.hermes/skills/openclaw-wxgzh/scripts && python3 wechat_spiderb.py -t week -p 1")

# ❌ 错误方式：用 & 会报错
python3 wechat_spiderb.py -t week -p 1 &   # 不要这样写！
```

**参数示例：**
- `-t week -p 1` → 一周内数据，最多 1 页
- `-t month -p 3` → 一月内数据，最多 3 页

---

### 步骤 2: 发送登录二维码（⚠️ 关键步骤，需等待 10 秒，并发送提示消息：二维码正在生成，请稍后请用微信扫码登录。）

**二维码文件生成需要约 10 秒**，AI 助手必须按以下流程操作：

#### 2.1 等待 + 检查（循环最多 4 次）

```bash
# 第 1 次检查：等待 10 秒
sleep 10 && ls -la /tmp/wxgzh_screenshots/login_qrcode.png

# 如果不存在，第 2 次检查：再等 5 秒
sleep 5 && ls -la /tmp/wxgzh_screenshots/login_qrcode.png

# 如果还不存在，第 3 次检查：再等 5 秒
sleep 5 && ls -la /tmp/wxgzh_screenshots/login_qrcode.png
```

#### 2.2 文件存在后立即发送

在响应中嵌入 `MEDIA:/absolute/path` 即可发送图片：

```
MEDIA:/tmp/wxgzh_screenshots/login_qrcode.png
```

**⚠️ 重要：**
- 二维码文件 **不是立即生成** 的，脚本需要时间启动浏览器、打开页面、截图
- **首次检查必须等待至少 10 秒**（之前 6 秒太短，文件还没生成）
- 如果文件不存在，**不要放弃**，继续每 5 秒重试一次，最多 4 次
- 总等待时间可能达到 20-25 秒，这是正常的
- **提示消息必须先发**：在等二维码的 10 秒内，先发消息"二维码正在生成，请稍后请用微信扫码登录。"，让用户提前知道要扫码。

#### 2.3 完整检查流程示例

```bash
# 启动脚本（用 background=true，不要用 &）
# terminal(background=true, command="cd ~/.hermes/skills/openclaw-wxgzh/scripts && python3 wechat_spiderb.py -t month -p 3")

# 等待 10 秒后检查
sleep 10
if [ -f /tmp/wxgzh_screenshots/login_qrcode.png ]; then
    echo "二维码已生成，发送给用户"
    # 调用 message 工具发送
else
    echo "二维码还未生成，再等 5 秒"
    sleep 5
    # 再次检查...
fi
```

---

### 步骤 3: 用户扫码登录
用户使用微信扫描二维码，并在手机上确认登录。


---

### 步骤 4: 等待数据抓取完成
AI 助手需要轮询检查报告是否生成：

```bash
# 每 30 秒检查一次，直到报告生成
sleep 30 && ls -la /tmp/wxgzh_reports/
```

**预期结果：**
- 报告生成前：目录为空
- 报告生成后：`wechat_stats_YYYYMMDD_HHMMSS_[week|month].xlsx`

---

### 步骤 5: 发送 Excel 报告

检测到报告文件后，**立即发送**到当前微信会话（⚠️ 不要发文字说明，直接发文件）：

```
MEDIA:/tmp/wxgzh_reports/wechat_stats_20260501_141720_week.xlsx
```

---

### 步骤 6: 运行数据分析并生成图表

发送 Excel 后，**立即运行数据分析脚本**生成可视化图表：

```bash
# 后台运行数据分析脚本（用 background=true，不要用 &）
terminal(background=true, command="cd /root/.hermes/skills/openclaw-wxgzh/scripts && python3 data_analyzer.py")
```

#### 6.1 等待图表生成（约 30 秒）
（启动命令同上：用 background=true 后台运行）

```bash
# 等待 30 秒后检查图表文件
sleep 30 && ls -la /tmp/wxgzh_analysis.png
```

**重要**：图表渲染需要约25秒（加载ECharts + 等待20秒渲染），请耐心等待。

#### 6.2 验证图表完整性

```bash
# 检查文件大小，确保图表完整
ls -la /tmp/wxgzh_analysis.png
# 正常大小应 > 100KB，如果 < 50KB 可能不完整
```

#### 6.3 图表生成后立即发送

```
MEDIA:/tmp/wxgzh_analysis.png
```

**图表说明：**
| 图表 | 文件 | 内容 |
|------|------|------|
| 合并分析图 | `/tmp/wxgzh_analysis.png` | 包含阅读数柱状图 + 互动数据堆叠折线图 + 最大值饼图 |

---

### ⚠️ 消息发送顺序规则（重要）

**正确做法：**
1. ✅ 发送 Excel 文件 → **不附带文字说明**
2. ✅ 发送图表文件 → **不附带文字说明**
3. ✅ 所有文件发送完毕后 → **最后发一条完成消息**

**错误做法：**
- ❌ 发文字"报告已生成，正在发送..." → 再发文件（文字延迟到达）
- ❌ 发文件时附带文字说明（文字会延迟）
- ❌ 每个步骤都发文字通知（造成消息混乱）

**消息发送格式（严格按此顺序）：**

```
# 消息1a （T+0秒，启动脚本后立即发送）：提示用户等待
二维码正在生成，请稍后请用微信扫码登录。

# 消息1b （T+10秒，二维码生成后）：发送二维码图片（无文字）
MEDIA:/tmp/wxgzh_screenshots/login_qrcode.png

# 消息2 ：仅 Excel 文件，无文字
MEDIA:/tmp/wxgzh_reports/wechat_stats_xxx.xlsx

# 消息3 ：图表 + 完成消息（同一条消息，MEDIA 图片先发，文字随后）
MEDIA:/tmp/wxgzh_analysis.png
✅完成！📊 Excel 报告已发送 📈 数据分析图表已发送
```

⚠️ **总共 3 条消息：** 提示文字、二维码图片、Excel 文件各自单独发送。图表和完成消息合并为一条发送。

---

## 🛠️ 相关命令

```bash
# 进入脚本工作目录
cd ~/.hermes/skills/openclaw-wxgzh/scripts

# 爬取文章
python3 wechat_spiderb.py -t month -p 3

# 数据分析（自动查找最新Excel）
python3 data_analyzer.py

# 数据分析（指定Excel文件）
python3 data_analyzer.py -f /tmp/wxgzh_reports/wechat_stats_xxx.xlsx

# 数据分析（指定输出目录）
python3 data_analyzer.py -o /tmp
```

## 📊 参数说明

### wechat_spiderb.py

| 参数            | 说明                       | 默认值 |
| ------------- | ------------------------ | --- |
| `-p, --pages` | 要爬取的最大页数                 | 10  |
| `-t, --time`  | 时间筛选：week=一周内, month=一月内 | 无   |

### data_analyzer.py

| 参数            | 说明                       | 默认值 |
| ------------- | ------------------------ | --- |
| `-f, --file`  | Excel 文件路径（默认自动查找最新的）   | 自动查找 |
| `-o, --output`| 图表输出目录                   | /tmp |

## 📁 输出文件

| 文件       | 路径                                        | 说明                      |
| -------- | ----------------------------------------- | ----------------------- |
| 登录二维码     | `/tmp/wxgzh_screenshots/login_qrcode.png` | 登录二维码截图，AI 助手必须发送给用户 |
| Excel 报告 | `/tmp/wxgzh_reports/wechat_stats_*.xlsx`  | 文章统计数据，AI 助手必须发送给用户  |
| 合并分析图表   | `/tmp/wxgzh_analysis.png`                | 柱状图+折线图+饼图合并图片 |

## 📈 Excel 报告内容

报告包含以下字段：

| 字段   | 说明            |
| ---- | ------------- |
| 标题   | 文章标题          |
| 发布时间 | 文章发布时间        |
| 阅读数  | 文章阅读量         |
| 点赞数  | 文章点赞数         |
| 分享数  | 文章分享数         |
| 推荐数  | 文章推荐数（好看数）    |
| 留言数  | 文章留言数         |
| 链接   | 文章链接          |
| 爬取时间 | 数据爬取时间        |

> ⚠️ **arm64 平台注意：** 脚本需要 `chromium_headless_shell` 而非普通 Chromium。
> 安装头壳浏览器（下载可能超时，需加长超时时间）：
> ```bash
> PLAYWRIGHT_BROWSERS_DOWNLOAD_TIMEOUT=120000 playwright install chromium-headless-shell
> ```
> 验证安装：
> ```bash
> ls -la /root/.cache/ms-playwright/chromium_headless_shell-*/chrome-linux/headless_shell
> ```

## ⚙️ 环境要求

- Python 3.7+
- Playwright 已安装
- pandas, openpyxl, pyecharts, pillow (PIL) 库

## 📦 安装依赖

```bash
pip install playwright pandas openpyxl pyecharts pillow
```

### ⚠️ Chromium 安装（关键）

脚本依赖 **`chromium_headless_shell`**（非普通 chromium），安装命令：

```bash
# arm64 架构（如树莓派/Topeet）需加超时参数，默认 30s 常超时
PLAYWRIGHT_BROWSERS_DOWNLOAD_TIMEOUT=120000 playwright install chromium-headless-shell

# 可选：同时安装普通 Chromium（某些场景需要）
playwright install chromium
```

**安装后路径：**
- `/root/.cache/ms-playwright/chromium_headless_shell-1208/`（必需 ~275MB）
- `/root/.cache/ms-playwright/chromium-1208/`（可选 ~430MB）
- `/root/.cache/ms-playwright/ffmpeg-1011/`（可选 ~1.6MB）

### ⚠️ 常见陷阱

- **系统清理会误删 Chromium** — 清理垃圾时容易删除 `/root/.cache/ms-playwright/` 目录，导致脚本报错 `"BrowserType.launch: Executable doesn't exist"`。如果出现该错误，重新执行 `playwright install chromium-headless-shell` 即可。
- **arm64 下载超时** — 默认 30s 超时不够，必须设置 `PLAYWRIGHT_BROWSERS_DOWNLOAD_TIMEOUT=120000` 或更高。

## ⚠️ 重要注意事项

### 1. 必须使用脚本生成的二维码
**用户必须扫描 `/tmp/wxgzh_screenshots/login_qrcode.png` 这个文件中的二维码。**

- ❌ **不要**让 AI 助手通过浏览器工具打开登录页后截图
- ❌ **不要**让用户自己打开微信公众平台截图
- ✅ **必须**等待脚本生成二维码后，AI 助手发送 `/tmp/wxgzh_screenshots/login_qrcode.png` 给用户

原因：如果 AI 助手和用户各自打开不同的浏览器会话，用户扫码登录的是自己的会话，脚本无法检测到登录状态。

### 2. AI 助手的责任（⚠️ 时序要求）

当用户请求分析公众号数据时，AI 助手必须按以下时序执行：

| 时间点 | 操作 | 说明 |
|--------|------|------|
| T+0 秒 | 启动爬虫脚本 + **发送提示消息** | `terminal(background=true, ...)` → `"二维码正在生成…"` |
| T+10 秒 | **第 1 次检查二维码** | `sleep 10 && ls ...` |
| T+15 秒 | 如无，第 2 次检查 | 再等 5 秒重试 |
| T+20 秒 | 如无，第 3 次检查 | 再等 5 秒重试 |
| T+25 秒 | 如仍无，检查脚本进程 | `ps aux \| grep wechat_spider` |
| 二维码生成 | **发送二维码图片** | 不要延迟 |
| 发二维码后 | **立即轮询报告，每 30 秒** | 不等用户回复"已扫码" |
| Excel 生成 | **直接发送 Excel 文件**（不发文字） | 不要延迟 |
| Excel 发送后 | **运行数据分析脚本** | `terminal(background=true, ...) python3 data_analyzer.py` |
| 30 秒后 | 检查图表文件 | `sleep 30 && ls /tmp/wxgzh_analysis.png` |
| 图表生成 | **直接发送图表文件**（不发文字） | 不要延迟 |
| 所有文件发送后 | **发一条完成消息** | `✅完成！📊 Excel 报告已发送 📈 数据分析图表已发送` |

**具体操作：**
1. ✅ **后台运行爬虫脚本** → 避免阻塞后续检查
2. ✅ **10 秒后首次检查** → 文件可能还未生成，耐心等待
3. ✅ **循环检查** → 最多 4 次，每次间隔 5 秒
4. ✅ **指定 channel 发送** → `channel="openclaw-weixin"`
5. ✅ **直接发送 Excel 文件** → 不要附带文字说明
6. ✅ **发送 Excel 后立即运行数据分析** → `python3 data_analyzer.py &`
7. ✅ **等待 30 秒后检查图表** → 渲染需要时间
8. ✅ **验证文件大小 > 100KB** → 确保图表完整
9. ✅ **直接发送图表文件** → 不要附带文字说明
10. ✅ **所有文件发送后发完成消息** 

### 3. 用户的责任
1. ✅ 收到二维码后，用微信扫码
2. ✅ 在手机上确认登录
3. ✅ 等待 AI 助手发送 Excel 报告和数据分析图表

### 4. 不要使用 OpenClaw 浏览器工具
- ❌ **不要**使用 OpenClaw 的 `browser` 工具
- ✅ **必须**让脚本自己管理 Playwright 浏览器会话

脚本已经内置了完整的浏览器管理逻辑，使用 OpenClaw 浏览器工具会导致会话冲突。

---

### 5. 快速执行清单（AI 助手必读）

```bash
# 1. 启动爬虫脚本（后台模式）
# ⚠️ 用 background=true 参数，不要用 &（terminal 工具不支持 & 后台化）
terminal(background=true, command="cd /root/.hermes/skills/openclaw-wxgzh/scripts && python3 wechat_spiderb.py -t month -p 3")

# 2. 发送提示消息（二维码生成前先告知用户）
发送："二维码正在生成，请稍后请用微信扫码登录。"

# 3. 等待 10 秒后检查二维码
sleep 10 && ls -la /tmp/wxgzh_screenshots/login_qrcode.png
# → 如果存在，立即用 message 工具发送到当前微信会话
# → 如果不存在，继续等待 5 秒后重试（最多重试 3 次）

# 3. 每 30 秒检查报告（脚本自动化，无需等用户确认）
sleep 30 && ls -la /tmp/wxgzh_reports/
# → 如果有 .xlsx 文件，直接发送 Excel（不发文字）

# 4. 发送 Excel 后，立即运行数据分析
python3 /root/.hermes/skills/openclaw-wxgzh/scripts/data_analyzer.py &

# 5. 等待 30 秒后检查图表（重要：渲染需要时间）
sleep 30 && ls -la /tmp/wxgzh_analysis.png
# → 检查文件大小 > 100KB，如果太小可能不完整
# → 如果存在且完整，直接发送图表（不发文字）

# 6. 所有文件发送完毕后，发一条完成消息告诉用户任务完成。
✅完成！📊 Excel 报告已发送 📈 数据分析图表已发送
```

**关键检查点：**
- ⏱️ **首次检查等待 10 秒**（不是 6 秒！浏览器启动需要时间）
- 🔄 **最多重试 3-4 次**，总等待时间可能 20-25 秒
- 📤 文件生成后 **立即发送**，不要等待用户询问
- 📊 用户扫码后 **2 分钟内** 应该生成报告
- 📈 **Excel 发送后立即运行 data_analyzer.py**
- 🖼️ **图表生成约需 30 秒**（渲染需要时间），检查后立即发送
- 🔍 **验证文件大小 > 100KB**，确保图表完整
- 🔍 如果超时，检查脚本进程：`ps aux | grep wechat_spider`

### 6. 减少 Token 消耗（重要）

为避免不必要的 token 消耗，AI 助手应：

**必须做：**
- ✅ 发送登录二维码图片（`/tmp/wxgzh_screenshots/login_qrcode.png`）
- ✅ 发送生成的 Excel 报告（`/tmp/wxgzh_reports/wechat_stats_*.xlsx`）
- ✅ 发送数据分析图表（`/tmp/wxgzh_analysis.png`）
- ✅ 等待脚本运行完成后发送文件

**不要做：**
- ❌ 不要读取和分析 Excel 文件内容
- ❌ 不要解读脚本运行过程和日志输出
- ❌ 不要统计文章数量、列出文章标题等详细说明
- ❌ 不要重复脚本已经输出的统计信息

**简洁回复模板：**
```
✅完成！📊 Excel 报告已发送 📈 数据分析图表已发送
```
---

## 🔧 故障排查

### 问题 1: 脚本运行后没有生成二维码
- 检查 `/tmp/wxgzh_screenshots/` 目录是否存在
- 确保脚本有权限写入该目录
- 查看脚本输出日志
- **检查脚本进程是否存活**：`ps aux | grep wechat_spider`

### 问题 2: 扫码后脚本没有继续执行
- 确认扫码的是脚本生成的二维码（路径：`/tmp/wxgzh_screenshots/login_qrcode.png`）
- 确认在手机上点击了"确认登录"
- 检查浏览器是否被其他进程关闭
- **轮询检查报告目录**：每 30 秒 `ls -la /tmp/wxgzh_reports/`

### 问题 3: 数据抓取失败
- 检查是否成功登录到公众号后台
- 检查网络连接是否正常
- 查看脚本输出的错误信息

### 问题 4: 数据分析图表生成失败
- 确认已安装 Playwright：`pip install playwright pillow && playwright install chromium`
- 检查 `/tmp/` 目录是否有写入权限
- 查看 data_analyzer.py 的输出日志排查具体错误

### 问题 5: 二维码文件生成慢（预期行为）
- **现象**：脚本启动后 6 秒检查，文件不存在
- **原因**：浏览器启动 + 打开页面 + 截图 **需要约 10 秒**
- **解决**：
  - 第 1 次检查：**等待 10 秒**（不是 6 秒！）
  - 如不存在，再等 5 秒重试，最多 3-4 次
  - 总等待时间 20-25 秒是正常的
- **检查命令**：`sleep 10 && ls -la /tmp/wxgzh_screenshots/login_qrcode.png`

### 问题 6: message 工具发送失败
- **确保指定 channel**：`channel="openclaw-weixin"`
- **文件路径必须是绝对路径**：`/tmp/wxgzh_screenshots/login_qrcode.png`
- **不要用相对路径**：`./login_qrcode.png` 会失败
- **确认文件已完全写入**：检查文件大小 > 0
  ```bash
  ls -la /tmp/wxgzh_screenshots/login_qrcode.png
  # 正常大小约 300-400 KB
  ```
