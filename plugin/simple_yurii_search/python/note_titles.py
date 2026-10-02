#!/usr/bin/env python3
"""\\L 用: ノートを「タイトル」で検索して fzf に流す。

    <絶対パス> : <タイトル行> : 1 : <YAMLタイトル（ヒット語を ANSI 強調）>

- 検索はタイトルだけ（全クエリ語がタイトルに部分一致）。
- タイトル行は右ペインのスクロール中心（fzf の '+{2}/2'）に使う。
- クエリが空なら全ノートを出す。

使い方: note_titles.py <root> [query...]
"""
from __future__ import annotations

import os
import re
import sys

SKIP_DIRS = {".git", ".hg", ".svn", "node_modules", "__pycache__",
             ".venv", "venv", ".mypy_cache", ".pytest_cache"}
MAX_BYTES = 2_000_000
RED = "\033[1;31m"
RESET = "\033[0m"


def title_of(text: str, path: str) -> tuple[str, int]:
    """(タイトル, タイトルが出てくる行番号 1 始まり)。"""
    lines = text.split("\n")
    if lines and lines[0].strip() == "---":
        for i in range(1, min(len(lines), 40)):
            if lines[i].strip() in ("---", "..."):
                break
            m = re.match(r"\s*title\s*:\s*(.+)", lines[i])
            if m:
                return m.group(1).strip().strip("\"'"), i + 1
    for i, ln in enumerate(lines):
        m = re.match(r"#\s+(.+)", ln)
        if m:
            return m.group(1).strip(), i + 1
    return os.path.splitext(os.path.basename(path))[0], 1


def split_tokens(query: str) -> list[str]:
    return [t for t in re.split(r"[\s\u3000]+", query) if t]


def highlight(text: str, tokens: list[str]) -> str:
    for t in tokens:
        tl = t.lower()
        out: list[str] = []
        idx = 0
        while True:
            low = text.lower()
            j = low.find(tl, idx)
            if j < 0:
                out.append(text[idx:])
                break
            out.append(text[idx:j])
            out.append(RED + text[j:j + len(t)] + RESET)
            idx = j + len(t)
        text = "".join(out)
    return text


def clean(s: str) -> str:
    return s.replace("\t", " ").replace("\n", " ")


def main() -> int:
    root = sys.argv[1] if len(sys.argv) > 1 else "."
    tokens = split_tokens(" ".join(sys.argv[2:]))
    out: list[str] = []
    for dp, dns, fns in os.walk(root):
        dns[:] = sorted(d for d in dns if d not in SKIP_DIRS and not d.startswith("."))
        for fn in sorted(fns):
            if not fn.endswith(".md"):
                continue
            p = os.path.join(dp, fn)
            try:
                if os.path.getsize(p) > MAX_BYTES:
                    continue
                with open(p, encoding="utf-8", errors="ignore") as f:
                    text = f.read()
            except OSError:
                continue
            title, line = title_of(text, p)
            low = title.lower()
            if all(t.lower() in low for t in tokens):
                disp = highlight(clean(title), tokens) if tokens else clean(title)
                out.append(f"{os.path.abspath(p)}:{line}:1:{disp}")
    sys.stdout.write("\n".join(out))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
