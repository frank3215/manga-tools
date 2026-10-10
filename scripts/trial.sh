#!/bin/bash
# 单部作品试译：直接对某个目录跑一次翻译，输出到指定目录，并把译文打到终端。
#
#   bash scripts/trial.sh <输入目录> [输出目录]
#   CFG=config/trial-config.json bash scripts/trial.sh /path/to/work
#
# 环境变量：
#   CFG   配置文件（默认 <repo>/config/sakura-config.json；试 nllb 等其它翻译器时换 trial-config.json）
set -eu

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MIT="$ROOT/manga-image-translator"
CFG="${CFG:-$ROOT/config/sakura-config.json}"

IN="${1:-}"
[ -n "$IN" ] || { echo "用法：bash scripts/trial.sh <输入目录> [输出目录]" >&2; exit 1; }
[ -d "$IN" ] || { echo "输入目录不存在：$IN" >&2; exit 1; }
OUT="${2:-$ROOT/out-trial/$(basename "$IN")}"
mkdir -p "$OUT"

export SAKURA_API_BASE="${SAKURA_API_BASE:-http://127.0.0.1:8080/v1}"
export SAKURA_VERSION="${SAKURA_VERSION:-0.9}"

cd "$MIT"
# shellcheck disable=SC1091
source .venv/bin/activate

time python -m manga_translator -v local -i "$IN" -o "$OUT" \
  --overwrite --save-text --config-file "$CFG"
echo "TRIAL_EXIT=$?"

ls -l "$OUT"
cat "$OUT"/*.txt 2>/dev/null
