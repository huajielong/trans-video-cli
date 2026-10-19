---
name: trans-video-cli
description: Translate, dub and subtitle videos/audio with the locally installed pyVideoTrans (Whisper ASR + LLM translation + Edge-TTS). Use this skill whenever the user wants to translate a video or audio file into another language, generate subtitles from media, translate an existing SRT, or synthesize dubbing from subtitles — e.g. "把这个视频翻译成英文", "给视频加中文字幕", "字幕翻译", "提取字幕", "语音识别转文字", "视频配音", "换成日语", "translate this video to Japanese", "dub this clip", "make subtitles for this mp4", "transcribe this recording". Also use when configuring translation channels (DeepSeek / Ollama / OpenAI / relay), picking ASR models, or debugging a failed pyVideoTrans run.
---

# trans-video-cli

封装本地的 **pyVideoTrans**，把「语音识别 → 翻译 → 配音 → 合成视频」做成一条安全的命令。底层仍调用 `pyvideotrans/cli.py`，但补齐了上游 CLI 缺少的安全检查。

## 先决条件与首次安装

技能目录内自带一份 pyVideoTrans 源码（`<skill_dir>/vendor/pyvideotrans/`）。首次使用：

```bash
python <skill_dir>/scripts/trans_cli.py doctor     # 看看这台机器检测到什么
python <skill_dir>/scripts/trans_cli.py setup      # 一键初始化：缺什么下什么，有缓存就用缓存
python <skill_dir>/scripts/trans_cli.py check      # 自检
```

`setup` 是**按机器配置自动获取、缓存优先**的引导器：

| 依赖 | 处理方式 |
|---|---|
| uv | PATH 有就用；没有则下载到 `<skill_dir>/tools/uv.exe` |
| ffmpeg / ffprobe | PATH 有就用；`<skill_dir>/tools/ffmpeg/bin` 有就用；都没有才下载 |
| Python 3.10 | 由 uv 自动安装（系统已有则复用） |
| PyTorch | `--torch auto`（默认）检测 NVIDIA GPU：有 GPU 用 cu128，否则用 CPU 轮子 |
| ASR 模型 | `--models large-v3-turbo,tiny` 预取；先查技能内/外部安装的模型缓存，命中就复制，未命中才下载 |
| Ollama | 已安装则直接复用；`--with-ollama` 会下载便携版并拉取模型（体积较大） |
| PyPI / GitHub | 默认清华镜像；代理自动读 `HTTPS_PROXY` 或 git 配置 |

常用开关：

```bash
... setup --torch cpu            # 强制 CPU 版 torch（无 NVIDIA GPU 时省约 3 GB）
... setup --models large-v3-turbo  # 预取默认模型（缓存命中则不下载）
... setup --with-ollama          # 连 Ollama 一起装好并拉取 qwen2.5:3b
... setup --no-download          # 离线模式：缺什么就报错，不联网
... setup --no-sync              # 只做探测/迁移/复制，不装依赖
... setup --copy-from <dir>      # 从指定源码替换 vendor/pyvideotrans
... setup --force                # 重新执行配置与依赖安装（仅在给 --copy-from 时重新复制）
... setup --migrate-from <dir>   # 显式迁移旧布局的 models/tools/params
```

`setup` 会自动迁移旧版的 `runtime/pyvideotrans`（仅当同级存在本包启动器时自动识别）：移动 `models`、`logs`、`params.json`、`tools`，并用 uv 缓存重建 `.venv`；`uv sync` 成功后才删除旧状态。全局安装目录下若存在无关的 `~/runtime/pyvideotrans`，不会自动迁移，需显式传 `--migrate-from`。

安装位置解析顺序：`--home` > `PYVIDEOTRANS_HOME` > 技能内 `<skill_dir>/vendor/pyvideotrans` > 外部 `~/pyvideotrans`。

`<skill_dir>` 是本 SKILL.md 所在目录。脚本只用 Python 标准库，用任意 Python 3.10+ 运行即可。

