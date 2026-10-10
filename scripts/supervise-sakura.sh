#!/bin/bash
# 守护 llama-server：健康检查失败时自动拉起，并把事件写入 supervisor.log。
# 长时间批量翻译时建议单独开一个终端跑它，避免服务中途掉线导致整批失败。
#
#   bash scripts/supervise-sakura.sh
#
# 环境变量：
#   PORT          健康检查端口（默认 8080）
#   CHECK_EVERY   巡检间隔秒数（默认 15）
#   BOOT_TIMEOUT  等待服务就绪的轮数，每轮 3 秒（默认 40）
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT="${PORT:-8080}"
CHECK_EVERY="${CHECK_EVERY:-15}"
BOOT_TIMEOUT="${BOOT_TIMEOUT:-40}"
HEALTH="http://127.0.0.1:$PORT/health"

LOG="$ROOT/supervisor.log"
SERVER_LOG="$ROOT/llama-server.log"

echo "$(date '+%F %T') supervisor start (port=$PORT)" >> "$LOG"

server_up() { curl -s --max-time 3 "$HEALTH" 2>/dev/null | grep -q '"ok"'; }

while true; do
  if ! server_up; then
    pkill -f "llama-server -m" 2>/dev/null
    sleep 2
    echo "$(date '+%F %T') (re)starting llama-server" >> "$LOG"
    PORT="$PORT" nohup "$ROOT/scripts/serve-sakura.sh" >> "$SERVER_LOG" 2>&1 &
    i=1
    while [ "$i" -le "$BOOT_TIMEOUT" ]; do
      sleep 3
      if server_up; then
        echo "$(date '+%F %T') server ready" >> "$LOG"
        break
      fi
      i=$((i + 1))
    done
  fi
  sleep "$CHECK_EVERY"
done
