#!/data/data/com.termux/files/usr/bin/bash
# termux-start.sh — 前台启动 agy2api（用于调试；常驻请用 agyapi start）
#
#   bash termux-start.sh
set -euo pipefail

cd "$(dirname "$0")"

[ -f .env ] || { echo "缺少 .env，请先运行 bash termux-install.sh" >&2; exit 1; }
[ -x .venv/bin/python ] || { echo "缺少 .venv，请先运行 bash termux-install.sh" >&2; exit 1; }

export ANDROID_API_LEVEL=24
set -a; . ./.env; set +a

exec .venv/bin/python web.py