## 验证是否可用

```bash
python <skill_dir>/scripts/trans_cli.py selftest
```

自动生成测试素材并依次验证 9 个环节：运行时、uv、Python/torch、ffmpeg、ffmpeg 编码、Edge-TTS 联网、语音识别、语音合成、翻译（仅当已配置可用渠道）。全部通过时输出：

```
RESULT: 9 passed, 0 failed, 0 skipped in 43.8s
```

加 `--keep` 保留中间文件，加 `--json` 输出机器可读结果。任何一项 FAIL 都会以非零退出码结束，并打印该环节的错误摘要。

## 可迁移部署

**技能目录本身就是分发包**：单独复制 `<skill_dir>/`（即 `.claude/skills/trans-video-cli/`）到目标机的 `~/.claude/skills/` 即可（源码约 19 MB，其中 pyVideoTrans 源码约 16 MB）：

1. 拷贝技能目录，排除 `tools/` 和 `vendor/pyvideotrans/` 下的生成状态（`.venv`、`models`、`output`、`tmp`、`logs`、`params.json`、`cfg.json` 等）；
2. 目标机运行 `<skill_dir>/scripts/trans_cli.py setup`——自动补齐 uv/ffmpeg/Python/PyTorch，缓存命中则跳过下载；
3. 从外部源码**新建复制**时，`setup` 会清空 `params.json` 里的 `*_key`；技能目录内已有或迁移过来的 `params.json` 会保留。使用前也可通过环境变量（如 `DEEPSEEK_API_KEY`）或 `--api-key` 提供凭证。

`.venv` 不随包分发（Windows 的 venv 含绝对路径）；模型与工具在目标机首次 `setup` 时自动获取。旧布局（1.2 及更早）可以用 `setup --migrate-from <旧包根>` 迁移。

## 跨平台支持

| 能力 | Windows | Linux x86_64 | Linux arm64 | macOS |
|---|---|---|---|---|
| 技能内 vendor 运行时 + venv | ✅ | ✅ | ✅ | ✅ |
| uv 自动获取 | ✅ | ✅ | ✅ | ✅ |
| ffmpeg 自动获取 | ✅ 下载静态包 | ✅ 下载静态包 | ✅ 下载静态包 | ⚠️ 有 brew/port 时自动安装，否则给出命令 |
| PyTorch | cu128 / CPU | cu128 / CPU | CPU | CPU |
| Ollama 自动获取 | ✅ | ✅ | ✅ | ⚠️ 需手动安装 |
| pynini / WeTextProcessing | ✅ | ✅ | ⚠️ 自动跳过 | ⚠️ 自动跳过 |
| ASR / 翻译 / Edge-TTS / 合成 | ✅ | ✅ | ✅ | ✅ |

说明：

- `pynini` 只有 Windows 与 Linux x86_64 的预编译轮子。其他平台 `setup` 会自动移除 `pynini` 与 `WeTextProcessing`——它们只用于 MOSS TTS 的文本规范化，不影响主流程；可用 `--keep-pynini` 强制保留。
- macOS 的 ffmpeg 通过 `brew install ffmpeg` / `port install ffmpeg` 安装；Ollama 请从官网安装。
- `--torch auto` 会按平台与 NVIDIA GPU 自动选择 cu128 或 CPU 轮子。
- 启动器：仓库根目录提供 `trans.cmd`（Windows）与 `./trans`（macOS/Linux），均转发到同一个脚本。只安装了技能目录时，直接调用 `python <skill_dir>/scripts/trans_cli.py ...`。

## 跨平台启动器

```bash
# Windows
trans.cmd selftest
trans.cmd vtv movie.mp4 --source zh-cn --target en

# macOS / Linux
./trans selftest
./trans vtv movie.mp4 --source zh-cn --target en
```

## 四条必须遵守的规则

