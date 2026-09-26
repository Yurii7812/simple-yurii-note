#!/usr/bin/env python3
"""simple_yurii_note の最小同期。

- 本文(Body)のリンク = そのノートの子（outgoing）。`### Child` は無い。
- `### Parent` = 明示的な親。sync は死にリンク・重複の掃除だけ行い、表示名は保つ。
- `### BackLink` = 本文でこのノートにリンクしているが親ではないノート（自動生成）。

使い方:
    simple_sync.py update      ROOT
    simple_sync.py update_one  FILE ROOT
"""

from __future__ import annotations

import os
import re
import sys
from pathlib import Path

PARENT_HDR = "### Parent"
BACK_HDR = "### BackLink"
LINK_RE = re.compile(r"\[([^\]]*)\]\(([^)]+)\)")


def is_md(path: Path) -> bool:
    return path.suffix.lower() == ".md"


def split_front(text: str) -> tuple[list[str], list[str]]:
    lines = text.splitlines()
    if lines and lines[0].strip() == "---":
        for i in range(1, len(lines)):
            if lines[i].strip() == "---":
                return lines[: i + 1], lines[i + 1:]
    return [], lines


def fm_title(fm: list[str]) -> str:
    for ln in fm:
        m = re.match(r"^\s*title\s*:\s*(.+?)\s*$", ln)
        if m:
            return m.group(1).strip()
    return ""


def links(lines: list[str]) -> list[tuple[str, str]]:
    out: list[tuple[str, str]] = []
    for ln in lines:
        for m in LINK_RE.finditer(ln):
            tgt = m.group(2).split("#", 1)[0].strip()
            if tgt.lower().endswith(".md"):
                out.append((m.group(1), tgt))
    return out


def parse(path: Path) -> dict:
    text = path.read_text(encoding="utf-8")
    fm, rest = split_front(text)
    body: list[str] = []
    parent: list[str] = []
    back: list[str] = []
    cur = "body"
    for ln in rest:
        s = ln.strip()
        if s == PARENT_HDR:
            cur = "parent"
            continue
        if s == BACK_HDR:
            cur = "back"
            continue
        (body if cur == "body" else parent if cur == "parent" else back).append(ln)
    return {
        "fm": fm,
        "title": fm_title(fm) or path.stem,
        "body": body,
        "parent": parent,
        "back": back,
    }


def _resolve(target: str, base: Path) -> Path:
    if target.startswith("/"):
        return Path(target).resolve()
    return (base / target).resolve()


def _rel(target: Path, base: Path) -> str:
    return Path(os.path.relpath(target, base)).as_posix()


def render(note: dict, parent: list[tuple[str, Path]], back: list[tuple[str, Path]], path: Path) -> str:
    out = list(note["fm"]) if note["fm"] else ["---", "title: " + note["title"], "---"]
    body = [ln for ln in note["body"]]
    while body and body[-1].strip() == "":
        body.pop()
    out += body

    for hdr, entries in ((PARENT_HDR, parent), (BACK_HDR, back)):
        out.append("")
        out.append(hdr)
        for disp, tgt in entries:
            out.append(f"[{disp}]({_rel(tgt, path.parent)})")

    while out and out[-1].strip() == "":
        out.pop()
    return "\n".join(out) + "\n"


def _iter_md(root: Path):
    root = root.resolve()
    for p in sorted(root.rglob("*.md")):
        if any(part.startswith(".") for part in p.relative_to(root).parts):
            continue
        yield p


def sync(root) -> int:
    root = Path(root).resolve()
    notes: dict[Path, dict] = {p.resolve(): parse(p) for p in _iter_md(root)}
    titles = {p: n["title"] for p, n in notes.items()}

    # 本文リンク = 子（outgoing）
    body_targets: dict[Path, list[Path]] = {}
    for p, n in notes.items():
        ts: list[Path] = []
        for _disp, tgt in links(n["body"]):
            rp = _resolve(tgt, p.parent)
            if rp in notes:
                ts.append(rp)
        body_targets[p] = ts

    incoming: dict[Path, list[Path]] = {p: [] for p in notes}
    for src, tgts in body_targets.items():
        for t in set(tgts):
            if t != src:
                incoming[t].append(src)

    changed = 0
    for p, n in notes.items():
        # Parent: 既存を保つ（死にリンク・重複を除去）
        parent: list[tuple[str, Path]] = []
        seen_p: set[Path] = set()
        for disp, tgt in links(n["parent"]):
            rp = _resolve(tgt, p.parent)
            if rp in notes and rp != p and rp not in seen_p:
                seen_p.add(rp)
                parent.append((disp or titles[rp], rp))
        parent_set = {rp for _, rp in parent}

        # BackLink: 本文で参照されているが Parent でないもの（自動）
        existing_back: dict[Path, str] = {}
        for disp, tgt in links(n["back"]):
            existing_back[_resolve(tgt, p.parent)] = disp
        back_srcs = sorted(
            {s for s in incoming[p] if s not in parent_set and s != p},
            key=lambda x: x.name,
        )
        back = [(existing_back.get(s) or titles[s], s) for s in back_srcs]

        new_text = render(n, parent, back, p)
        old = p.read_text(encoding="utf-8")
        if new_text != old:
            p.write_text(new_text, encoding="utf-8")
            changed += 1
    return changed


def update_one(file_path, root) -> str:
    changed = sync(root)
    return f"simple_yurii_note: synced {changed} file(s)" if changed else "simple_yurii_note: no changes"


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print("usage:\n  simple_sync.py update ROOT\n  simple_sync.py update_one FILE ROOT", file=sys.stderr)
        return 2
    mode = argv[1]
    if mode == "update":
        changed = sync(argv[2])
        print(f"simple_yurii_note: synced {changed} file(s) under {argv[2]}")
        return 0
    if mode == "update_one":
        if len(argv) < 4:
            print("usage: simple_sync.py update_one FILE ROOT", file=sys.stderr)
            return 2
        print(update_one(argv[2], argv[3]))
        return 0
    print(f"unsupported mode: {mode}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
