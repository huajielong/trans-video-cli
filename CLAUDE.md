# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目定位

本仓库不是 pyVideoTrans 本体，而是把 pyVideoTrans 封装成**可迁移、自包含 CLI 技能**的封装层：语音识别 → 字幕翻译 → AI 配音 → 合成视频，一条命令完成。日常修改和排查应聚焦封装层，而不是 `runtime/` 中的上游引擎。

三层结构：

- `trans.cmd` / `trans`：Windows / macOS·Linux 启动器，仅转发到封装脚本。
- `.claude/skills/trans-video-cli/scripts/trans_cli.py`：**本项目的核心代码**（约 1840 行，仅用 Python 标准库）。所有命令（setup / selftest / doctor / check / channels / voices / test-channel / vtv / stt / sts / tts）都在这里实现；负责安全校验、渠道解析、凭证注入、调用上游、结果校验。
- `runtime/pyvideotrans/`：包内自带的 pyVideoTrans 源码（当前上游 `v4.16`），通过 `uv run cli.py` 在 `.venv`（Python 3.10.19）中执行。`pyproject.toml` / `uv.lock` 也在这里。
- `.claude/skills/trans-video-cli/SKILL.md` 与 `references/`：技能定义与查阅资料；SKILL.md 是面向使用者的权威说明。
- `tools/`：按需下载的 uv、ffmpeg、Ollama；`tools/_cache/` 保存下载的压缩包，重装时优先复用。
- `runtime/pyvideotrans/{.venv,models,output,tmp,logs}`：生成状态，不随包分发（首次 `setup` 后 `.venv` 约 8 GB，模型另算）。

## 常用命令

Windows 使用 `trans.cmd`；macOS/Linux 使用 `./trans`。两者等价于：

```bash
python .claude/skills/trans-video-cli/scripts/trans_cli.py <command> ...
```

首次安装 / 修复运行时：

```bash
trans.cmd doctor                # 探测系统、GPU、已有工具与缓存
trans.cmd setup                 # 缺什么下什么，缓存优先；会执行 uv sync
trans.cmd check --gpu           # 检查安装并验证 torch / CUDA
trans.cmd selftest              # 端到端自检（9 个环节）
```

四个任务：

```bash
trans.cmd vtv "D:\videos\demo.mp4" --source zh-cn --target en
trans.cmd stt "D:\videos\demo.mp4"                          # 默认 large-v3-turbo
trans.cmd sts "D:\subs\demo.srt" --source zh-cn --target ja
trans.cmd tts "D:\subs\demo.srt" --target en --voice en-US-GuyNeural
```

渠道、音色与凭证：

```bash
trans.cmd channels                                              # 30 个翻译渠道 + 41 个 TTS 渠道
trans.cmd voices --language en --locale en-US
trans.cmd test-channel --channel deepseek                       # 用一次极小对话请求验证 Key
```

调试：

```bash
trans.cmd vtv demo.mp4 --source zh-cn --target en --dry-run     # 只打印将执行的命令
trans.cmd vtv demo.mp4 --source zh-cn --target en --json        # 机器可读结果
trans.cmd stt demo.mp4 --no-cuda                                # 强制 CPU
trans.cmd selftest --keep --json                                # 保留中间文件
```

`setup` 关键开关：`--torch cpu|cu128|auto`、`--models large-v3-turbo,tiny`、`--with-ollama`、`--no-download`（离线）、`--no-sync`（只复制不装依赖）、`--copy-from <dir>`、`--force`（重新复制源码，保留 `params.json`）、`--keep-pynini`。

**测试说明**：仓库没有 lint / 单元测试配置，`selftest` 是唯一的端到端验证。它没有按 stage 过滤的参数；只验证某一环时，直接对最小样例运行对应任务（例如两行 SRT 的 `tts`）或 `check --gpu`。修改封装脚本后至少跑一遍 `trans.cmd check` 和 `trans.cmd selftest`。上游 `runtime/pyvideotrans` 自带的 pytest 套件有大量已知失败，不要用它判断安装是否正常。

## 架构与执行流

### 封装脚本

1. `build_parser()` 解析子命令，分派到 `cmd_*`；`cmd_run()` 处理 vtv/stt/sts/tts。
2. `resolve_home_info()` 定位运行时，顺序为：
   `--home` > `PYVIDEOTRANS_HOME` > 包内 `runtime/pyvideotrans` > 外部 `~/pyvideotrans`。
3. `cmd_run()`：读取 `videotrans/params.json` → 解析翻译 / TTS 渠道 → `configure_channel()` 把 Key、模型、Base URL 写入 `params.json`（不会打印 Key）→ `resolve_outdir()` 安全检查 → 显式拼出 `uv run cli.py --task ...` 参数 → 本地 LLM 渠道自动启动 Ollama / 拉取模型 → 对输出目录做 `snapshot()` → 执行 → 用 `changed_files()` 校验产物 → 返回退出码。
4. 渠道名/编号表（`TRANSLATE_CHANNELS`、`CANONICAL`、`CHANNEL_CONFIG`、`TTS_CHANNELS`）必须与上游 `videotrans/translator/_constants.py`、`videotrans/tts/_constants.py` 保持一致。上游增删渠道时，同步修改封装脚本、`SKILL.md` 和 `references/channels.md`。

### setup 的初始化流程