1. **永远不要把输入文件放进输出目录。** 上游在每个任务开始时对 `--output-dir` 执行 `shutil.rmtree`（`--clear_cache` 默认开启）。包装脚本会拒绝这种用法，也会拒绝与技能安装目录重叠的输出目录，并且默认把结果写到输入的**同级新目录** `<文件名>_translated/`。
2. **优先用这个包装脚本，不要直接调 `cli.py`。** 上游 CLI 的 `--translate_type` / `--tts_type` / `--model_name` 都有不安全的默认值（分别是 Google、Edge、**tiny**），包装脚本会从 `params.json` 读配置并显式传参。
3. **默认 ASR 模型是 `large-v3-turbo`。** 准确率接近 `large-v3`，体积约 1.6 GB、速度约为其两倍，适合作为默认值。追求极致准确率用 `--asr-model large-v3`（约 3 GB）；`tiny` / `base` 只适合快速验证链路。
4. **不熟悉的渠道先跑 `test-channel` 验证凭证。** 尤其 DeepSeek：用 `GET /models` 验 Key 会得到**假阴性**（有效 Key 也报 invalid），必须用对话接口验证。见 `references/troubleshooting.md`。

## 命令一览

| 命令 | 作用 | 典型用法 |
|---|---|---|
| `setup` | 初始化/更新运行时（按机器配置自动下载，缓存优先） | `trans_cli.py setup` |
| `selftest` | 端到端自检（ffmpeg / ASR / TTS / 翻译） | `trans_cli.py selftest` |
| `doctor` | 探测系统、GPU、工具与缓存状态 | `trans_cli.py doctor` |
| `check` | 检查安装 / 显示当前渠道配置 | `trans_cli.py check` |
| `channels` | 列出所有翻译 / TTS 渠道及编号 | `trans_cli.py channels` |
| `voices` | 列出 Edge-TTS 音色 | `trans_cli.py voices --language en --locale en-US` |
| `test-channel` | 发一条极小的对话请求验证凭证 | `trans_cli.py test-channel --channel deepseek` |
| `vtv` | 视频翻译：识别 → 翻译 → 配音 → 合成 | `trans_cli.py vtv movie.mp4 --source zh-cn --target en` |
| `stt` | 音视频 → SRT 字幕 | `trans_cli.py stt talk.mp4`（默认 large-v3-turbo） |
| `sts` | 翻译已有 SRT | `trans_cli.py sts subs.srt --source zh-cn --target ja` |
| `tts` | SRT → 配音音频 | `trans_cli.py tts subs.srt --target en --voice en-US-GuyNeural` |

### 最常用的三条

```bash
# 1) 完整视频翻译（中文 → 英文），自动选目标语言默认音色，GPU 加速
python <skill_dir>/scripts/trans_cli.py vtv "D:\videos\demo.mp4" --source zh-cn --target en

# 2) 只要字幕（不翻译、不配音），大模型保证准确率
python <skill_dir>/scripts/trans_cli.py stt "D:\videos\demo.mp4"

# 3) 只翻译已有字幕
python <skill_dir>/scripts/trans_cli.py sts "D:\subs\demo.srt" --source zh-cn --target ja
```

加 `--dry-run` 可以只看将要执行的命令，不真正运行；加 `--json` 得到机器可读的结果摘要。

## 选择翻译渠道

不传 `--channel` 时，使用 `params.json` 里的 `translate_type`（当前配置）。常用渠道：

| 渠道 | `--channel` | 说明 |
|---|---|---|
| DeepSeek | `deepseek` | 需要 `deepseek_key`；模型常用 `deepseek-flash` |
| 本地 Ollama | `ollama` | 无需 Key；默认 `qwen2.5:3b`。会自动复用/启动 Ollama，缺模型时自动拉取；`--no-auto-ollama` 可关闭 |
| 任意 OpenAI 兼容中转 | `openai_compatible` | 配合 `--api-base` / `--api-key` / `--model` |
| OpenAI | `chatgpt` | 需要 `chatgpt_key`，可用 `--api-base` 指向中转 |
| 智谱 / 阿里百炼 / 硅基流动 | `zhipuai` / `bailian` / `siliconflow` | 需要对应 Key |
| 免费（Google / Microsoft） | `google` / `microsoft` | 无 Key，但国内常不可达 |

