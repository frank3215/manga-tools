#!/bin/bash
# 冒烟验证：固定跑 1~2 部作品、只跑一轮，用于确认环境/配置可用。
#
#   FILTER='^某作品名$' bash scripts/validate.sh
set -eu

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
: "${FILTER:?'请用 FILTER 指定要验证的作品目录名正则，例如 FILTER="^某作品$" bash scripts/validate.sh'}"
export OUTDIR="${OUTDIR:-$ROOT/out}"
export PAR=1
export PASSES=1
exec caffeinate -i /bin/bash "$ROOT/scripts/translate-all.sh"
