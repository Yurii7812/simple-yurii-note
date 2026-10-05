#!/bin/sh
# 保存タイミング（オートセーブ）の回帰網。
# 「保存が要る瞬間にだけ書く」現仕様（Esc 即保存 / 離脱時即保存 / gm 前 /
# \tD rename 前 / autosave=0 尊重）を固定する。実データには触れない。
# 使い方: test/autosave_net.sh
set -e
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
WORK=$(mktemp -d)
STATE="$HOME/.vim/simple_yurii_note"
STATE_BAK="$WORK/state.bak"

# headless テストは state dir（ロック・履歴）を汚すため退避して復元する
if [ -d "$STATE" ]; then
  cp -a "$STATE" "$STATE_BAK"
fi
restore() {
  if [ -d "$STATE_BAK" ]; then
    rm -rf "$STATE"
    mv "$STATE_BAK" "$STATE"
  fi
  rm -rf "$WORK"
}
trap restore EXIT

VAULT="$WORK/vault"
mkdir -p "$VAULT/.trash" "$WORK/bin"
for f in a b c d e; do printf 'orig\n' > "$VAULT/$f.md"; done
printf 'a,b\n' > "$VAULT/x.csv"
printf 'import sys\nsys.exit(0)\n' > "$WORK/fake_sync.py"
printf '#!/bin/sh\necho "$@" >> "%s"\n' "$WORK/xdg_called.txt" > "$WORK/bin/xdg-open"
chmod +x "$WORK/bin/xdg-open"

AUTOSAVE_WORK="$WORK" PATH="$WORK/bin:$PATH" \
  timeout 60 vim -u "$REPO/vimrc_simple-yurii-note" -N -es \
  -S "$REPO/test/autosave_check.vim" || true

fail() { echo "NG: $1" >&2; exit 1; }
out() { cat "$WORK/out_$1.txt" 2>/dev/null || true; }

[ "$(out save)" = "modified=0 line=one" ] || fail "save_current_note が書かない: $(out save)"
[ "$(out target)" = "md=1 csv=1 outside=0" ] || fail "is_autosave_target: $(out target)"
[ "$(out insertleave)" = "modified=0 line=bee!" ] || fail "Esc 即保存が効かない: $(out insertleave)"
[ "$(out bufleave)" = "see" ] || fail "BufLeave 即保存が効かない: $(out bufleave)"
[ "$(out off)" = "modified=1 line=one" ] || fail "autosave=0 で書いてしまう: $(out off)"
[ "$(out gm)" = "modified=0 line=gmtest" ] || fail "gm 前保存が効かない: $(out gm)"
grep -q "vault/e.md" "$WORK/xdg_called.txt" || fail "gm が既定アプリを呼んでいない"

# 7) \tD: rename 前に保存され、元ファイルは消えている
TRASHED=$(ls "$VAULT/.trash" 2>/dev/null | head -1 || true)
[ -n "$TRASHED" ] || fail "\\tD でゴミ箱に入っていない"
[ "$(head -1 "$VAULT/.trash/$TRASHED")" = "latest edit" ] || fail "\\tD の最新編集が保存されていない"
[ ! -e "$VAULT/d.md" ] || fail "\\tD 後も元ファイルが残っている"

echo "autosave OK"