切换渠道并写入凭证（会写入 `<skill_dir>/vendor/pyvideotrans/videotrans/params.json`，脚本不会把 Key 打印出来）：

```bash
# 方式 A：Key 已在环境变量里（推荐）
set DEEPSEEK_API_KEY=sk-xxxx
python <skill_dir>/scripts/trans_cli.py test-channel --channel deepseek
python <skill_dir>/scripts/trans_cli.py vtv demo.mp4 --source zh-cn --target en --channel deepseek

# 方式 B：显式传入
python <skill_dir>/scripts/trans_cli.py vtv demo.mp4 --source zh-cn --target en \
  --channel deepseek --api-key sk-xxxx --model deepseek-flash

# 方式 C：本地 Ollama
python <skill_dir>/scripts/trans_cli.py vtv demo.mp4 --source zh-cn --target en --channel ollama

# 方式 D：第三方中转（OpenAI 兼容）
python <skill_dir>/scripts/trans_cli.py vtv demo.mp4 --source zh-cn --target en \
  --channel openai_compatible --api-base https://relay.example.com/v1 --api-key sk-xxxx --model gpt-4o-mini
```

完整的 30 个翻译渠道、41 个 TTS 渠道及各自的配置字段见 `references/channels.md`。

## 配音与字幕

- **音色**：`vtv` 不传 `--voice` 时，按目标语言选默认 Edge 音色（en→`en-US-GuyNeural`、zh-cn→`zh-CN-XiaoxiaoNeural`…，见 `references/languages.md`）。用 `voices` 命令查其他音色。
- **字幕类型**（`--subtitle-type`）：`0` 不嵌入、`1` 硬字幕（默认）、`2` 软字幕、`3` 双硬、`4` 双软。想要干净画面就传 `0`；想让播放器可开关字幕就传 `2`。
- **TTS 渠道**：`--tts-channel edge`（默认，免费）或其他本地/云渠道，编号见 `references/channels.md`。

## 输出文件

任务结束后，包装脚本会列出新增/更新的文件。典型产物：

| 任务 | 产物（已实测） |
|---|---|
| `vtv` | `<原名>.mp4`（译制视频）、`<目标语言>.srt`、`<目标语言>.m4a`（配音）、`<源语言>.srt` / `.m4a` |
| `stt` | `<输入文件名>.srt`（例：`talk.srt`） |
| `sts` | `<源语言>.<目标语言>.srt`（例：`zh-cn.en.srt`） |
| `tts` | `<目标语言>.wav`（例：`en.wav`） |

退出码：`0` 成功；`1` 上游任务失败（日志路径会打印）；`2` 包装脚本的前置检查失败。

## 常见问题

遇到失败先看 `references/troubleshooting.md`，其中记录了实测踩过的坑：

- `xxx is not exists` → 输入被当成输出目录内容删掉了（clear_cache）
- `Missing credentials` → 本地 LLM 渠道的 `localllm_key` 不能为空
- DeepSeek Key "invalid" → 别用 `/models` 验，用 `test-channel`
- 日志中文乱码 → 包装脚本已强制 `PYTHONUTF8=1`
- 模型下载慢 / 超时 → huggingface 自动回落 hf-mirror，faster-whisper 走 ModelScope

## 参考文件

- `references/channels.md` — 全部翻译 / TTS 渠道、配置字段、Key 环境变量
- `references/languages.md` — 语言代码、默认 Edge 音色
- `references/models.md` — Whisper 模型尺寸 / 速度 / 显存建议
- `references/troubleshooting.md` — 错误对照与处理方法
