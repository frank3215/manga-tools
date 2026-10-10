#!/bin/bash
# 批量漫画翻译主驱动：断点续跑 + 服务健康检查 + 多轮重试。
#
#   SRC_ROOT=/path/to/works OUTDIR=/path/to/out bash scripts/translate-all.sh
#
# 环境变量：
#   SRC_ROOT  作品根目录，每个子目录是一部作品（默认 $HOME/Downloads/gallery-dl/kemono/fanbox/25664）
#   OUTDIR    输出根目录（默认 <repo>/out）
#   PAR       并发数（默认 1；Sakura 服务 -np 1，并发 >1 只是排队，不建议调高）
#   PASSES    最大重试轮数（默认 3）
#   FILTER    只跑目录名匹配该正则的作品（默认 . 即全部）
#
# 判定成功的条件：进程退出码为 0、输出图片数 >= 输入图片数、日志无异常关键字。
# 已跑完的作品（输出数 >= 输入数）会直接 SKIP，因此脚本可随时中断重跑。
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export SRC_ROOT="${SRC_ROOT:-$HOME/Downloads/gallery-dl/kemono/fanbox/25664}"
export OUTDIR="${OUTDIR:-$ROOT/out}"
export PAR="${PAR:-1}"
export PASSES="${PASSES:-3}"
export FILTER="${FILTER:-.}"
export CFG="${CFG:-$ROOT/config/sakura-config.json}"
export LOGDIR="${LOGDIR:-$ROOT/logs}"
export MIT="${MIT:-$ROOT/manga-image-translator}"
export HEALTH="${HEALTH:-http://127.0.0.1:8080/health}"
export SAKURA_API_BASE="${SAKURA_API_BASE:-http://127.0.0.1:8080/v1}"
export SAKURA_VERSION="${SAKURA_VERSION:-0.9}"

if [ ! -d "$SRC_ROOT" ]; then
  echo "作品根目录不存在：${SRC_ROOT}（用 SRC_ROOT=... 指定）" >&2
  exit 1
fi
if [ ! -d "$MIT/.venv" ]; then
  echo "缺少 Python 环境 $MIT/.venv，请先跑 scripts/setup.sh" >&2
  exit 1
fi

mkdir -p "$LOGDIR" "$OUTDIR"

count_jpg() { find "$1" -maxdepth 1 -type f -iname '*.jpg' 2>/dev/null | wc -l | tr -d ' '; }
server_up() { curl -s --max-time 3 "$HEALTH" 2>/dev/null | grep -q '"ok"'; }
wait_server() { local i; for i in $(seq 1 120); do server_up && return 0; sleep 5; done; return 1; }
logfile_of() { printf '%s/%s.log' "$LOGDIR" "$(printf '%s' "$1" | tr '/ ' '__')"; }

one() {
  local dir name dest src_count dst_count rc lf
  dir="$1"; name="$(basename "$dir")"; dest="$OUTDIR/$name"; lf="$(logfile_of "$name")"
  src_count=$(count_jpg "$dir")
  [ "$src_count" -eq 0 ] && { echo "SKIP(empty) $name"; return 0; }

  dst_count=0; [ -d "$dest" ] && dst_count=$(count_jpg "$dest")
  if [ "$dst_count" -ge "$src_count" ]; then echo "SKIP(done)  $name"; return 0; fi

  if ! wait_server; then echo "FAIL(server) $name"; return 1; fi

  mkdir -p "$dest"
  ( cd "$MIT" && source .venv/bin/activate && \
    python -m manga_translator local -i "$dir" -o "$dest" --overwrite --config-file "$CFG" ) > "$lf" 2>&1
  rc=$?
  dst_count=$(count_jpg "$dest")
  if [ $rc -eq 0 ] && [ "$dst_count" -ge "$src_count" ] && \
     ! grep -qaE "Traceback|RuntimeError|Sakura API请求失败|Error during translating" "$lf"; then
    echo "OK           $name ($dst_count/$src_count)"
    return 0
  fi
  echo "FAIL         $name (rc=$rc, out=$dst_count/$src_count)"
  return 1
}
export -f one count_jpg server_up wait_server logfile_of

TMP1=$(mktemp); TMP2=$(mktemp)
find "$SRC_ROOT" -maxdepth 1 -mindepth 1 -type d -print0 > "$TMP1"
: > "$TMP2"
while IFS= read -r -d '' d; do
  b="$(basename "$d")"
  if printf '%s\n' "$b" | grep -qE "$FILTER"; then printf '%s\0' "$d" >> "$TMP2"; fi
done < "$TMP1"
COUNT=$(tr -cd '\0' < "$TMP2" | wc -c | tr -d ' ')
echo "== $COUNT folders | src=$SRC_ROOT out=$OUTDIR par=$PAR passes=$PASSES | start $(date '+%F %T') =="

pass=1
while [ "$pass" -le "$PASSES" ]; do
  RES=$(mktemp)
  echo "---- pass $pass ----"
  xargs -0 -P "$PAR" -I{} bash -c 'one "$@"' _ {} < "$TMP2" | tee "$RES"
  fails=$(grep -c '^FAIL' "$RES" 2>/dev/null); fails=${fails:-0}
  oks=$(grep -c '^OK' "$RES" 2>/dev/null); oks=${oks:-0}
  echo "---- pass $pass: ok=$oks fail=$fails ----"
  [ "$fails" -eq 0 ] && break
  pass=$((pass + 1))
done
echo "===== ALL DONE $(date '+%F %T') ====="
