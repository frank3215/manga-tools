#!/bin/bash
# 启动本地 Sakura 翻译服务（llama.cpp + Metal），OpenAI 兼容接口监听 :8080。
#
#   bash scripts/serve-sakura.sh
#
# 环境变量：
#   LLAMA_DIR   llama.cpp 解压目录（默认 <repo>/llama-b11056）
#   MODEL       GGUF 模型路径（默认 <repo>/sakura-7b-lnovel-v0.9-Q4_K_M.gguf）
#   PORT        监听端口（默认 8080）
#   CTX         上下文长度（默认 2048）
#   NGL         offload 到 GPU 的层数，99 表示全部（默认 99）
#   THREADS     CPU 线程数（默认 6）
set -eu

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LLAMA_DIR="${LLAMA_DIR:-$ROOT/llama-b11056}"
MODEL="${MODEL:-$ROOT/sakura-7b-lnovel-v0.9-Q4_K_M.gguf}"
PORT="${PORT:-8080}"
CTX="${CTX:-2048}"
NGL="${NGL:-99}"
THREADS="${THREADS:-6}"

LLAMA="$LLAMA_DIR/llama-server"
[ -x "$LLAMA" ] || { echo "找不到 ${LLAMA}，请先跑 scripts/download-model.sh" >&2; exit 1; }
[ -f "$MODEL" ] || { echo "找不到模型 ${MODEL}，请先跑 scripts/download-model.sh" >&2; exit 1; }

exec "$LLAMA" -m "$MODEL" --host 127.0.0.1 --port "$PORT" \
  -c "$CTX" -ngl "$NGL" -np 1 --threads "$THREADS" --no-webui --jinja
