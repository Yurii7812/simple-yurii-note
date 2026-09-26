#!/usr/bin/env python3
"""vault の各 .md を 1 行に潰して出力する。

    <絶対パス> \t <タイトル> \t <本文全体（空白 1 個に潰す）>

fzf に流して「ファイル単位・行またぎ・キーワード AND」の検索に使う。
`こんにちは 天気` で、その 2 語がファイルのどこかに両方あれば当たる。
"""
from __future__ import annotations

import os
import re
import sys

SKIP_DIRS = {".git", ".hg", ".svn", "node_modules", "__pycache__",
             ".venv", "venv", ".mypy_cache", ".pytest_cache"}
MAX_BYTES = 2_000_000


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


def main() -> int:
    root = sys.argv[1] if len(sys.argv) > 1 else "."
    rows: list[str] = []
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
            body = re.sub(r"\s+", " ", text).strip()
            rows.append(f"{os.path.abspath(p)}\t{title_of(text, p)}\t{body}")
    sys.stdout.write("\n".join(rows))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
