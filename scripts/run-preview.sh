#!/bin/bash
# 小批量试跑：只跑目录名匹配正则的几部作品，用来快速验证配置改动。
#
#   bash scripts/run-preview.sh '作品名正则'
#   FILTER='正则' bash scripts/run-preview.sh
#
# 不给参数则跑全部（等价于 run-full.sh，只是不限制轮数）。
set -eu

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export FILTER="${1:-${FILTER:-.}}"
export OUTDIR="${OUTDIR:-$ROOT/out}"
export PAR="${PAR:-1}"
export PASSES="${PASSES:-1}"

echo "FILTER=$FILTER"
exec caffeinate -i /bin/bash "$ROOT/scripts/translate-all.sh"
