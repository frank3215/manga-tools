#!/bin/bash
# 创建 manga-image-translator 的 Python 虚拟环境并安装依赖（macOS / Apple Silicon）。
#
#   bash scripts/setup.sh
#
# 环境变量：
#   REQ   自定义 requirements 文件（默认 <repo>/requirements-norust.txt）
set -eu

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MIT="$ROOT/manga-image-translator"
REQ="${REQ:-$ROOT/requirements-norust.txt}"

if [ ! -d "$MIT" ]; then
  echo "缺少上游仓库 ${MIT}，请先克隆：" >&2
  echo "  git clone https://github.com/zyddnys/manga-image-translator.git \"$MIT\"" >&2
  exit 1
fi
if ! command -v uv >/dev/null 2>&1; then
  echo "缺少 uv，请先安装：curl -LsSf https://astral.sh/uv/install.sh | sh" >&2
  exit 1
fi

cd "$MIT"
[ -d .venv ] || uv venv --python 3.11 .venv
# shellcheck disable=SC1091
source .venv/bin/activate

echo "== 安装依赖：$REQ =="
uv pip install -r "$REQ"

# 官方 Rust/ONNX 加速轮子。部分机器（含 Apple Silicon + Python 3.11）安装会失败，
# 失败不影响纯 Python 推理路径，因此不阻断流程。
echo "== 可选：rusty-manga-image-translator 加速轮子 =="
uv pip install rusty-manga-image-translator \
  || echo "WARN: rusty-manga-image-translator 安装失败，已跳过（纯 Python 路径仍可用）"

python -c "import torch; print('torch', torch.__version__, 'mps', torch.backends.mps.is_available())"
python -c "import manga_translator; print('manga_translator OK')"
echo "SETUP_DONE"
