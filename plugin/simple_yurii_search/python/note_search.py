#!/usr/bin/env python3
"""gs / \\L 用: ノートを全文検索して fzf に 1 行ずつ流す。

    <絶対パス> \t <タイトル（ANSI強調）> \t <最初のヒット行>

- 検索は「全クエリ語がタイトルか本文にある」AND。**タイトルに当たった語数が多い順**
  （=タイトル優先）に並べる。同じならタイトル名順。
- クエリが空なら全ノートをタイトル順に出す。
- 左（一覧）はタイトルだけ。右（プレビュー）は preview_highlight.py が
  クエリ語を強調し、3列目のヒット行へスクロールする。
- fzf 側は --disabled で検索しない（検索・並び・強調はこのスクリプトが行う）。

使い方: note_search.py <root> [query...]
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


def split_tokens(query: str) -> list[str]:
    return [t for t in re.split(r"[\s\u3000]+", query) if t]


def title_of(text: str, path: str) -> tuple[str, int]:
    """(タイトル, タイトル行 1 始まり)。YAML title → 先頭 # 見出し → ファイル名。"""
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


def highlight(text: str, tokens: list[str]) -> str:
    for t in tokens:
        tl = t.lower()
        out: list[str] = []
        start = 0
        while True:
            j = text.lower().find(tl, start)
            if j < 0:
                out.append(text[start:])
                break
            out.append(text[start:j])
            out.append(RED + text[j:j + len(t)] + RESET)
            start = j + len(t)
        text = "".join(out)
    return text


def load_notes(root: str):
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
            yield os.path.abspath(p), text


def first_hit_line(lines: list[str], tokens: list[str]) -> int:
    for i, ln in enumerate(lines, 1):
        low = ln.lower()
        if any(t.lower() in low for t in tokens):
            return i
    return 1


def main() -> int:
    root = sys.argv[1] if len(sys.argv) > 1 else "."
    tokens = split_tokens(" ".join(sys.argv[2:]))
    rows: list[tuple[int, str, str, str, int]] = []
    for path, text in load_notes(root):
        title, _tline = title_of(text, path)
        if tokens and not all(t.lower() in text.lower() for t in tokens):
            continue
        title_hits = sum(1 for t in tokens if t.lower() in title.lower())
        line = first_hit_line(text.split("\n"), tokens) if tokens else 1
        rows.append((-title_hits, title.casefold(), path, title, line))
    rows.sort()
    out = []
    for _score, _t, path, title, line in rows:
        out.append(f"{path}\t{highlight(title.replace(chr(9), ' '), tokens)}\t{line}")
    sys.stdout.write("\n".join(out))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
