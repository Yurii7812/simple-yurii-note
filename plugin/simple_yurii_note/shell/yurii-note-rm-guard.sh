# yurii-note-rm-guard.sh
#
# Vim の :!rm %  / :silent !rm % など「Vim から spawn される非対話 bash」で
# rm をラップし、vault 配下の .md（ノート）だけを <root>/.trash/ へ退避する。
# ノート以外・フラグ・ディレクトリは本物の rm にそのまま渡す。
#
# 使い方: プラグインが $BASH_ENV にこのファイルを設定する（bash -c が読み込む）。
#   YURII_NOTE_VAULT … vault のパス（既定: $HOME/files/yurii-note）
#   YURII_NOTE_RM_NO_GUARD=1 … この関数を無効化
#
if [ -n "${YURII_NOTE_RM_NO_GUARD:-}" ]; then
  return 0 2>/dev/null || exit 0
fi
if [ -z "${YURII_NOTE_RM_GUARD_LOADED:-}" ]; then
  YURII_NOTE_RM_GUARD_LOADED=1

  rm() {
    local vault="${YURII_NOTE_VAULT:-$HOME/files/yurii-note}"
    vault="${vault%/}"
    local trash="$vault/.trash"
    local -a rest=()
    local arg abs base dest ts i
    for arg in "$@"; do
      case "$arg" in
        -*) rest+=("$arg"); continue ;;
      esac
      case "$arg" in
        /*) abs="$arg" ;;
        *)  abs="$PWD/$arg" ;;
      esac
      # vault 配下の .md だけゴミ箱へ。.trash 自身や他ファイルは本物の rm へ。
      if [ -f "$abs" ] && [ "${abs##*.}" = "md" ] \
         && [ "${abs#"$vault"/}" != "$abs" ] && [ "${abs#"$trash"/}" = "$abs" ]; then
        mkdir -p "$trash" 2>/dev/null
        ts=$(date +%y%m%d%H%M%S)
        base=$(basename -- "$abs")
        dest="$trash/${ts}_${base}"
        i=1
        while [ -e "$dest" ]; do dest="$trash/${ts}_${i}_${base}"; i=$((i+1)); done
        if mv -- "$abs" "$dest" 2>/dev/null; then
          continue
        fi
      fi
      rest+=("$arg")
    done
    if [ "${#rest[@]}" -gt 0 ]; then command rm "${rest[@]}"; fi
  }
fi
