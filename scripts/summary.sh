#!/bin/bash
# 批量翻译结果汇总：进度、产出统计、失败作品、译文抽样。
#
#   bash scripts/summary.sh                    # 立即读 <repo>/full.log 出报告
#   bash scripts/summary.sh --wait             # 先等批量任务跑完再出报告
#   bash scripts/summary.sh path/to/run.log    # 指定运行日志
#
# 环境变量：
#   SRC_ROOT  作品根目录（用于对比每个作品的输入/输出张数）
#   LOGDIR    每部作品的运行日志目录（默认 <repo>/logs）
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export SRC_ROOT="${SRC_ROOT:-$HOME/Downloads/gallery-dl/kemono/fanbox/25664}"
LOGDIR="${LOGDIR:-$ROOT/logs}"
OUTDIR="${OUTDIR:-$ROOT/out}"

WAIT=0
RUNLOG=""
for arg in "$@"; do
  case "$arg" in
    --wait) WAIT=1 ;;
    *) RUNLOG="$arg" ;;
  esac
done
RUNLOG="${RUNLOG:-$ROOT/full.log}"

if [ "$WAIT" = 1 ]; then
  echo "等待批量任务结束（轮询 $RUNLOG 与 translate-all.sh 进程）..."
  while pgrep -f "translate-all.sh" >/dev/null 2>&1; do sleep 20; done
  sleep 5
fi

echo "===== RUN SUMMARY ($(date '+%F %T')) ====="
if [ -f "$RUNLOG" ]; then
  grep -aE "^(==|----|FAIL|=====)" "$RUNLOG"
else
  echo "(没有运行日志 $RUNLOG)"
fi

echo
echo "--- 每个作品 输出/输入 张数 ---"
tot=0; works=0; incomplete=0
for d in "$OUTDIR"/*/; do
  [ -d "$d" ] || continue
  works=$((works + 1))
  n=$(find "$d" -maxdepth 1 -type f -iname '*.jpg' | wc -l | tr -d ' ')
  s=0
  [ -d "$SRC_ROOT/$(basename "$d")" ] && \
    s=$(find "$SRC_ROOT/$(basename "$d")" -maxdepth 1 -type f -iname '*.jpg' | wc -l | tr -d ' ')
  tot=$((tot + n))
  if [ "$n" -lt "$s" ]; then
    incomplete=$((incomplete + 1))
    printf "INCOMPLETE %3d/%-3d  %s\n" "$n" "$s" "$(basename "$d")"
  else
    printf "%3d/%-3d  %s\n" "$n" "$s" "$(basename "$d")"
  fi
done
echo "works=$works  output_images=$tot  incomplete_works=$incomplete"

echo
echo "--- 单作品耗时（出现次数最多的前 25 条） ---"
grep -ah "Done. Translated" "$LOGDIR"/*.log 2>/dev/null | sed 's/^\[local\] //' | sort | uniq -c | sort -rn | head -25

echo
echo "--- 有译文的作品（译文行数） ---"
for f in "$LOGDIR"/*.log; do
  [ -f "$f" ] || continue
  c=$(grep -ac "=>" "$f")
  [ "$c" -gt 0 ] && printf "%4d 行  %s\n" "$c" "$(basename "$f" .log)"
done

echo
echo "--- 出错作品 ---"
for f in "$LOGDIR"/*.log; do
  [ -f "$f" ] || continue
  grep -qaE "Traceback|RuntimeError|Sakura API请求失败" "$f" && echo "  $(basename "$f" .log)"
done

echo
echo "--- 无任何译文的作品（可能本来就是纯插图） ---"
for f in "$LOGDIR"/*.log; do
  [ -f "$f" ] || continue
  [ "$(grep -ac '=>' "$f")" -eq 0 ] && echo "  $(basename "$f" .log)"
done

echo
echo "--- 译文抽样（每个作品前 3 行） ---"
for f in "$LOGDIR"/*.log; do
  [ -f "$f" ] || continue
  l=$(grep -a "=>" "$f" | head -3 | sed 's/^\[SakuraTranslator\] //')
  [ -n "$l" ] && { echo "### $(basename "$f" .log)"; echo "$l"; }
done

echo
echo "--- 磁盘 ---"; df -h /System/Volumes/Data 2>/dev/null | tail -1
echo "===== SUMMARY DONE ====="
