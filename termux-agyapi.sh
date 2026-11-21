#!/data/data/com.termux/files/usr/bin/bash
# agyapi — 管理 agy2api 的 runit 服务（默认只监听 127.0.0.1:7861）
#
#   agyapi            启动（默认）
#   agyapi start      启动并等待面板返回 200
#   agyapi stop       停止并关闭自启
#   agyapi restart    重启（优雅失败会自动 force-stop）
#   agyapi status     服务状态 / HTTP / 模型数 / 端口 / 日志
#   agyapi logs       最近 30 行日志
#
# 环境变量:
#   AGY2API_DIR  安装目录（默认 ~/agy2api）
#   AGY2API_PORT 覆盖端口（默认读 .env 的 PORT）
set -uo pipefail

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
HOME_DIR="${HOME:-/data/data/com.termux/files/home}"
APP="${AGY2API_DIR:-$HOME_DIR/agy2api}"
SVDIR="${SVDIR:-$PREFIX/var/service}"
SV="$PREFIX/bin/sv"
SV_ENABLE="$PREFIX/bin/sv-enable"
SV_DISABLE="$PREFIX/bin/sv-disable"
LOGDIR="${LOGDIR:-$PREFIX/var/log}"
SERVICE="agy2api"
export SVDIR
export LOGDIR

PORT="${AGY2API_PORT:-$(sed -n 's/^PORT=//p' "$APP/.env" 2>/dev/null | head -1)}"
PORT="${PORT:-7861}"

api_key() { sed -n 's/^API_PASSWORD=//p' "$APP/.env" 2>/dev/null; }

http_code() {
  curl -s -o /dev/null -w '%{http_code}' --max-time 4 \
    "http://127.0.0.1:$PORT/" 2>/dev/null || true
}

model_count() {
  local out n
  out=$(curl -s --max-time 8 -H "Authorization: Bearer $(api_key)" \
    "http://127.0.0.1:$PORT/v1/models" 2>/dev/null) || { echo "?"; return; }
  n=$(printf '%s' "$out" | node -e '
    let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
      try{process.stdout.write(String((JSON.parse(s).data||[]).length))}
      catch{process.stdout.write("?")}
    })' 2>/dev/null)
  echo "${n:-?}"
}

running() { "$SV" status "$SERVICE" 2>/dev/null | grep -q '^run:'; }

# restart 之后 runsvdir 可能还没起来（Termux 重启后的常见状态）
ensure_daemon() {
  local i
  pgrep -f "runsvdir .*$SVDIR" >/dev/null 2>&1 && return 0
  "$PREFIX/bin/service-daemon" start >/dev/null 2>&1 || true
  for i in $(seq 1 25); do
    pgrep -f "runsvdir .*$SVDIR" >/dev/null 2>&1 && return 0
    sleep 0.2
  done
  if [ -x "$PREFIX/bin/runsvdir" ]; then
    nohup "$PREFIX/bin/runsvdir" -P "$SVDIR" >/dev/null 2>&1 &
    for i in $(seq 1 50); do
      pgrep -f "runsvdir .*$SVDIR" >/dev/null 2>&1 && return 0
      sleep 0.2
    done
  fi
  return 1
}

start() {
  [ -d "$SVDIR/$SERVICE" ] || { echo "服务未注册，请先运行 bash $APP/termux-install.sh" >&2; return 1; }
  termux-wake-lock 2>/dev/null || true
  if ! ensure_daemon; then
    echo "!! termux-services 未运行（runsvdir 缺失）" >&2
    return 1
  fi
  local i
  for i in $(seq 1 60); do
    running || "$SV" up "$SERVICE" >/dev/null 2>&1
    if [ "$(http_code)" = "200" ]; then
      echo "agy2api ready: http://127.0.0.1:$PORT/  (models: $(model_count))"
      return 0
    fi
    sleep 1
  done
  echo "!! agy2api 未就绪；最近日志：" >&2
  tail -20 "$LOGDIR/sv/$SERVICE/current" >&2 2>/dev/null
  return 1
}

stop() {
  "$SV_DISABLE" "$SERVICE" >/dev/null 2>&1 || true
  "$SV" down "$SERVICE" >/dev/null 2>&1 || true
  local i
  for i in $(seq 1 5); do
    running || break
    sleep 1
  done
  running && "$SV" force-stop "$SERVICE" >/dev/null 2>&1 || true
  termux-wake-unlock 2>/dev/null || true
  echo "stopped (auto-start disabled)"
}

restart() {
  ensure_daemon || { echo "!! runsvdir 缺失" >&2; return 1; }
  local i
  "$SV" restart "$SERVICE" >/dev/null 2>&1 || true
  # uvicorn 可能在优雅关闭时卡住（等待后台任务），给它 15 秒再强杀
  for i in $(seq 1 15); do
    [ "$(http_code)" = "200" ] && { echo "restarted; http=200"; return 0; }
    running || break
    sleep 1
  done
  echo "graceful restart 未完成，强制停止后重启..."
  "$SV" force-stop "$SERVICE" >/dev/null 2>&1 || true
  sleep 2
  for i in $(seq 1 45); do
    running || "$SV" up "$SERVICE" >/dev/null 2>&1
    [ "$(http_code)" = "200" ] && { echo "restarted (forced); http=200"; return 0; }
    sleep 1
  done
  echo "!! restart 未就绪" >&2
  return 1
}

status() {
  printf '%-14s %s\n' "service" "$("$SV" status "$SERVICE" 2>/dev/null | head -1)"
  printf '%-14s %s\n' "http" "$(http_code)"
  printf '%-14s %s\n' "models" "$(model_count)"
  printf '%-14s %s\n' "listen" "127.0.0.1:$PORT"
  printf '%-14s %s\n' "dir" "$APP"
  printf '%-14s %s\n' "logs" "$LOGDIR/sv/$SERVICE/current"
}

logs() { tail -30 "$LOGDIR/sv/$SERVICE/current" 2>/dev/null; }

case "${1:-start}" in
  start)   start ;;
  stop)    stop ;;
  restart) restart ;;
  status)  status ;;
  logs)    logs ;;
  *)
    echo "usage: $0 [start|stop|restart|status|logs]" >&2
    exit 2
    ;;
esac
