#!/bin/sh
# 分割リファクタ用の回帰網: Vim の公開APIが変わっていないことを確認する。
# 使い方: test/run.sh
set -e
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
GOLDEN="$REPO/test/api_public.txt"
OUT=$(mktemp)
ERR=$(mktemp)
trap 'rm -f "$OUT" "$ERR"' EXIT

python3 "$REPO/test/vim_static_check.py"
python3 "$REPO/test/check_guide.py"
python3 "$REPO/plugin/simple_yurii_note/python/test_sort_yomi.py"

timeout 60 vim -u "$REPO/vimrc_simple-yurii-note" -es \
  -c "let g:simple_yurii_note_api_out='$OUT'" \
  -c "source $REPO/test/vim_api_check.vim" \
  -c 'qa!' </dev/null 2>"$ERR" || true

if [ ! -s "$OUT" ]; then
  echo "NG: Vim から関数一覧を得られなかった（ロード失敗の疑い）" >&2
  cat "$ERR" >&2 || true
  exit 1
fi
if [ -s "$ERR" ]; then
  echo "注意: Vim が stderr に出力した:" >&2
  cat "$ERR" >&2
fi
if diff -u "$GOLDEN" "$OUT"; then
  echo "Vim API OK ($(wc -l < "$OUT") funcs)"
else
  echo "NG: 公開APIが変化した（上記の差分）" >&2
  exit 1
fi
