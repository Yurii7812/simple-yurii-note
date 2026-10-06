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
printf 'orig\n' > "$VAULT/ins.md"
printf '# Index\n' > "$VAULT/index.md"
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

# 8) 挿入モードのまま止まっても保存される（pty が必要なので script+fifo で）
if command -v script >/dev/null 2>&1 && command -v mkfifo >/dev/null 2>&1; then
  # 通常の vimrc は pty 起動時にメッセージ待ち（mode=c）になり得るため、
  # プラグインだけを読む最小 vimrc を使う。other.vim が `colorscheme kalisi`
  # を呼ぶので、ダミーの colors/kalisi.vim を runtimepath に足して ENTER 待ち
  # （E185）を避ける。
  mkdir -p "$WORK/colors"
  printf 'let g:colors_name = "kalisi"\n' > "$WORK/colors/kalisi.vim"
  cat > "$WORK/pty_vimrc" <<EOF
set nocompatible
set noswapfile
execute 'set runtimepath^=' . fnameescape('$REPO')
execute 'set runtimepath^=' . fnameescape('$WORK')
let g:simple_yurii_note_open_index_on_startup = 0
let g:simple_yurii_note_autosync = 0
let g:simple_yurii_note_root = '$VAULT'
let g:simple_yurii_note_autosave_delay = 300
EOF
  FIFO="$WORK/fifo"
  mkfifo "$FIFO"
  (sleep 8 > "$FIFO" 2>/dev/null) &
  HOLDER=$!
  AUTOSAVE_WORK="$WORK" timeout 15 script -qec \
    "vim -u '$WORK/pty_vimrc' -N -S '$REPO/test/autosave_insert_check.vim'" \
    /dev/null < "$FIFO" >/dev/null 2>&1 || true
  kill "$HOLDER" 2>/dev/null || true
  wait "$HOLDER" 2>/dev/null || true
  rm -f "$FIFO"
  INSERT_OUT=$(cat "$WORK/out_insert.txt" 2>/dev/null || true)
  case "$INSERT_OUT" in
    mode=i\ modified=0\ line=insert-pause|mode=r\ modified=0\ line=insert-pause) ;;
    *) fail "挿入中のデバウンス保存が効かない: ${INSERT_OUT:-no-output}";;
  esac
else
  echo "skip: script / mkfifo が無いため挿入中デバウンスの確認を省略"
fi

# 9) ビジュアル選択中にオートセーブのタイマーが来ても選択が解除されない（pty）
if command -v script >/dev/null 2>&1 && command -v mkfifo >/dev/null 2>&1; then
  printf 'orig\n' > "$VAULT/vis.md"
  FIFO2="$WORK/fifo2"
  mkfifo "$FIFO2"
  (sleep 8 > "$FIFO2" 2>/dev/null) &
  HOLDER2=$!
  AUTOSAVE_WORK="$WORK" timeout 15 script -qec \
    "vim -u '$WORK/pty_vimrc' -N -S '$REPO/test/autosave_visual_check.vim'" \
    /dev/null < "$FIFO2" >/dev/null 2>&1 || true
  kill "$HOLDER2" 2>/dev/null || true
  wait "$HOLDER2" 2>/dev/null || true
  rm -f "$FIFO2"
  VIS_OUT=$(cat "$WORK/out_visual.txt" 2>/dev/null || true)
  case "$VIS_OUT" in
    mode=V\ modified=1\ line=orig) ;;
    *) fail "ビジュアル中のオートセーブで選択が解除/保存された: ${VIS_OUT:-no-output}";;
  esac
else
  echo "skip: script / mkfifo が無いためビジュアル中デバウンスの確認を省略"
fi

echo "autosave OK"
