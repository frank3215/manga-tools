#!/bin/bash
# 跑全部作品（单并发、最多 3 轮重试），并用 caffeinate 阻止 Mac 休眠。
#
#   bash scripts/run-full.sh
set -eu

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export OUTDIR="${OUTDIR:-$ROOT/out}"
export PAR="${PAR:-1}"
export PASSES="${PASSES:-3}"
export FILTER="${FILTER:-.}"
exec caffeinate -i /bin/bash "$ROOT/scripts/translate-all.sh"
