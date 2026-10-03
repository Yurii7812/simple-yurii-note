#!/usr/bin/env python3
"""操作ガイドの陳腐化チェック。

1. plugin の nnoremap/xnoremap/vnoremap を全部拾い、s:guide_template() に
   載っていなければ失敗（キーを足したらガイドも直せ）。
2. test/guide_keys.txt の必須トークンがガイドに無ければ失敗。
3. 旧名・旧用語が残っていたら失敗。
"""
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
AUTOLOAD = REPO / "plugin/simple_yurii_note/autoload/simple_yurii_note.vim"
MAPPING_FILES = [
    REPO / "plugin/simple_yurii_note/plugin/simple_yurii_note.vim",
    REPO / "plugin/simple_yurii_search/plugin/simple_yurii_search.vim",
    REPO / "plugin/SetImageSize.vim",
    REPO / "plugin/other.vim",
]

# ガイドに載せなくてよい（内部用・Vim 標準の再定義）
EXEMPT_KEYS = {"<C-O>", "."}
MODIFIERS = {"<nowait>", "<silent>", "<buffer>", "<expr>", "<script>", "<unique>"}
BANNED = ["yurii_pkm", "Child", "バックリンク", "タイトルだけ検索"]


def guide_source() -> str:
    text = AUTOLOAD.read_text(encoding="utf-8")
    m = re.search(r"function! s:guide_template\(\).*?\nendfunction", text, re.S)
    if not m:
        sys.exit("NG: s:guide_template() が見つからない")
    return m.group(0)


def mapped_keys() -> list:
    keys = []
    pat = re.compile(r"^\s*(?:nnoremap|xnoremap|vnoremap)\s+(.*)$")
    for path in MAPPING_FILES:
        for line in path.read_text(encoding="utf-8").splitlines():
            if "<buffer" in line:
                continue
            m = pat.match(line)
            if not m:
                continue
            for tok in m.group(1).split():
                if tok in MODIFIERS:
                    continue
                key = tok.replace("<leader>", "\\")
                if key not in keys:
                    keys.append(key)
                break
    return keys


def main() -> int:
    guide = guide_source()
    ng = 0

    for key in mapped_keys():
        if key in EXEMPT_KEYS:
            continue
        if key not in guide:
            print(f"NG: マッピング {key} が操作ガイドに無い。guide_template と guide_keys.txt を更新すること", file=sys.stderr)
            ng += 1

    keys_file = REPO / "test/guide_keys.txt"
    for raw in keys_file.read_text(encoding="utf-8").splitlines():
        token = raw.strip()
        if not token or token.startswith("#"):
            continue
        if token not in guide:
            print(f"NG: guide_keys.txt の {token} が操作ガイドに無い", file=sys.stderr)
            ng += 1

    for bad in BANNED:
        if bad in guide:
            print(f"NG: 操作ガイドに旧表記 {bad!r} が残っている", file=sys.stderr)
            ng += 1

    if ng:
        return 1
    print(f"guide OK ({len(mapped_keys())} mappings)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
