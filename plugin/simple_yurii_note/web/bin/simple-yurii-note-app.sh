#!/bin/sh
# simple_yurii_note デスクトップアプリ (Electron) を起動する。
# 使い方: simple-yurii-note-app.sh [VAULT_DIR]
#   VAULT_DIR 省略時は ~/files/yurii-note。
set -eu
WEB=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ELECTRON="$WEB/node_modules/.bin/electron"
if [ ! -x "$ELECTRON" ]; then
  echo "electron が見つかりません。次を実行してください: cd \"$WEB\" && npm install" >&2
  exit 1
fi
VAULT=${1:-"$HOME/files/yurii-note"}
PKM_ROOT=$(CDPATH= cd -- "$VAULT" && pwd)
export PKM_ROOT
exec "$ELECTRON" "$WEB"
