#!/usr/bin/env python3
"""simple_sync の回帰テスト。pytest でも `python3 test_simple_sync.py` でも動く。"""

import importlib.util
import tempfile
from pathlib import Path

_spec = importlib.util.spec_from_file_location("simple_sync", Path(__file__).with_name("simple_sync.py"))
simple_sync = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(simple_sync)


def write(p: Path, text: str) -> None:
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text, encoding="utf-8")


def note(title: str, body: str = "") -> str:
    return f"---\ntitle: {title}\n---\n# {title}\n\n{body}\n\n### Parent\n### BackLink\n"


def sections(text: str) -> tuple[str, str]:
    parent = text.split("### BackLink")[0].split("### Parent", 1)[1]
    back = text.split("### BackLink", 1)[1]
    return parent, back


def test_backlink_is_body_incoming_minus_parent():
    root = Path(tempfile.mkdtemp())
    write(root / "A.md", note("A", "本文で [B](B.md) に触れる。"))
    write(root / "B.md", note("B"))

    simple_sync.sync(root)
    parent, back = sections((root / "B.md").read_text(encoding="utf-8"))
    assert "[A](A.md)" not in parent
    assert "[A](A.md)" in back, "本文リンクは BackLink に入る"

    # A を B の Parent に追加すると BackLink から消える
    b = (root / "B.md").read_text(encoding="utf-8").replace("### Parent\n", "### Parent\n[A](A.md)\n")
    (root / "B.md").write_text(b, encoding="utf-8")
    simple_sync.sync(root)

    parent, back = sections((root / "B.md").read_text(encoding="utf-8"))
    assert "[A](A.md)" in parent
    assert "[A](A.md)" not in back, "Parent にあるものは BackLink に出ない"


def test_body_h2_heading_not_treated_as_structure():
    root = Path(tempfile.mkdtemp())
    write(root / "A.md", note("A", "## 本文中の見出し\nこれは本文の h2。"))
    simple_sync.sync(root)
    text = (root / "A.md").read_text(encoding="utf-8")
    assert "## 本文中の見出し" in text
    assert text.count("### Parent") == 1
    assert text.count("### BackLink") == 1


def _run() -> None:
    test_backlink_is_body_incoming_minus_parent()
    test_body_h2_heading_not_treated_as_structure()
    print("OK: simple_sync tests passed")


if __name__ == "__main__":
    _run()
