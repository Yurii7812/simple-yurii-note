#!/usr/bin/env python3
"""gs 用: ノートを全件 or 全文検索して fzf に 1 行ずつ流す。

    <絶対パス> \t <ヒット行番号> \t <YAMLタイトル> \t <抜粋>

- 表示は「タイトル（＋ヒット箇所の抜粋）」。検索は fzf 側（表示列＝検索列）に任せる。
- ヒットした全クエリ語がタイトルか抜粋に必ず入るようにするので、fzf の絞り込みで
  消えず、そのままハイライトされる。
- ヒット行番号は右ペイン（fzf.vim の preview.sh）のスクロール中心に使う。
- クエリが空なら全ノート（抜粋なし・1 行目）を出す。

使い方: python3 note_search.py <root> [query...]
"""
from __future__ import annotations

import os
import re
import sys

SKIP_DIRS = {".git", ".hg", ".svn", "node_modules", "__pycache__",
             ".venv", "venv", ".mypy_cache", ".pytest_cache"}
MAX_BYTES = 2_000_000
SNIPPET_WIDTH = 40


def title_of(text: str, path: str) -> str:
    lines = text.split("\n")
    if lines and lines[0].strip() == "---":
        for i in range(1, min(len(lines), 40)):
            if lines[i].strip() in ("---", "..."):
                break
            m = re.match(r"\s*title\s*:\s*(.+)", lines[i])
            if m:
                return m.group(1).strip().strip("\"'")
    for ln in lines:
        m = re.match(r"#\s+(.+)", ln)
        if m:
            return m.group(1).strip()
    return os.path.splitext(os.path.basename(path))[0]


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
            yield os.path.abspath(p), title_of(text, p), text


def body_of(text: str) -> str:
    """frontmatter と先頭見出しを除いた本文（空白 1 個に潰す）。"""
    lines = text.split("\n")
    i = 0
    if lines and lines[0].strip() == "---":
        i = 1
        while i < len(lines) and lines[i].strip() not in ("---", "..."):
            i += 1
        i += 1
    while i < len(lines) and (lines[i].strip() == "" or lines[i].lstrip().startswith("#")):
        i += 1
    return re.sub(r"\s+", " ", "\n".join(lines[i:])).strip()


def hit_line(text: str, tokens: list[str]) -> int:
    """クエリ語が最初に出てくる行番号（1 始まり）。無ければ 1。"""
    lines = text.split("\n")
    for i, ln in enumerate(lines):
        low = ln.lower()
        if any(t.lower() in low for t in tokens):
            return i + 1
    return 1


def _context(hay: str, t: str) -> str:
    i = hay.lower().find(t.lower())
    if i < 0:
        return ""
    s = max(0, i - SNIPPET_WIDTH)
    e = min(len(hay), i + len(t) + SNIPPET_WIDTH)
    return ("…" if s > 0 else "") + hay[s:e] + ("…" if e < len(hay) else "")


def snippet_for(title: str, text: str, tokens: list[str]) -> str:
    body = body_of(text)
    full = re.sub(r"\s+", " ", text).strip()
    title_low = title.lower()
    parts: list[str] = []
    for t in tokens:
        if t.lower() in title_low:
            continue  # タイトル側でハイライトされるので抜粋不要
        seg = _context(body, t) or _context(full, t)
        if seg:
            parts.append(seg)
    if not parts:
        return ""
    return "  …  ".join(parts)


def clean(s: str) -> str:
    return s.replace("\t", " ").replace("\n", " ")


def main() -> int:
    root = sys.argv[1] if len(sys.argv) > 1 else "."
    query = " ".join(sys.argv[2:])
    tokens = [t for t in re.split(r"[\s\u3000]+", query) if t]
    out: list[str] = []
    for path, title, text in load_notes(root):
        hay = (title + "\n" + text).lower()
        if all(t.lower() in hay for t in tokens):
            snip = snippet_for(title, text, tokens) if tokens else ""
            line = hit_line(text, tokens) if tokens else 1
            out.append(f"{path}\t{line}\t{clean(title)}\t{clean(snip)}")
    sys.stdout.write("\n".join(out))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
