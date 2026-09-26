#!/usr/bin/env python3
"""Vim の関数参照が解決するかを静的に検査する（分割リファクタ用の網）。

- `s:foo(` の参照は、**同じファイル内** に定義があること。
- `simple_yurii_note#...(` の参照は、autoload/ 以下のどこかに定義があること
  （Vim の autoload は名前からファイルパスを決めるので、名前とファイルの対応も見る）。
- どのファイルにも定義が無いのに呼ばれている関数を NG にする。

使い方: python3 test/vim_static_check.py
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
AUTOLOAD_ROOT = REPO / "plugin" / "simple_yurii_note" / "autoload"

DEF_RE = re.compile(r"^\s*fu(?:nction)?!?\s+([A-Za-z0-9_:#]+)", re.M)
S_CALL_RE = re.compile(r"\bs:([A-Za-z_][A-Za-z0-9_]*)\s*\(")
NS_CALL_RE = re.compile(r"\b(simple_yurii_note#[A-Za-z0-9_#]+)\s*\(")


def vim_files() -> list[Path]:
    return sorted(p for p in REPO.rglob("*.vim") if ".git" not in p.parts)


def defined_in(text: str) -> set[str]:
    return set(DEF_RE.findall(text))


def main() -> int:
    files = vim_files()
    per_file_defs: dict[Path, set[str]] = {}
    all_defs: set[str] = set()
    for p in files:
        d = defined_in(p.read_text(encoding="utf-8", errors="ignore"))
        per_file_defs[p] = d
        all_defs |= d

    ng = 0
    for p in files:
        text = p.read_text(encoding="utf-8", errors="ignore")
        local = per_file_defs[p]
        for name in S_CALL_RE.findall(text):
            if f"s:{name}" not in local:
                print(f"NG {p.relative_to(REPO)}: s:{name}() はこのファイルに定義が無い")
                ng += 1
        for name in NS_CALL_RE.findall(text):
            if name not in all_defs:
                print(f"NG {p.relative_to(REPO)}: {name}() の定義がどこにも無い")
                ng += 1

    # autoload 名前空間とファイルパスの対応（simple_yurii_note#a#b -> autoload/simple_yurii_note/a.vim）
    for name in sorted(all_defs):
        if not name.startswith("simple_yurii_note#"):
            continue
        parts = name.split("#")
        if len(parts) == 2:
            expected = AUTOLOAD_ROOT / "simple_yurii_note.vim"
        else:
            expected = AUTOLOAD_ROOT / ("/".join(parts[1:-1]) + ".vim")
        if not expected.exists():
            print(f"NG: {name}() は {expected.relative_to(REPO)} に無いと autoload できない")
            ng += 1

    if ng:
        print(f"\n{ng} NG")
        return 1
    print(f"static OK ({len(files)} files)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
