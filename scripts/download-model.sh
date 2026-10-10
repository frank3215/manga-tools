#!/bin/bash
# 下载 llama.cpp（macOS arm64 预编译包）与 Sakura-7B 量化模型。
# 支持断点续传，可反复执行；下完再跑 scripts/serve-sakura.sh 起服务。
#
#   bash scripts/download-model.sh
#
# 环境变量：
#   LLAMA_TAG   llama.cpp release tag（默认 b11056，需与 serve-sakura.sh 的 LLAMA_DIR 对应）
#   MODEL_URL   GGUF 下载地址（默认 Sakura-7B-LNovel-v0.9 Q4_K_M）
#   PROXY       形如 http://127.0.0.1:7890，设置后走代理下载
set -eu

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LLAMA_TAG="${LLAMA_TAG:-b11056}"
MODEL_URL="${MODEL_URL:-https://huggingface.co/SakuraLLM/Sakura-7B-LNovel-v0.9-GGUF/resolve/main/sakura-7b-lnovel-v0.9-Q4_K_M.gguf}"

if [ -n "${PROXY:-}" ]; then
  export https_proxy="$PROXY" http_proxy="$PROXY" all_proxy="$PROXY"
fi

LLAMA_ARCHIVE="llama-$LLAMA_TAG-bin-macos-arm64.tar.gz"
LLAMA_URL="https://github.com/ggml-org/llama.cpp/releases/download/$LLAMA_TAG/$LLAMA_ARCHIVE"
MODEL="$ROOT/$(basename "$MODEL_URL")"

cd "$ROOT"

echo "== 1/2 llama.cpp $LLAMA_TAG =="
curl -L --fail --retry 8 --retry-all-errors --retry-delay 5 -C - -o "$LLAMA_ARCHIVE" "$LLAMA_URL"
tar -xzf "$LLAMA_ARCHIVE"
echo "已解压到 $ROOT/llama-$LLAMA_TAG"

echo "== 2/2 Sakura 模型 =="
echo "目标：$MODEL"
# --http1.1 + -C - ：大文件续传在 HTTP/2 下容易中断，这里强制 1.1。
curl -L --http1.1 --fail --retry 8 --retry-all-errors --retry-delay 5 -C - -o "$MODEL" "$MODEL_URL"

ls -lh "$ROOT/$LLAMA_ARCHIVE" "$MODEL"
echo "DOWNLOAD_DONE"
