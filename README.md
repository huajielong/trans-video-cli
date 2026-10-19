# trans-video-cli

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

把 [pyVideoTrans](https://github.com/jianchang512/pyvideotrans) 封装成一个**可迁移、自包含的 CLI 技能**：语音识别 → 字幕翻译 → AI 配音 → 合成视频，一条命令完成。

技能目录内自带一份 pyVideoTrans 源码，初始化后即可脱离外部安装运行。**`.claude/skills/trans-video-cli/` 本身是唯一分发单元**：单独复制它并在目标机运行 `setup` 即可使用。

## 目录结构

```
trans_video_cli\
├── README.md
├── trans / trans.cmd                  ← 可选启动器（仅仓库根目录；转发到技能脚本）
└── .claude\
    └── skills\
        └── trans-video-cli\           ← 唯一分发单元
            ├── SKILL.md               ← 技能定义（Claude Code 自动加载）
            ├── scripts\
            │   └── trans_cli.py       ← 封装脚本（仅标准库）
            ├── references\
            │   ├── channels.md        ← 30 个翻译渠道 + 41 个 TTS 渠道
            │   ├── languages.md       ← 语言代码 + 默认音色
            │   ├── models.md          ← Whisper 模型选择
            │   └── troubleshooting.md ← 错误对照表
            ├── tools\                 ← setup 按需下载（未跟踪）
            │   ├── uv.exe  ffmpeg\  ollama\
            │   └── _cache\            ← 已下载的压缩包，重装/迁移时直接复用
            └── vendor\
                └── pyvideotrans\      ← 自带的 pyVideoTrans 源码（约 16 MB，git 跟踪）
                    ├── cli.py         ← 实际被调用的入口
                    ├── videotrans\    ← 引擎
                    ├── .venv\         ← setup 后生成（约 8.3 GB，不随包分发）
                    ├── models\        ← ASR 模型缓存
                    └── output\ tmp\ logs\
```

`.claude\skills\` 是 Claude Code 的自动发现路径；项目级/全局安装方式见下文「在 Agent 中安装与使用」。下文用 `C:\path\to\trans_video_cli`（macOS/Linux 为 `/path/to/trans_video_cli`）指代仓库根目录，用 `<skill_dir>` 指代 `.claude\skills\trans-video-cli`。

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
| uv | PATH 有就复用；没有则下载到 `<skill_dir>\tools\uv.exe` |
| ffmpeg / ffprobe | PATH 有就复用；`<skill_dir>\tools\ffmpeg\bin` 有就复用；都没有才下载并解压 |
| Python 3.10 | uv 自动安装；已有版本则复用 |
| PyTorch | 检测 NVIDIA GPU：有则 cu128，无则 CPU 轮子（`--torch cpu/cu128` 可强制） |
| ASR 模型 | `--models large-v3-turbo,tiny` 预取；先查技能内与外部安装的模型缓存，未命中才下载 |
| Ollama | 已安装则复用；`--with-ollama` 下载便携版并拉取模型 |
| PyPI / GitHub | 默认清华镜像（`--index-url` 覆盖）；代理自动读 `HTTPS_PROXY` 或 git 配置 |

常用开关：

```bash
... setup --torch cpu            # 强制 CPU 版 torch
... setup --models large-v3-turbo  # 预取默认模型（缓存命中则跳过）
... setup --with-ollama          # 连 Ollama 一起装好并拉取 qwen2.5:3b
... setup --no-download          # 离线模式：缺什么就报错，不联网
... setup --no-sync              # 只探测/迁移/复制，不装依赖
... setup --copy-from <dir>      # 从指定源码替换 vendor/pyvideotrans
... setup --force                # 重新执行配置与依赖安装（仅在给 --copy-from 时重新复制源码）
... setup --migrate-from <dir>   # 显式迁移旧布局的 models/tools/params
```

`setup` 会自动迁移旧版布局：如果检测到 `runtime/pyvideotrans`（仅当同级存在本包启动器时自动识别），会把 `models`、`logs`、`videotrans/params.json`、`tools` 移到技能目录内，并用本机 uv 缓存重建 `.venv`；只有 `uv sync` 成功后才删除旧状态。全局安装目录下若出现无关的 `~/runtime/pyvideotrans`，不会自动迁移，需显式传 `--migrate-from`。

凭证说明：从外部 checkout **新建复制**时，`setup` 会清空 `params.json` 中所有 `*_key` 字段；技能目录内已有的 `params.json`（包括迁移过来的）会保留。分发前仍应排除 `params.json` / `cfg.json`。使用前也可以通过环境变量或 `--api-key` 提供凭证。

环境路径解析顺序：

```
--home  >  PYVIDEOTRANS_HOME  >  <skill_dir>\vendor\pyvideotrans  >  外部 ~/pyvideotrans
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
... setup --copy-from <dir>                               # 替换 vendor 源码
... setup --migrate-from <dir>                            # 迁移旧布局状态
... setup --no-sync                                       # 只迁移/复制，不装依赖
... setup --force                                         # 重新执行配置与依赖安装
... check                                                 # 自检
... channels                                              # 列出渠道和编号
... voices --language en --locale en-US                   # 列出音色
... test-channel --channel deepseek                       # 验证 API Key
... vtv demo.mp4 --source zh-cn --target en --dry-run     # 只看将要执行的命令
```

## 在 Agent 中安装与使用

本项目本身就是一个 Claude Code 技能：`SKILL.md` 描述何时触发、如何调用，`references/` 提供渠道、语言、模型和排错资料。注册后，Agent 可以直接把自然语言需求转成 CLI 命令。

### 1. 在线安装技能

在任意 Agent（或终端）里执行下面的流程，从 GitHub 拉取技能并安装到用户级技能目录。Claude Code 会自动发现 `~/.claude/skills/`，安装后所有项目都可使用。

需要 `git` 与 Python 3.10+；uv、ffmpeg、PyTorch 和模型由后续的 `setup` 自动补齐。

```bash
# macOS / Linux
TMP_DIR="$(mktemp -d)"
git clone --depth 1 https://github.com/huajielong/trans-video-cli.git "$TMP_DIR/trans-video-cli"
mkdir -p ~/.claude/skills/trans-video-cli
cp -R "$TMP_DIR/trans-video-cli/.claude/skills/trans-video-cli/." ~/.claude/skills/trans-video-cli/
rm -rf "$TMP_DIR"
```

```bat
:: Windows（cmd）
set "TMPCLONE=%TEMP%\trans-video-cli-install"
if exist "%TMPCLONE%" rmdir /S /Q "%TMPCLONE%"
git clone --depth 1 https://github.com/huajielong/trans-video-cli.git "%TMPCLONE%"
if not exist "%USERPROFILE%\.claude\skills\trans-video-cli" mkdir "%USERPROFILE%\.claude\skills\trans-video-cli"
xcopy /E /I /Y "%TMPCLONE%\.claude\skills\trans-video-cli\*" "%USERPROFILE%\.claude\skills\trans-video-cli\"
rmdir /S /Q "%TMPCLONE%"
```

安装位置：`~/.claude/skills/trans-video-cli/`。重复安装会覆盖源码，但保留已有的 `.venv`、模型和 `params.json` 等生成状态。

也可以直接把这段指令交给 Agent：「从 GitHub 安装 trans-video-cli 技能到 `~/.claude/skills`，然后运行 setup」。

### 2. 在 Agent 中首次初始化

对 Agent 说“初始化 trans-video-cli 运行时”，或让它执行：

```bash
# macOS / Linux
python3 ~/.claude/skills/trans-video-cli/scripts/trans_cli.py doctor
python3 ~/.claude/skills/trans-video-cli/scripts/trans_cli.py setup
python3 ~/.claude/skills/trans-video-cli/scripts/trans_cli.py check --gpu
python3 ~/.claude/skills/trans-video-cli/scripts/trans_cli.py selftest
```

```bat
:: Windows
python "%USERPROFILE%\.claude\skills\trans-video-cli\scripts\trans_cli.py" doctor
python "%USERPROFILE%\.claude\skills\trans-video-cli\scripts\trans_cli.py" setup
python "%USERPROFILE%\.claude\skills\trans-video-cli\scripts\trans_cli.py" check --gpu
python "%USERPROFILE%\.claude\skills\trans-video-cli\scripts\trans_cli.py" selftest
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

也可以显式调用技能，或让其他 Agent 直接执行命令：

```text
/trans-video-cli vtv "D:\videos\demo.mp4" --source zh-cn --target en
```

```bat
:: Windows
python "%USERPROFILE%\.claude\skills\trans-video-cli\scripts\trans_cli.py" stt "D:\videos\demo.mp4"
```

```bash
# macOS / Linux
python3 ~/.claude/skills/trans-video-cli/scripts/trans_cli.py stt "/path/to/demo.mp4"
```

建议让 Agent 先加 `--dry-run` 查看将要执行的命令；长任务加 `--json` 获取结构化结果。

> 安全提示：Agent 需要获得执行 `python` / `uv` / `ffmpeg` 的权限，请逐条批准，不要使用跳过权限的模式。包装脚本会拒绝把输入文件放进输出目录，也会拒绝输出目录与技能安装目录重叠；不要绕过它直接调用上游 `cli.py`。

## 跨平台支持

| 能力 | Windows | Linux x86_64 | Linux arm64 | macOS |
|---|---|---|---|---|
| 技能内 vendor 运行时 + venv | ✅ | ✅ | ✅ | ✅ |
| uv 自动获取 | ✅ | ✅ | ✅ | ✅ |
| ffmpeg 自动获取 | ✅ | ✅ | ✅ | ⚠️ brew/port |
| PyTorch | cu128 / CPU | cu128 / CPU | CPU | CPU |
| Ollama 自动获取 | ✅ | ✅ | ✅ | ⚠️ 手动安装 |
| pynini / WeTextProcessing | ✅ | ✅ | ⚠️ 自动跳过 | ⚠️ 自动跳过 |
| 主流程（识别/翻译/配音/合成） | ✅ | ✅ | ✅ | ✅ |

平台启动器（仅仓库根目录提供）：

```bash
# Windows
trans.cmd selftest
trans.cmd vtv movie.mp4 --source zh-cn --target en

# macOS / Linux
./trans selftest
./trans vtv movie.mp4 --source zh-cn --target en
```

只安装了技能目录、没有启动器时，直接调用 `python <skill_dir>/scripts/trans_cli.py ...`。

## 迁移到另一台机器

技能目录 `.claude/skills/trans-video-cli/` 可直接打包拷贝（源码约 19 MB，其中 pyVideoTrans 源码约 16 MB）：

1. 目标机准备任意 Python 3.10+（仅用于运行引导脚本）；uv、ffmpeg、项目所需的 Python 3.10 都由 `setup` 自动补齐；
2. 拷贝技能目录，排除 `tools/` 和 `vendor/pyvideotrans/` 下的生成状态（`.venv`、`models`、`output`、`tmp`、`logs`、`params.json`、`cfg.json` 等）；
3. 运行 `setup`——已有缓存就复用，缺什么下什么；
4. 设置所需凭证，例如 `set DEEPSEEK_API_KEY=sk-xxxx`。

```bat
:: Windows 拷贝
robocopy "C:\path\to\trans_video_cli\.claude\skills\trans-video-cli" ^
  D:\backup\trans-video-cli /E ^
  /XD .venv models output tmp logs tools __pycache__ ^
  /XF params.json params.json.bak params.json.tmp cfg.json codec.json languages.json camb_languages.json

# macOS / Linux 拷贝
rsync -a \
  --exclude .venv --exclude models --exclude output --exclude tmp \
  --exclude logs --exclude tools --exclude __pycache__ \
  --exclude params.json --exclude cfg.json --exclude codec.json \
  --exclude languages.json --exclude camb_languages.json \
  /path/to/trans_video_cli/.claude/skills/trans-video-cli/ \
  /path/to/backup/trans-video-cli/

# macOS / Linux 打包
tar --exclude=.venv --exclude=models --exclude=output --exclude=tmp \
    --exclude=logs --exclude=tools --exclude=__pycache__ \
    --exclude=params.json --exclude=cfg.json --exclude=codec.json \
    --exclude=languages.json --exclude=camb_languages.json \
    -czf trans-video-cli.tar.gz -C /path/to/trans_video_cli/.claude/skills trans-video-cli
```

`.venv` 不随包分发（Windows 的 venv 含绝对路径）；模型与工具会在目标机首次 `setup` 时自动获取。`tools/_cache` 可以保留以加速离线重装。

如果旧机器仍是 1.2 及更早的仓库布局，直接在新技能目录运行 `setup`，或使用 `setup --migrate-from <旧包根或旧 pyvideotrans 目录>` 迁移模型、工具和凭证。

## 设计要点（为什么不是直接调 cli.py）

1. **输出目录安全**：上游在每个任务开始时递归删除 `--output-dir`。封装脚本默认输出到输入同级的新目录 `<文件名>_translated/`，并拒绝“输入在输出目录内”、输出目录与技能目录重叠等危险组合。
2. **渠道按名选择**：`--channel deepseek|ollama|openai_compatible|...`，不用记数字编号。
3. **凭证自动注入**：从 `DEEPSEEK_API_KEY` 等环境变量或 `--api-key` 写入 `params.json`，不打印密钥。
4. **安全的默认值**：ASR 默认 `large-v3-turbo`（上游默认 `tiny` 质量很差）；翻译渠道默认沿用 `params.json` 配置（上游默认 Google）。
5. **UTF-8 子进程**：避免中文 Windows 的 GBK 乱码。
6. **结果校验**：任务结束后列出实际产物；上游报成功但没有文件时返回非零退出码。
7. **自包含布局**：源码、工具和运行状态都在技能目录内，单独复制即可迁移；旧布局由 `setup` 自动/显式迁移。

## 退出码

| 码 | 含义 |
|---:|---|
| 0 | 成功 |
| 1 | pyVideoTrans 任务失败 / `uv sync` 失败 |
| 2 | 前置检查失败（文件不存在、目录不安全、渠道名错误等） |

## 备注

- 该目录不修改 pyvideotrans 源码；配置写入 `<skill_dir>\vendor\pyvideotrans\videotrans\params.json`。
- 分发包内不含任何 API Key（从外部源码新建复制或首次分发时会清空 `*_key`）。本仓库不跟踪运行后的 `params.json` / `cfg.json`（可能含 API Key 或机器相关路径）。
- 上游自带的 pytest 套件有大量已知失败，不要用它判断安装是否正常；以 `check` 和 `selftest` 为准。

## 许可证

本项目以 **GNU GPL v3.0** 发布，全文见 [`LICENSE`](LICENSE)。

- 原创封装层（`trans_cli.py`、`SKILL.md`、`references/`、启动器与本 README）由 huajielong 编写，以 GPL-3.0 发布。
- `.claude/skills/trans-video-cli/vendor/pyvideotrans/` 是 [pyVideoTrans](https://github.com/jianchang512/pyvideotrans) v4.16 的源码，版权归其作者所有，同样采用 GPL-3.0；详见 [`vendor/pyvideotrans/LICENSE`](.claude/skills/trans-video-cli/vendor/pyvideotrans/LICENSE) 和 [`NOTICE`](NOTICE)。

如果只是使用而不分发，按本文档安装即可；如果要再分发，请保留 `LICENSE`、`NOTICE` 与上游许可证文件。