1. `resolve_uv()`：PATH 或 `UV_BIN` 有就复用；否则下载到 `tools/uv.exe`（非 Windows 为 `tools/uv`）。
2. `resolve_ffmpeg()`：PATH → `tools/ffmpeg/bin/` → 下载；macOS 走 brew/port。
3. 复制 `COPY_ENTRIES` 到 `runtime/pyvideotrans`；新建复制会清空 `params.json` 的 `*_key` 并把 `cfg.json` 的 token / proxy / homedir 重置为可迁移值；更新模式（`--force`）保留已有 `params.json`。
4. 按 `nvidia-smi` 结果改写运行时 `pyproject.toml` 中 torch/torchaudio 的 index（`cu128` 或 CPU）。
5. 在没有 pynini 轮子的平台移除 `pynini` / `WeTextProcessing`（仅影响 MOSS TTS 文本规范化）。
6. `uv sync`（默认清华 PyPI 镜像；代理取 `--proxy`、`HTTPS_PROXY` 或 `git config --global http.proxy`）。
7. `--models` 预取 ASR 模型：本地缓存 → ModelScope → hf-mirror → huggingface.co + 代理。
8. `--with-ollama` 可选安装便携版 Ollama 并拉取 `qwen2.5:3b`。

### 上游流水线

`runtime/pyvideotrans/` 是未修改的上游代码。九个处理阶段为：预处理 → 语音识别 → 说话人分离 → 字幕翻译 → TTS 配音 → 音画对齐 → 二次识别 → 最终合成 → 收尾；对应 `videotrans/task/` 下的 `TransCreate`（vtv）、`SpeechToText`（stt）、`TranslateSrt`（sts）、`DubbingSrt`（tts）。封装脚本只负责选任务和参数，实际流水线、并行队列和配置数据类都在上游。

## 必须遵守的约束

1. **绝不让输入文件落在输出目录内。** 上游在任务开始时会 `shutil.rmtree(target_dir)`（`videotrans/task/trans_create.py:58`，`clear_cache` 默认开启），输入会被删掉。`resolve_outdir()` 会拒绝“输出目录包含输入”以及主目录、盘符根目录、运行时目录等危险目标。默认输出为输入同级的 `<文件名>_translated/`；目录非空时依次使用 `-2`、`-3` 后缀；显式 `--outdir` 非空时必须加 `--overwrite`（其内容会被删除）。
2. **优先用封装脚本，不要直接调 `runtime/pyvideotrans/cli.py`。** 上游默认 `--translate_type 0`（Google）、`--tts_type 0`（Edge）、`--model_name tiny`（识别质量很差），且不提供目录安全保护。封装脚本始终显式传参，并从 `params.json` 继承渠道配置。
3. **`params.json` 是运行时状态，可能含真实密钥。** 路径为 `runtime/pyvideotrans/videotrans/params.json`；不要提交、打包或把其中的 `*_key` 打印出来。新复制运行时时 `setup` 会清空 Key；`check` 与 `configure_channel` 均已做脱敏。分发前排除 `.venv`、`models`、`tools/_cache`、`tmp`、`logs` 以及含密钥的 `params.json`。
4. **不要修改 `runtime/pyvideotrans` 的引擎源码。** 它属于上游 vendored 代码，`setup --force` 会重新复制覆盖。`setup` 自身只会改写其中的 `pyproject.toml`（torch index、pynini 依赖）和 `params.json` / `cfg.json`。
5. **默认值约定**：ASR 默认 `large-v3-turbo`（可用 `TRANS_ASR_MODEL` 或 `--asr-model` 覆盖）；CUDA 默认开启（`--no-cuda` 关闭）；字幕默认硬字幕（`--subtitle-type 1`）；翻译渠道默认沿用 `params.json` 的 `translate_type`。
6. **退出码语义**：`0` 成功；`1` 上游任务失败或 `uv sync` 失败；`2` 封装层前置检查失败，或上游报成功但输出目录没有任何新增/更新文件。不要随意更改这些约定。
7. **子进程必须使用 UTF-8**：封装脚本为上游设置 `PYTHONUTF8=1`、`PYTHONIOENCODING=utf-8`、`PYTHONUNBUFFERED=1`，否则中文 Windows 的 GBK 控制台会乱码。
8. **已知上游限制**：单行 SRT + Edge-TTS 不会产生音频文件（`selftest` 的 SRT 特意使用两行；`tts` 命中单行时会打印警告）。DeepSeek 凭证不要用 `GET /models` 验证（有效 Key 也会假阴性），应使用 `test-channel` 的对话接口。
9. **工具路径**：`UV_BIN`、`FFMPEG_BIN`、`FFPROBE_BIN`、`OLLAMA_BIN` 可显式覆盖；`cmd_run()` 会把已提供的 ffmpeg / ollama 所在目录加入子进程 `PATH`，不会在任务阶段临时下载工具。

## 参考文档

- `.claude/skills/trans-video-cli/SKILL.md` — 技能完整用法、四条核心规则、命令表
- `references/channels.md` — 30 个翻译渠道 / 41 个 TTS 渠道及 `params.json` 字段、环境变量
- `references/languages.md` — 语言代码与默认 Edge 音色
- `references/models.md` — Whisper 模型体积、显存、速度与选型
- `references/troubleshooting.md` — 实测的错误对照表（初始化、输出目录、凭证、模型下载等）
- `runtime/pyvideotrans/docs/` — 上游架构、CLI、WebUI、扩展开发文档
