# trans-video-cli

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

把 [pyVideoTrans](https://github.com/jianchang512/pyvideotrans) 封装成一个**可迁移、自包含的 CLI 技能**：语音识别 → 字幕翻译 → AI 配音 → 合成视频，一条命令完成。

包内自带一份 pyVideoTrans 源码，初始化后即可脱离外部安装运行。

## 目录结构

```
trans_video_cli\
├── README.md                          ← 本文件
├── runtime\
│   └── pyvideotrans\                  ← 包内自带的 pyVideoTrans 源码（约 16 MB）
│       ├── cli.py                     ← 实际被调用的入口
│       ├── videotrans\                ← 引擎
│       ├── models\                    ← ASR 模型缓存（setup --models 或首次使用时生成）
│       └── .venv\                     ← setup 后生成（约 8.3 GB，不随包分发）
├── tools\                             ← 按需自动下载的工具（缓存优先）
│   ├── uv\  ffmpeg\  ollama\
│   └── _cache\                        ← 已下载的压缩包，重装/迁移时直接复用
└── .claude\
    └── skills\
        └── trans-video-cli\
            ├── SKILL.md               ← 技能定义（Claude Code 自动加载）
            ├── scripts\
            │   └── trans_cli.py       ← 封装脚本（仅标准库）
            └── references\
                ├── channels.md        ← 30 个翻译渠道 + 41 个 TTS 渠道
                ├── languages.md       ← 语言代码 + 默认音色
                ├── models.md          ← Whisper 模型选择
                └── troubleshooting.md ← 错误对照表
```

`.claude\skills\` 是 Claude Code 的自动发现路径；项目级/全局安装方式见下文「在 Agent 中安装与使用」。下文用 `C:\path\to\trans_video_cli`（macOS/Linux 为 `/path/to/trans_video_cli`）指代本目录。

## 首次安装

```bash
# 1) 探测这台机器（系统 / GPU / 已有工具 / 缓存）
python .claude\skills\trans-video-cli\scripts\trans_cli.py doctor

# 2) 一键初始化：缺什么下什么，有缓存就用缓存
python .claude\skills\trans-video-cli\scripts\trans_cli.py setup

# 3) 自检（--gpu 顺带验证 CUDA）
python .claude\skills\trans-video-cli\scripts\trans_cli.py check --gpu

# 4) 端到端自检：自动生成素材，跑通 ffmpeg / 识别 / 配音 / 翻译
python .claude\skills\trans-video-cli\scripts\trans_cli.py selftest
```

`selftest` 成功时输出 `RESULT: 9 passed, 0 failed`，失败会返回非零退出码并打印错误摘要；`--keep` 保留中间文件，`--json` 输出机器可读结果。

`setup` 的自动获取策略（缓存优先）：

| 依赖 | 行为 |
|---|---|
| uv | PATH 有就复用；没有则下载官方二进制到 `tools\uv\` |
| ffmpeg / ffprobe | PATH 有就复用；`tools\ffmpeg\bin` 有就复用；都没有才下载并解压 |
| Python 3.10 | uv 自动安装；已有版本则复用 |
| PyTorch | 检测 NVIDIA GPU：有则 cu128，无则 CPU 轮子（`--torch cpu/cu128` 可强制） |
| ASR 模型 | `--models large-v3-turbo,tiny` 预取；先查包内与外部安装的模型缓存，未命中才下载 |
| Ollama | 已安装则复用；`--with-ollama` 下载便携版并拉取模型 |
| PyPI / GitHub | 默认清华镜像（`--index-url` 覆盖）；代理自动读 `HTTPS_PROXY` 或 git 配置 |

常用开关：

```bash
... setup --torch cpu            # 强制 CPU 版 torch
... setup --models large-v3-turbo  # 预取默认模型（缓存命中则跳过）
... setup --with-ollama          # 连 Ollama 一起装好并拉取 qwen2.5:3b
... setup --no-download          # 离线模式：缺什么就报错，不联网
... setup --no-sync              # 只探测/复制，不装依赖
... setup --copy-from <dir>      # 从指定源码初始化
... setup --force                # 重新复制源码（保留已有 params.json）
```

另外：**`setup` 会清空 `params.json` 中所有 `*_key` 字段**，避免把密钥打进可分发目录。使用前请通过环境变量或 `--api-key` 提供。

环境路径解析顺序：

```
--home  >  PYVIDEOTRANS_HOME  >  包内 runtime\pyvideotrans  >  外部 ~/pyvideotrans
```

## 快速开始

```bash
# 完整视频翻译（中文 → 英文）
python .claude\skills\trans-video-cli\scripts\trans_cli.py vtv "D:\videos\demo.mp4" --source zh-cn --target en

# 只生成字幕
python .claude\skills\trans-video-cli\scripts\trans_cli.py stt "D:\videos\demo.mp4"

# 翻译已有字幕
python .claude\skills\trans-video-cli\scripts\trans_cli.py sts "D:\subs\demo.srt" --source zh-cn --target ja

# 字幕转配音
python .claude\skills\trans-video-cli\scripts\trans_cli.py tts "D:\subs\demo.srt" --target en
```

其他命令：

```bash
... setup --copy-from <dir>                               # 从指定源码初始化
... setup --no-sync                                       # 只复制源码，不装依赖
... setup --force                                         # 重新复制源码（保留已有 params.json）
... check                                                 # 自检
... channels                                              # 列出渠道和编号
... voices --language en --locale en-US                   # 列出音色
... test-channel --channel deepseek                       # 验证 API Key
... vtv demo.mp4 --source zh-cn --target en --dry-run     # 只看将要执行的命令
```

## 在 Agent 中安装与使用

本项目本身就是一个 Claude Code 技能：`SKILL.md` 描述何时触发、如何调用，`references/` 提供渠道、语言、模型和排错资料。注册后，Agent 可以直接把自然语言需求转成 CLI 命令。

### 1. 注册技能

**方式 A：项目级注册（推荐）**

在包含本目录的终端启动 Claude Code，或把本目录加入当前会话：

```bash
claude --add-dir C:\path\to\trans_video_cli
```

会话内也可以使用 `/add-dir C:\path\to\trans_video_cli`。Claude Code 会自动发现 `.claude\skills\trans-video-cli\`，`trans-video-cli` 技能随即可用。

**方式 B：全局注册（所有项目可用）**

把技能目录链接到用户级技能目录，同时保留它与包内 `runtime/`、`tools/` 的相对位置：

```bat
:: Windows（cmd；目录联接不需要管理员权限）
if not exist "%USERPROFILE%\.claude\skills" mkdir "%USERPROFILE%\.claude\skills"
mklink /J "%USERPROFILE%\.claude\skills\trans-video-cli" "C:\path\to\trans_video_cli\.claude\skills\trans-video-cli"
```

```bash
# macOS / Linux
mkdir -p ~/.claude/skills
ln -s /path/to/trans_video_cli/.claude/skills/trans-video-cli ~/.claude/skills/trans-video-cli
```

不要只复制 `trans-video-cli` 子目录：封装脚本根据自身路径推算包根目录，只有符号链接/目录联接才能保留 `runtime/` 和 `tools/` 的位置。若必须复制，请复制整个 `trans_video_cli/`，并用 `PYVIDEOTRANS_HOME` 或 `--home` 指向运行时。

**方式 C：其他 Agent**

任何能执行命令的 Agent 都可以直接调用，无需注册技能：

```bat
C:\path\to\trans_video_cli\trans.cmd vtv "D:\videos\demo.mp4" --source zh-cn --target en
```

把 `SKILL.md` 和 `references/` 一并作为上下文交给 Agent，效果接近 Claude Code 的技能。

### 2. 在 Agent 中首次初始化

对 Agent 说“初始化 trans-video-cli 运行时”，或让它执行：

```bash
python .claude\skills\trans-video-cli\scripts\trans_cli.py doctor
python .claude\skills\trans-video-cli\scripts\trans_cli.py setup
python .claude\skills\trans-video-cli\scripts\trans_cli.py check --gpu
python .claude\skills\trans-video-cli\scripts\trans_cli.py selftest
```

`setup` 需要联网获取 uv、ffmpeg、Python 3.10、PyTorch 与 ASR 模型；首次安装通常占用 10 GB 以上（`.venv` 约 8 GB，模型另算），建议预留 15 GB 以上磁盘空间。凭证只通过环境变量（如 `DEEPSEEK_API_KEY`）或 `--api-key` 提供，不要写进 README，也不要提交 `params.json`。

### 3. 在 Agent 中调用

自然语言即可触发技能：

```text
把 D:\videos\demo.mp4 翻译成英文并配音
给这个视频生成中文字幕
把这份 SRT 翻译成日文
```

Agent 会读取 `SKILL.md`，选择 `vtv` / `stt` / `sts` / `tts` 命令，并在必要时确认输入文件、目标语言和输出目录。

也可以显式调用技能，或直接执行命令：

```text
/trans-video-cli vtv "D:\videos\demo.mp4" --source zh-cn --target en
```

```bat
C:\path\to\trans_video_cli\trans.cmd stt "D:\videos\demo.mp4"
```

建议让 Agent 先加 `--dry-run` 查看将要执行的命令；长任务加 `--json` 获取结构化结果。

> 安全提示：Agent 需要获得执行 `python` / `uv` / `ffmpeg` 的权限，请逐条批准，不要使用跳过权限的模式。包装脚本会拒绝把输入文件放进输出目录，也不要绕过它直接调用上游 `cli.py`。

## 跨平台支持

| 能力 | Windows | Linux x86_64 | Linux arm64 | macOS |
|---|---|---|---|---|
| 包内运行时 + venv | ✅ | ✅ | ✅ | ✅ |
| uv 自动获取 | ✅ | ✅ | ✅ | ✅ |
| ffmpeg 自动获取 | ✅ | ✅ | ✅ | ⚠️ brew/port |
| PyTorch | cu128 / CPU | cu128 / CPU | CPU | CPU |
| Ollama 自动获取 | ✅ | ✅ | ✅ | ⚠️ 手动安装 |
| pynini / WeTextProcessing | ✅ | ✅ | ⚠️ 自动跳过 | ⚠️ 自动跳过 |
| 主流程（识别/翻译/配音/合成） | ✅ | ✅ | ✅ | ✅ |

平台启动器：

```bash
# Windows
trans.cmd selftest
trans.cmd vtv movie.mp4 --source zh-cn --target en

# macOS / Linux
./trans selftest
./trans vtv movie.mp4 --source zh-cn --target en
```

## 迁移到另一台机器

整个 `trans_video_cli\` 目录可直接打包拷贝（源码约 16 MB）：

1. 目标机准备任意 Python 3.8+（仅用于运行引导脚本）；uv、ffmpeg、项目所需的 Python 3.10 都由 `setup` 自动补齐；
2. 拷贝目录（排除 `.venv`、`models`、`tools\_cache`、`tmp`、`logs`）；
3. 运行 `setup`——已有缓存就复用，缺什么下什么；
4. 设置所需凭证，例如 `set DEEPSEEK_API_KEY=sk-xxxx`。

```bash
# Windows 拷贝
robocopy C:\path\to\trans_video_cli D:\backup\trans_video_cli /E /XD .venv models tmp logs __pycache__

# macOS / Linux 拷贝
rsync -a --exclude .venv --exclude models --exclude tmp --exclude logs \
  /path/to/trans_video_cli/ /path/to/backup/trans_video_cli/

# macOS / Linux 打包
tar --exclude=.venv --exclude=models --exclude=tmp --exclude=logs \
    -czf trans_video_cli.tar.gz trans_video_cli/
```

`.venv` 不随包分发（Windows 的 venv 含绝对路径）；模型与工具会在目标机首次 `setup` 时自动获取。`tools\_cache` 可以保留以加速离线重装。

## 设计要点（为什么不是直接调 cli.py）

1. **输出目录安全**：上游在每个任务开始时递归删除 `--output-dir`。封装脚本默认输出到输入同级的新目录 `<文件名>_translated/`，并拒绝“输入在输出目录内”等危险组合。
2. **渠道按名选择**：`--channel deepseek|ollama|openai_compatible|...`，不用记数字编号。
3. **凭证自动注入**：从 `DEEPSEEK_API_KEY` 等环境变量或 `--api-key` 写入 `params.json`，不打印密钥。
4. **安全的默认值**：ASR 默认 `large-v3-turbo`（上游默认 `tiny` 质量很差）；翻译渠道默认沿用 `params.json` 配置（上游默认 Google）。
5. **UTF-8 子进程**：避免中文 Windows 的 GBK 乱码。
6. **结果校验**：任务结束后列出实际产物；上游报成功但没有文件时返回非零退出码。

## 退出码

| 码 | 含义 |
|---:|---|
| 0 | 成功 |
| 1 | pyVideoTrans 任务失败 / `uv sync` 失败 |
| 2 | 前置检查失败（文件不存在、目录不安全、渠道名错误等） |

## 备注

- 该目录不修改 pyvideotrans 源码；配置写入运行时目录下的 `videotrans\params.json`。
- 分发包内不含任何 API Key（`setup` 会清空 `*_key`）。本仓库不跟踪运行后的 `params.json` / `cfg.json`（可能含 API Key 或机器相关路径）。
- 上游自带的 pytest 套件有大量已知失败，不要用它判断安装是否正常；以 `check` 和 `selftest` 为准。

## 许可证

本项目以 **GNU GPL v3.0** 发布，全文见 [`LICENSE`](LICENSE)。

- 原创封装层（`trans_cli.py`、`SKILL.md`、`references/`、启动器与本 README）由 huajielong 编写，以 GPL-3.0 发布。
- `runtime/pyvideotrans/` 是 [pyVideoTrans](https://github.com/jianchang512/pyvideotrans) v4.16 的源码，版权归其作者所有，同样采用 GPL-3.0；详见 [`runtime/pyvideotrans/LICENSE`](runtime/pyvideotrans/LICENSE) 和 [`NOTICE`](NOTICE)。

如果只是使用而不分发，按本文档安装即可；如果要再分发，请保留 `LICENSE`、`NOTICE` 与上游许可证文件。
