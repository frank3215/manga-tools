# manga-tools

macOS（Apple Silicon / Metal）上的**本地漫画翻译流水线**：用
[manga-image-translator](https://github.com/zyddnys/manga-image-translator) 做
「文字检测 → OCR → 擦字 → 嵌字」，用本地跑的 **Sakura-7B-LNovel**（llama.cpp + Metal，
OpenAI 兼容接口）做日→中翻译。全程离线，不依赖任何云端翻译 API。

本仓库只放**脚本与配置**：模型、预编译二进制、上游仓库、翻译产物一律不入库（见
[`.gitignore`](.gitignore)）。

## 处理流程

```
输入作品目录（每部作品一个子目录，内含 *.jpg）
        │
        ▼
manga_translator local ──┬─ 文字检测 (detector: default, detection_size 2048)
                         ├─ OCR        (ocr: mocr)
                         ├─ 翻译       (translator: sakura → http://127.0.0.1:8080/v1)
                         ├─ 擦字       (inpainter: lama_large)
                         └─ 嵌字       (render: default, 自动字号/方向)
        │
        ▼
输出目录（保持同名文件），同时把「日文 => 中文」逐行写进 logs/<作品名>.log
```

翻译质量的关键在翻译器：Sakura 是专门针对轻小说/漫画日译中微调的模型，比通用 NLLB
在漫画口语、拟声词、人称上表现好得多，这也是整条流水线要本地跑 LLM 的原因。

## 目录结构

```
manga-tools/
├── config/
│   ├── sakura-config.json      # 生产配置：sakura 翻译器 + mocr + lama_large
│   └── trial-config.json       # 对照配置：nllb 翻译器 + 48px OCR（做 A/B 对比用）
├── scripts/                    # 全部可执行脚本，见下表
├── patches/
│   └── manga-image-translator-sakura-fix.patch   # 对上游 sakura 翻译器的两处修复
├── .githooks/pre-commit        # 第二道防线：拦截图片/模型/大文件入库
├── requirements-norust.txt     # 上游 requirements 去掉 Rust 轮子依赖后的版本
└── (manga-image-translator/)   # 上游仓库，需自行 clone，已被 .gitignore 排除
```

## 环境要求

| 项 | 要求 |
| --- | --- |
| 系统 | macOS，Apple Silicon（Metal 加速） |
| Python | 3.11（由 `uv` 管理，装在 `manga-image-translator/.venv`） |
| 工具 | [`uv`](https://docs.astral.sh/uv/)、`curl`、`git` |
| 磁盘 | 约 6 GB（模型 4.6 GB + 依赖与模型缓存） |
| 网络 | 首次下载模型/二进制需要访问 GitHub 与 HuggingFace；国内建议挂代理 |

## 快速开始

```bash
# 0) 取上游代码（本仓库不含它），并启用防误提交钩子
git clone https://github.com/zyddnys/manga-image-translator.git \
  ~/manga-tools/manga-image-translator
git config core.hooksPath .githooks

# 1) 建虚拟环境、装依赖
bash scripts/setup.sh

# 2) 下载 llama.cpp 预编译包 + Sakura 模型（支持断点续传，可反复执行）
PROXY=http://127.0.0.1:7890 bash scripts/download-model.sh

# 3) 起翻译服务（前台，占用 :8080），另开一个终端跑后续步骤
bash scripts/serve-sakura.sh
#    长时间批量跑建议改用守护模式：
#    bash scripts/supervise-sakura.sh &

# 4) 冒烟验证：先拿一部作品试一下
FILTER='^某作品目录名$' bash scripts/validate.sh

# 5) 批量翻译（默认读 $HOME/Downloads/gallery-dl/kemono/fanbox/25664）
SRC_ROOT=/path/to/works bash scripts/run-full.sh

# 6) 出汇总报告（--wait 会先等批量任务结束）
bash scripts/summary.sh --wait
```

## 脚本一览

| 脚本 | 作用 |
| --- | --- |
| `scripts/setup.sh` | 建 `.venv`、装 `requirements-norust.txt`、尝试装 Rust 加速轮子 |
| `scripts/download-model.sh` | 下载 llama.cpp（`b11056` arm64）与 Sakura-7B Q4_K_M GGUF，带 `-C -` 续传 |
| `scripts/serve-sakura.sh` | 启动 `llama-server`，OpenAI 兼容接口监听 `:8080` |
| `scripts/supervise-sakura.sh` | 守护进程：`/health` 不 ok 就重启服务，事件写 `supervisor.log` |
| `scripts/translate-all.sh` | **主驱动**：断点续跑、健康检查、多轮重试、逐作品判成败 |
| `scripts/run-full.sh` | 跑全部作品（`caffeinate` 防休眠） |
| `scripts/run-preview.sh` | 只跑 `FILTER` 命中的作品，快速验证改动 |
| `scripts/validate.sh` | 强制要求 `FILTER`，单轮冒烟验证 |
| `scripts/trial.sh` | 单目录试译，`--save-text` 并把译文打到终端 |
| `scripts/summary.sh` | 汇总：进度、产出张数、失败作品、译文抽样、磁盘占用 |

## 参数速查

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `SRC_ROOT` | `$HOME/Downloads/gallery-dl/kemono/fanbox/25664` | 作品根目录，每个子目录一部作品 |
| `OUTDIR` | `<repo>/out` | 译文输出根目录 |
| `LOGDIR` | `<repo>/logs` | 每部作品的运行日志 |
| `PAR` | `1` | 并发数。服务端 `-np 1`，调大只是排队，**不建议 >1** |
| `PASSES` | `3` | 失败作品的最大重试轮数 |
| `FILTER` | `.` | 作品目录名正则 |
| `CFG` | `<repo>/config/sakura-config.json` | 传给 `manga_translator --config-file` |
| `LLAMA_DIR` | `<repo>/llama-b11056` | llama.cpp 解压目录 |
| `MODEL` | `<repo>/sakura-7b-lnovel-v0.9-Q4_K_M.gguf` | GGUF 路径 |
| `PROXY` | 空 | 形如 `http://127.0.0.1:7890`，仅下载脚本使用 |
| `SAKURA_API_BASE` | `http://127.0.0.1:8080/v1` | 上游 sakura 翻译器读取的服务地址 |
| `SAKURA_VERSION` | `0.9` | 提示词版本，需与模型代次一致 |

`translate-all.sh` 判定「这部作品成功」的条件是三件事同时成立：进程退出码为 0、
输出图片数 ≥ 输入图片数、日志里没有 `Traceback` / `RuntimeError` / `Sakura API请求失败` /
`Error during translating`。已跑完的作品（输出数 ≥ 输入数）直接 `SKIP`，所以脚本可以
随时 Ctrl-C 再重跑，不会重复劳动。

## 上游补丁

`patches/manga-image-translator-sakura-fix.patch` 修的是 `manga_translator/translators/sakura.py`：

1. `_handle_translation_request` 的返回值先做 `str()` 兜底，避免返回 list 时上层字符串
   拼接抛 `TypeError`；
2. 重试耗尽后**不再 `return prompt`**，改为抛 `RuntimeError`。原实现会静默返回未翻译的
   原文，产出「看起来成功、其实没翻」的图片；改抛异常后这张图会明确失败，交给外层
   `translate-all.sh` 重试。

应用方式：

```bash
cd ~/manga-tools/manga-image-translator
git apply ../patches/manga-image-translator-sakura-fix.patch
```

补丁基于上游 commit `95227a2`（`zyddnys/manga-image-translator`）。

`requirements-norust.txt` 与上游 `requirements.txt` 只差一行：去掉了
`rusty-manga-image-translator`。该 Rust 加速轮子在 Apple Silicon + Python 3.11 上经常装不上，
且它的依赖解析会拖垮整批安装，所以从清单里拆出来由 `setup.sh` 单独尝试安装（失败仅告警，
纯 Python 路径照常可用）。

## 常见问题

**输出图片是原图、文字没变？**
十有八九是 Sakura 服务挂了而补丁未生效（静默返回原文）。确认 `curl -s
http://127.0.0.1:8080/health` 返回 `{"status":"ok"}`，并检查 `logs/<作品>.log` 里有没有
`Sakura API请求失败`。

**服务跑一会儿就掉线？**
用 `scripts/supervise-sakura.sh` 守护，它会在健康检查失败时自动拉起并记录到
`supervisor.log`。OOM 时把 `NGL` 调低或换更小量化的模型。

**首轮很慢？**
首轮要下载 manga-image-translator 的检测/擦字模型（约几百 MB）并预热 Metal，后续作品
会明显变快。

**能并发跑吗？**
可以，但不划算：`llama-server` 起的是 `-np 1`（单 slot），并发请求只会排队，还容易把
显存/内存压爆。作者实测 `PAR=1` 最稳。

## 不入库的内容

本仓库只放**脚本、配置与文档**。为避免仓库膨胀与版权/内容合规问题，
[`.gitignore`](.gitignore) 采用**扩展名兜底**策略：不管文件出现在哪个目录，只要命中下列
类型就不会被提交。

| 类别 | 覆盖格式（示例） |
| --- | --- |
| 图片 | `jpg/jpeg/png/gif/webp/avif/heic/bmp/tif/tiff/svg/psd/tga/dds/exr/jxl` + 各类相机 RAW（`cr2/cr3/nef/arw/dng` …） |
| 磁盘镜像 / 安装包 | `dmg/pkg/iso/img/sparseimage/vhd/vhdx/qcow2/msi/deb/rpm` |
| 模型权重 | `gguf/ggml/safetensors/ckpt/pt/pth/onnx/tflite/mlmodel/h5/pb/npz/npy/bin/msgpack`，以及 `models/`、`hub/`、`models--*/` 等缓存目录 |
| 压缩包 / 大二进制 | `tar/tar.gz/tgz/zip/7z/rar/xz/zst/parquet/sqlite/so/dylib/dll/exe/wasm` … |
| 本机实际大目录 | `sakura-7b-lnovel-v0.9-Q4_K_M.gguf`（4.6 GB，超 GitHub 单文件 100 MB 上限）、`koharu_*.dmg`、`llama-*/`、`manga-image-translator/`（上游 clone） |
| 翻译产物与日志 | `out/`、`out-*/`、`qa*/`、`test1/`、`input*/`、`result*/`、`logs/`、`*.log`（含漫画原图与译文） |

若将来确实需要在 README 里放一张示意图，在 `.gitignore` 末尾用 `!` 单独放行，例如
`!docs/assets/*.png`。

### 第二道防线：pre-commit 钩子

`.gitignore` 只对**未跟踪**文件生效，`git add -f` 或规则疏漏仍可能把大文件提交进去，
因此仓库内置了 [`.githooks/pre-commit`](.githooks/pre-commit)，直接检查暂存区：
命中上述扩展名、或单文件超过 1 MB，立即中止提交。

启用（每个 clone 各做一次，钩子不会随 clone 自动生效）：

```bash
git config core.hooksPath .githooks
```

确需提交时用 `git commit --no-verify` 跳过。

