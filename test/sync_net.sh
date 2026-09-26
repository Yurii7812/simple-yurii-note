#!/bin/sh
# 現役同期エンジン(note_format_v2.py の simple_sync)の回帰網。
# 実データを /tmp にコピーし、2回 sync して冪等（2回目が 0 changes）を確認する。
# 分割リファクタの前後で同じ結果になることが期待値。
# 使い方: test/sync_net.sh [VAULT]   （既定 $HOME/files/yurii-note）
set -e
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SRC=${1:-$HOME/files/yurii-note}
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/vault"
cp -a "$SRC"/. "$WORK/vault/"
PY="$REPO/plugin/simple_yurii_note/python/note_format_v2.py"

R1=$(python3 "$PY" update "$WORK/vault")
R2=$(python3 "$PY" update "$WORK/vault")
echo "1回目: $R1"
echo "2回目: $R2"

case "$R2" in
  *"updated 0 file(s)"*) echo "sync 冪等 OK";;
  *) echo "NG: 2回目が 0 changes でない" >&2; exit 1;;
esac
