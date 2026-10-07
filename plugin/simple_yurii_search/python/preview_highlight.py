#!/usr/bin/env python3
"""fzf の右ペイン（プレビュー）用: ノート本文を出し、クエリ語を ANSI で強調する。

使い方: preview_highlight.py <file> <query> [--line N]
- クエリの各語（空白・全角スペース区切り）を赤太字にする。
- --line N があれば、N 行目（1 始まり）の少し上から末尾までを出す。
  fzf の --preview-window の +{n}/2 スクロールは「1 論理行 = 1 画面行」前提で、
  wrap で折り返される長い行があるとヒット行がウィンドウ下端で切れてしまう
  （例: 460 桁の行の 326 桁目のヒット）。そのためスクロールに頼らず、ヒット行が
  先頭付近（折返しが上に数行あっても見える位置）に来るよう先頭を削る。
- クエリが空ならハイライトせず出すだけ。
"""
from __future__ import annotations

import re
import sys

RED = "\033[1;31m"
RESET = "\033[0m"

LEAD_LINES = 2


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
    args = sys.argv[1:]
    hit = 0
    if "--line" in args:
        i = args.index("--line")
        try:
            hit = int(args[i + 1])
        except (IndexError, ValueError):
            hit = 0
        del args[i:i + 2]
    if not args:
        return 1
    path = args[0]
    tokens = split_tokens(" ".join(args[1:]))
    try:
        with open(path, encoding="utf-8", errors="ignore") as f:
            lines = f.read().split("\n")
    except OSError:
        return 1
    start = max(0, hit - 1 - LEAD_LINES) if hit > 0 else 0
    sys.stdout.write("\n".join(highlight_line(ln, tokens) for ln in lines[start:]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
