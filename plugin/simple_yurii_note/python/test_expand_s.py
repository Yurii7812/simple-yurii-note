from pathlib import Path

from expand_s import build_expanded_content


def write_note(path: Path, title: str, body: str = "", child: str = "") -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        f"# {title}\n\n{body}\n\nParent:\nChild:\n{child}BackLink:\n",
        encoding="utf-8",
    )


def test_expand_includes_body_links_and_child_hierarchy(tmp_path: Path) -> None:
    root = tmp_path
    source = root / "source.md"
    body_link = root / "body.md"
    child = root / "child.md"
    grandchild = root / "grandchild.md"

    write_note(source, "Source", "本文の[本文リンク](body.md)も展開する。", "[Child](child.md)\n")
    write_note(body_link, "Body", "body text")
    write_note(child, "Child", "child text", "[Grandchild](grandchild.md)\n")
    write_note(grandchild, "Grandchild", "grandchild text")

    content = "\n".join(build_expanded_content(source, root, 2))

    assert "本文の本文リンクも展開する。" in content
    assert "## Body" in content
    assert "## Child" in content
    assert "### Grandchild" in content
    assert "grandchild text" in content
