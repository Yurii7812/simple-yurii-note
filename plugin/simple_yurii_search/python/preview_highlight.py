#!/usr/bin/env python3
"""fzf の右ペイン（プレビュー）用: ノート本文を出し、クエリ語を ANSI で強調する。

使い方: preview_highlight.py <file> [query...]
- クエリの各語（空白・全角スペース区切り）を赤太字にする。
- 全行をそのまま出す（表示位置は fzf の --preview-window '+{n}/2' に任せる）。
- クエリが空ならハイライトせず出すだけ。
"""
from __future__ import annotations

import re
import sys

RED = "\033[1;31m"
RESET = "\033[0m"


def split_tokens(query: str) -> list[str]:
    return [t for t in re.split(r"[\s\u3000]+", query) if t]


def highlight_line(line: str, tokens: list[str]) -> str:
    for t in tokens:
        tl = t.lower()
        out: list[str] = []
        idx = 0
        while True:
            low = line.lower()
            j = low.find(tl, idx)
            if j < 0:
                out.append(line[idx:])
                break
            out.append(line[idx:j])
            out.append(RED + line[j:j + len(t)] + RESET)
            idx = j + len(t)
        line = "".join(out)
    return line


def main() -> int:
    if len(sys.argv) < 2:
        return 1
    path = sys.argv[1]
    tokens = split_tokens(" ".join(sys.argv[2:]))
    try:
        with open(path, encoding="utf-8", errors="ignore") as f:
            lines = f.read().split("\n")
    except OSError:
        return 1
    sys.stdout.write("\n".join(highlight_line(ln, tokens) for ln in lines))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
