# manga-tools

macOS（Apple Silicon / Metal）上的**本地漫画翻译流水线**：

- [manga-image-translator](https://github.com/zyddnys/manga-image-translator) 负责
  「文字检测 → OCR → 擦字 → 嵌字」；
- 本地跑的 **Sakura-7B-LNovel**（llama.cpp + Metal，OpenAI 兼容接口）负责日→中翻译。

全程离线推理，不需要任何云端翻译 API。本仓库只放**脚本、配置与文档**——模型、预编译
二进制、上游仓库、翻译产物一律不入库（见文末「仓库约定」）。

> **只想快点跑起来？** 备好约 8 GB 磁盘和能访问 GitHub / HuggingFace 的网络，然后：
>
> ```bash
> git clone https://github.com/frank3215/manga-tools.git ~/manga-tools && cd ~/manga-tools
> git clone https://github.com/zyddnys/manga-image-translator.git manga-image-translator
> bash scripts/setup.sh
> PROXY=http://127.0.0.1:7890 bash scripts/download-model.sh   # 不需要代理就去掉 PROXY=
> bash scripts/serve-sakura.sh                                  # 前台占用 :8080，另开终端继续
> FILTER='^某作品目录名$' bash scripts/validate.sh              # 冒烟
> SRC_ROOT=/path/to/works bash scripts/run-full.sh              # 批量
> bash scripts/summary.sh --wait                                # 报告
> ```

## 处理流程

```
输入作品目录（每部作品一个子目录，内含 *.jpg）
        │
        ▼
manga_translator local ──┬─ 文字检测  detector: default, detection_size 2048
                         ├─ OCR      ocr: mocr
                         ├─ 翻译      translator: sakura → http://127.0.0.1:8080/v1
                         ├─ 擦字      inpainter: lama_large
                         └─ 嵌字      render: default（自动字号/方向）
        │
        ▼
输出目录（与输入同名），并把「日文 => 中文」逐行写进 logs/<作品名>.log
```

质量的关键在翻译器：Sakura 是针对轻小说/漫画日译中微调的模型，在口语、拟声词、人称上
明显好过通用 NLLB，这也是整条流水线要本地跑 LLM 的原因。

---

# 一、需要下载什么

| 组件 | 体积 | 来源 | 由谁下载 |
| --- | --- | --- | --- |
| 上游 `manga-image-translator` | 克隆约 200 MB（含 `.git`） | GitHub | **手动** `git clone` |
| Python 依赖（含 torch） | 约 1.5 GB | PyPI | `scripts/setup.sh` |
| llama.cpp 预编译包（macOS arm64） | 11 MB（解压后 27 MB） | GitHub Releases | `scripts/download-model.sh` |
| **Sakura-7B-LNovel GGUF** | **4.9 GB**（Q4_K_M） | HuggingFace | `scripts/download-model.sh` |
| 检测 / 擦字 / OCR / 超分模型 | 920 MB | GitHub Releases + HuggingFace | **首次翻译时自动**下载 |
| manga-ocr 识别模型 | 440 MB | HuggingFace | **首次翻译时自动**下载 |

**磁盘预算约 8 GB**（模型 4.9 GB + 上游与依赖 2.6 GB + 自动模型 1.4 GB + 余量）。
开工前先看一眼：

```bash
df -h /System/Volumes/Data
```

Sakura 有多个量化档，显存/内存紧张可以换更小的（改 `MODEL_URL`，见下文「换模型 / 换量化」）：

| 文件 | 体积 | 说明 |
| --- | --- | --- |
| `sakura-7b-lnovel-v0.9-Q2_K.gguf` | 3.34 GB | 最小，质量下降明显 |
| `sakura-7b-lnovel-v0.9-Q3_K_M.gguf` | 4.06 GB | 折中 |
| `sakura-7b-lnovel-v0.9-Q4_K_M.gguf` | 4.90 GB | **默认，推荐** |
| `sakura-7b-lnovel-v0.9-Q5_K_M.gguf` | 5.71 GB | 略好，更吃内存 |
| `sakura-7b-lnovel-v0.9-Q6_K.gguf` | 6.34 GB | 接近 fp16，最慢 |

---

# 二、安装步骤

## 0. 前置工具

macOS 自带 `git`、`curl`、`caffeinate`。若 `git --version` 报错，先装命令行工具：

```bash
xcode-select --install
```

再装 [`uv`](https://docs.astral.sh/uv/)（用于管理 Python 3.11 与虚拟环境）：

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
uv --version
```

## 1. 取代码

```bash
git clone https://github.com/frank3215/manga-tools.git ~/manga-tools
cd ~/manga-tools
git clone https://github.com/zyddnys/manga-image-translator.git manga-image-translator
```

两点说明：

- 本仓库可以放在**任意目录**，脚本按自身位置（`$(dirname $0)/..`）定位配置与模型，
  不依赖 `~/manga-tools` 这个路径。
- 上游目录名必须是 `manga-image-translator`，放在本仓库根下（或后续用 `MIT=` 指定）。

顺手启用防误提交钩子（防止把图片/模型提交进仓库）：

```bash
git config core.hooksPath .githooks
```

## 2. 安装 Python 依赖

```bash
bash scripts/setup.sh
```

它会：用 `uv` 建 Python 3.11 虚拟环境 → 装
[`requirements-norust.txt`](requirements-norust.txt) → 单独尝试装 Rust 加速轮子（失败仅告警）
→ 自检 torch 与 MPS。

最后应该看到类似输出：

```
torch 2.x.x mps True
manga_translator OK
SETUP_DONE
```

`mps True` 表示 Apple Silicon 的 Metal 后端可用。若装依赖超时，先设代理再重跑：

```bash
export https_proxy=http://127.0.0.1:7890 http_proxy=http://127.0.0.1:7890 all_proxy=http://127.0.0.1:7890
bash scripts/setup.sh
```

## 3. 下载 llama.cpp 与 Sakura 模型

```bash
# 能直连 GitHub / HuggingFace：
bash scripts/download-model.sh

# 需要代理：
PROXY=http://127.0.0.1:7890 bash scripts/download-model.sh
```

脚本做两件事，都支持**断点续传**（中断后原命令再跑一遍即可）：

1. 下 `llama-b11056-bin-macos-arm64.tar.gz` 并解压到 `./llama-b11056/`；
2. 下 `sakura-7b-lnovel-v0.9-Q4_K_M.gguf`（4.9 GB）到仓库根目录。

下完确认：

```bash
ls -lh llama-b11056/llama-server sakura-7b-lnovel-v0.9-Q4_K_M.gguf
# 模型应约 4.9G；若明显偏小说明没下完，重跑上面命令续传
```

> 下不动怎么办：`MODEL_URL` 可指向任何可访问的镜像；或手动下载后放到仓库根目录并改名为
> `sakura-7b-lnovel-v0.9-Q4_K_M.gguf`，脚本只认这个路径（也可用 `MODEL=` 指定别的位置）。

## 4. 首次翻译会自动下载的模型

**不用手动下**。第一次跑翻译时，上游会从 GitHub Releases（`beta-0.3`）和 HuggingFace
拉取检测/擦字/OCR/超分模型，约 1.4 GB，落在：

- `manga-image-translator/models/`（检测、擦字、OCR、超分，共 920 MB）
- `~/.cache/huggingface/`（manga-ocr 识别模型 440 MB）

只想先把这批下好、不想翻译的话，随便丢一张图跑一次 `scripts/trial.sh` 即可。若这些
HuggingFace 下载失败，可给上游设镜像：

```bash
export HF_ENDPOINT=https://hf-mirror.com
```

（该变量对上游用 `huggingface_hub` 的下载生效，对 `download-model.sh` 的 curl 不生效。）

## 5. 打上游补丁（强烈建议）

上游 sakura 翻译器在服务不可用时**会静默返回原文**，产出「看着成功、其实没翻」的图片。
本仓库的补丁把它改成抛异常，配合 `translate-all.sh` 就能正确判定失败并重试：

```bash
cd manga-image-translator
git apply ../patches/manga-image-translator-sakura-fix.patch
cd ..
```

详见文末「上游补丁」。

---

# 三、验证安装

```bash
# 1) 服务能起来吗（前台，占 :8080，验证完 Ctrl-C）
bash scripts/serve-sakura.sh
```

另开一个终端：

```bash
# 2) 健康检查，应返回 {"status":"ok"}
curl -s http://127.0.0.1:8080/health

# 3) 真的能翻译吗（走的就是上游用的那套 chat 接口）
curl -s http://127.0.0.1:8080/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "sukinishiro",
    "messages": [
      {"role": "system", "content": "你是一个轻小说翻译模型，可以流畅通顺地以日本轻小说的风格将日文翻译成简体中文，并联系上下文正确使用人称代词，不擅自添加原文中没有的代词。"},
      {"role": "user", "content": "将下面的日文文本翻译成中文：魔女は笑った。"}
    ],
    "temperature": 0.1,
    "max_tokens": 64
  }'
```

第三条例子里 `model` 可以随便填（llama-server 忽略它）；`--jinja` 会套用模型自带的
对话模板，所以**不要**自己拼 `<|start|>` / `<|end|>` 之类的特殊 token。

```bash
# 4) 端到端冒烟：拿一部作品真跑一遍
FILTER='^某作品目录名$' bash scripts/validate.sh
```

---

# 四、日常使用

## 准备作品目录

一部作品一个子目录，图片放平层（`*.jpg`）：

```
$SRC_ROOT/
├── 作品甲/
│   ├── 01.jpg
│   └── 02.jpg
└── 作品乙/
    ├── 01.jpg
    └── 02.jpg
```

`SRC_ROOT` 默认是 `$HOME/Downloads/gallery-dl/kemono/fanbox/25664`（本机原路径），
换目录用环境变量指定即可。

## 起翻译服务

```bash
# 前台（日常）
bash scripts/serve-sakura.sh

# 守护模式（长时间批量，掉线自动拉起，事件写入 supervisor.log）
bash scripts/supervise-sakura.sh &
```

服务是 OpenAI 兼容接口，默认 `http://127.0.0.1:8080/v1`，参数：`-c 2048 -ngl 99 -np 1`
（单 slot）。可用 `PORT` / `CTX` / `NGL` / `THREADS` 覆盖。

## 试译一部

```bash
# 直接对某个目录跑一次，输出到 out-trial/<目录名>，译文同时打到终端
bash scripts/trial.sh /path/to/作品甲

# 换用 nllb 对照配置（不依赖 Sakura 服务）
CFG=config/trial-config.json bash scripts/trial.sh /path/to/作品甲
```

## 批量翻译

```bash
# 跑 SRC_ROOT 下全部作品
SRC_ROOT=/path/to/works bash scripts/run-full.sh

# 只跑匹配正则的几部（快速验证改动）
SRC_ROOT=/path/to/works bash scripts/run-preview.sh '作品甲|作品乙'

# 加速：让检测/擦字也走 Metal（默认 CPU，见下方说明）
USE_GPU=1 SRC_ROOT=/path/to/works bash scripts/run-full.sh
```

批量脚本的行为：

- **断点续跑**：输出张数 ≥ 输入张数的作品直接 `SKIP`，可随时 Ctrl-C 再重跑；
- **多轮重试**：失败作品最多重跑 `PASSES`（默认 3）轮；
- **健康检查**：每部作品开跑前先等 `/health` 就绪，服务挂了不会空转；
- **逐作品判成败**：退出码 0 + 输出数达标 + 日志无异常关键字，三者同时满足才算 `OK`；
- **防休眠**：用 `caffeinate -i` 包住，跑几小时也不会睡。

输出到 `OUTDIR/<作品名>/`，日志在 `LOGDIR/<作品名>.log`。

## 看进度 / 出报告

```bash
bash scripts/summary.sh            # 立即出报告
bash scripts/summary.sh --wait     # 先等批量任务跑完再出
```

报告含：运行概览、每部作品「输出/输入」张数、未完作品、失败作品、单作品耗时、
译文行数统计、译文抽样、磁盘占用。

## 中断与续跑

直接 `Ctrl-C`。再跑同一条命令时，已完成的作品会 `SKIP`，只补没跑完的。

想**强制重跑**某部作品，删掉它的输出目录再跑一次即可：

```bash
rm -rf out/作品甲
```

（`translate-all.sh` 每次都带 `--overwrite`，不会跳过目录里已存在的单张图片；跳过与否
只看「输出张数是否已达到输入张数」。）

## 换模型 / 换量化

```bash
# 下 Q5_K_M
MODEL_URL=https://huggingface.co/SakuraLLM/Sakura-7B-LNovel-v0.9-GGUF/resolve/main/sakura-7b-lnovel-v0.9-Q5_K_M.gguf \
  PROXY=http://127.0.0.1:7890 bash scripts/download-model.sh

# 指定用它起服务（文件名与 MODEL_URL 的 basename 一致）
MODEL=./sakura-7b-lnovel-v0.9-Q5_K_M.gguf bash scripts/serve-sakura.sh
```

换 llama.cpp 版本同理：`LLAMA_TAG=b12345 bash scripts/download-model.sh`，解压目录会变成
`llama-b12345/`，起服务时加 `LLAMA_DIR=./llama-b12345`。

## 关于 `USE_GPU`

`manga_translator` 默认走 CPU 做检测/擦字；`USE_GPU=1` 会加 `--use-gpu`（自动选 MPS/CUDA）。
默认关掉的原因：MPS 在超长图上偶发 OOM，且首次预热有额外开销。**Sakura 本身的推理始终由
llama.cpp 走 Metal**，与这个开关无关。

---

# 五、脚本一览

| 脚本 | 作用 |
| --- | --- |
| `scripts/setup.sh` | 建 `.venv`、装 `requirements-norust.txt`、尝试装 Rust 加速轮子 |
| `scripts/download-model.sh` | 下载 llama.cpp 与 Sakura GGUF，带 `-C -` 续传 |
| `scripts/serve-sakura.sh` | 启动 `llama-server`，OpenAI 兼容接口监听 `:8080` |
| `scripts/supervise-sakura.sh` | 守护：`/health` 不 ok 就重启，事件写 `supervisor.log` |
| `scripts/translate-all.sh` | **主驱动**：断点续跑、健康检查、多轮重试、逐作品判成败 |
| `scripts/run-full.sh` | 跑全部作品（`caffeinate` 防休眠） |
| `scripts/run-preview.sh` | 只跑 `FILTER` 命中的作品 |
| `scripts/validate.sh` | 强制要求 `FILTER`，单轮冒烟验证 |
| `scripts/trial.sh` | 单目录试译，`--save-text` 并把译文打到终端 |
| `scripts/summary.sh` | 汇总报告 |

# 六、参数速查

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `SRC_ROOT` | `$HOME/Downloads/gallery-dl/kemono/fanbox/25664` | 作品根目录 |
| `OUTDIR` | `<repo>/out` | 译文输出根目录 |
| `LOGDIR` | `<repo>/logs` | 每部作品的运行日志 |
| `PAR` | `1` | 并发数。服务端 `-np 1`，调大只是排队，**不建议 >1** |
| `PASSES` | `3` | 失败作品最大重试轮数 |
| `FILTER` | `.` | 作品目录名正则 |
| `CFG` | `<repo>/config/sakura-config.json` | 传给 `manga_translator --config-file` |
| `USE_GPU` | `0` | `1` 则加 `--use-gpu`（MPS/CUDA） |
| `MIT` | `<repo>/manga-image-translator` | 上游目录 |
| `LLAMA_DIR` | `<repo>/llama-b11056` | llama.cpp 解压目录 |
| `MODEL` | `<repo>/sakura-7b-lnovel-v0.9-Q4_K_M.gguf` | GGUF 路径 |
| `LLAMA_TAG` | `b11056` | llama.cpp release tag（仅下载用） |
| `PROXY` | 空 | 形如 `http://127.0.0.1:7890`，仅下载脚本用 |
| `PORT` / `CTX` / `NGL` / `THREADS` | `8080` / `2048` / `99` / `6` | llama-server 参数 |
| `SAKURA_API_BASE` | `http://127.0.0.1:8080/v1` | 上游 sakura 翻译器读取的服务地址 |
| `SAKURA_VERSION` | `0.9` | 提示词版本，需与模型代次一致 |

# 七、配置文件

| 文件 | 用途 |
| --- | --- |
| [`config/sakura-config.json`](config/sakura-config.json) | 生产配置：`translator: sakura` + `ocr: mocr` + `inpainter: lama_large` |
| [`config/trial-config.json`](config/trial-config.json) | 对照配置：`translator: nllb` + `ocr: 48px`（不依赖服务，做 A/B 用） |

常用可调项（`sakura-config.json`）：

| 键 | 当前值 | 说明 |
| --- | --- | --- |
| `detector.detection_size` | `2048` | 检测分辨率，调大更准但更慢 |
| `detector.box_threshold` | `0.6` | 调低召回更多气泡，也更多误检 |
| `ocr.ocr` | `mocr` | 也可换 `48px`（小模型，更快） |
| `inpainter.inpainter` | `lama_large` | 擦字模型，`lama_large` 质量最好 |
| `inpainter.inpainting_size` | `1536` | 擦字分辨率 |
| `render.font_size_offset` | `0` | 字号整体偏移，字太小调大 |
| `mask_dilation_offset` | `20` | 文字掩膜外扩，处理描边字 |

完整选项：`bash -c 'cd manga-image-translator && source .venv/bin/activate && python -m manga_translator config-help'`。

# 八、常见问题

**输出图片是原图、文字没变？**
说明 Sakura 服务不可用，而补丁未生效（静默返回原文）。确认
`curl -s http://127.0.0.1:8080/health` 返回 `{"status":"ok"}`，并检查
`logs/<作品>.log` 里有没有 `Sakura API请求失败`。

**服务跑一会儿就掉线？**
用 `scripts/supervise-sakura.sh` 守护。OOM 时把 `NGL` 调低，或换 `Q3_K_M` 更小的量化。

**首轮很慢？**
首轮要下 1.4 GB 自动模型并预热 Metal。之后每部作品只需检测+OCR+擦字+嵌字，快很多。

**能并发跑吗？**
可以但不划算：`llama-server` 是 `-np 1` 单 slot，并发请求只会排队，还容易压爆内存。
`PAR=1` 最稳。

**`mps False` / 跑起来是 CPU？**
`uv` 装的 torch 在 Apple Silicon 上默认带 MPS。若为 False，确认是原生 arm64 终端（不是
Rosetta 下的 x86 终端），然后重装：

```bash
cd manga-image-translator && source .venv/bin/activate
uv pip install --force-reinstall torch torchvision
python -c "import torch; print(torch.backends.mps.is_available())"
```

**补丁 apply 失败？**
上游 `sakura.py` 变动会导致上下文不匹配。按
[`patches/README.md`](patches/README.md) 里描述的两处逻辑手动改即可，代码很短。

# 九、上游补丁

`patches/manga-image-translator-sakura-fix.patch` 改 `manga_translator/translators/sakura.py`：

1. `_handle_translation_request` 返回值先 `str()` 兜底，避免返回 list 时拼接抛 `TypeError`；
2. 重试耗尽后**不再 `return prompt`**，改为抛 `RuntimeError`——否则会静默产出「没翻」的
   图片；改抛异常后该图明确失败，交给 `translate-all.sh` 重试。

应用 / 撤销：

```bash
cd manga-image-translator
git apply ../patches/manga-image-translator-sakura-fix.patch     # 应用
git apply -R ../patches/manga-image-translator-sakura-fix.patch  # 撤销
```

补丁基于上游 commit `95227a2`。

`requirements-norust.txt` 与上游 `requirements.txt` 只差一行：去掉
`rusty-manga-image-translator`。该 Rust 加速轮子在 Apple Silicon + Python 3.11 上经常装不上，
且其依赖解析会拖垮整批安装，故拆出来由 `setup.sh` 单独尝试（失败仅告警）。

# 十、仓库约定

## 目录结构

```
manga-tools/
├── README.md
├── .gitignore
├── .githooks/pre-commit        # 拦截图片/模型/大文件入库
├── config/                     # 翻译配置
├── scripts/                    # 全部脚本
├── patches/                    # 上游补丁与说明
├── requirements-norust.txt
└── (manga-image-translator/)   # 上游仓库，自行 clone，已被 .gitignore 排除
```

## 不入库的内容

本仓库只放**脚本、配置与文档**。[`.gitignore`](.gitignore) 按**扩展名兜底**：不管文件出现在
哪个目录，命中下列类型都不会被提交。

| 类别 | 覆盖格式（示例） |
| --- | --- |
| 图片 | `jpg/jpeg/png/gif/webp/avif/heic/bmp/tif/tiff/svg/psd/tga/dds/exr/jxl` + 相机 RAW（`cr2/cr3/nef/arw/dng` …） |
| 磁盘镜像 / 安装包 | `dmg/pkg/iso/img/sparseimage/vhd/vhdx/qcow2/msi/deb/rpm` |
| 模型权重 | `gguf/ggml/safetensors/ckpt/pt/pth/onnx/tflite/mlmodel/h5/pb/npz/npy/bin/msgpack`，及 `models/`、`hub/`、`models--*/` |
| 压缩包 / 大二进制 | `tar/tar.gz/tgz/zip/7z/rar/xz/zst/parquet/sqlite/so/dylib/dll/exe/wasm` … |
| 翻译产物与日志 | `out/`、`out-*/`、`qa*/`、`test1/`、`input*/`、`result*/`、`logs/`、`*.log` |

需在 README 放示意图时，在 `.gitignore` 末尾用 `!` 单独放行（如 `!docs/assets/*.png`）。

## 第二道防线：pre-commit 钩子

`.gitignore` 只对**未跟踪**文件生效，`git add -f` 或规则疏漏仍可能放进大文件。
[`.githooks/pre-commit`](.githooks/pre-commit) 直接检查暂存区：命中上述扩展名、或单文件
超过 1 MB，立即中止提交。

```bash
git config core.hooksPath .githooks   # 每个 clone 各做一次
```

确需提交时用 `git commit --no-verify` 跳过。
