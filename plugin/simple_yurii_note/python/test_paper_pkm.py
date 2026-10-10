#!/usr/bin/env python3
"""paper_pkm の自己完結テスト（pytest 非依存）。

    python3 test_paper_pkm.py
"""
from __future__ import annotations

import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import japanese_yomi as jy  # noqa: E402
import paper_pkm as pp  # noqa: E402

_FAILED: list[str] = []

_YOMI = {"知識管理": "ちしきかんり", "日記": "にっき"}


def fake_reader(text: str) -> str:
    return _YOMI.get(text, text)


def check(cond: bool, msg: str) -> None:
    if cond:
        print(f"  ok   {msg}")
    else:
        print(f"  FAIL {msg}")
        _FAILED.append(msg)


def _make_vault(root: Path) -> Path:
    (root / "index.md").write_text(
        "---\ntime: 2026-01-01 00:00:00\ntitle: Index\nattribute: group\n---\n\n# Index\n",
        encoding="utf-8",
    )
    return root


def _add_images(root: Path, ids: list[str]) -> list[tuple[Path, str]]:
    out = []
    for fid in ids:
        src = root / f"scan_{fid}.jpg"
        src.write_bytes(b"x")
        out.append((src, fid))
    return out


def test_parse_keyword_line() -> None:
    print("parse_keyword_line: キーワード行の解析")
    e = pp.parse_keyword_line("バナナ: 1,1a10b,3")
    check(e == {"key": "バナナ", "display": "バナナ",
                "ids": ["1", "1a10b", "3"]}, "カンマ区切り")
    e = pp.parse_keyword_line("キーワード: 1 2a")
    check(e is not None and e["ids"] == ["1", "2a"], "空白区切り")
    check(pp.parse_keyword_line("オザーク(ドラマ): 2") is None,
          "括弧付きの行は廃止（紛らわしいため扱わない）")
    check(pp.parse_keyword_line("キーワード: フォルゲゼッテル") is None,
          "ID でない値は行として扱わない")
    check(pp.parse_keyword_line("ただの文章") is None, "普通の文は None")
    check(pp.parse_keyword_line("time: 2026-01-01 00:00:00") is None,
          "front matter の time 行は None（誤マッチ回帰）")
    check(pp.parse_keyword_line("title: Index-write") is None, "title 行は None")
    check(pp.parse_keyword_line("バナナ: 1A10B") is not None, "大文字は正規化して受ける")


def test_keyword_reading() -> None:
    print("keyword_reading: キーワード行のよみ")
    check(pp.keyword_reading("バナナ: 1,2") == "ばなな", "カタカナはひらがな化")
    check(pp.keyword_reading("知識管理: 3") == "ちしきかんり", "漢字のよみ")
    check(pp.keyword_reading("ただの文") is None, "キーワード行でなければ None")


def test_keyword_sort() -> None:
    print("keyword_sort_key: キーワード行のよみ順")
    entries = [
        pp.parse_keyword_line("バナナ: 1,2"),
        pp.parse_keyword_line("知識管理: 3"),
        pp.parse_keyword_line("オザーク: 4"),
    ]
    order = [e["key"] for e in sorted(entries, key=pp.keyword_sort_key)]
    check(order == ["オザーク", "知識管理", "バナナ"], "おざーく < ちしき < ばなな")


def test_id_helpers() -> None:
    print("ID ヘルパー")
    check(pp.parent_id("1a10b") == "1a10", "parent_id")
    check(pp.parent_id("3") is None, "数字だけは親なし")
    check(pp.next_sibling_id("1a") == "1b", "next_sibling_id 英字")
    check(pp.next_sibling_id("9") == "10", "next_sibling_id 数字")
    check(pp.child_id("1a") == "1a1", "child_id 英字")
    check(pp.child_id("1") == "1a", "child_id 数字")
    check(pp.normalize_id("１Ａ") == "1a", "全角の正規化")


def test_create_and_regen() -> None:
    print("create/regen: Index・グループ・Folgezettel-Index・スキャンノート")
    with tempfile.TemporaryDirectory() as d:
        root = _make_vault(Path(d))
        index_path = pp.create_paper_index(root)
        check(index_path.is_file(), "Paper-Zettelkasten-Index ができる")
        check((root / "Index-write.md").is_file(), "Index-write.md ができる")
        check((root / "Folgezettel-Index.md").is_file(), "Folgezettel-Index.md ができる")
        check(pp.find_paper_index(root) == index_path, "paper_index マーカーで見つかる")
        check(pp.create_paper_index(root) == index_path, "2回目は同じ Index を再利用")

        moved, errors = pp.move_images(
            root, root, _add_images(root, ["1", "1a", "2"])
        )
        check(len(moved) == 3 and not errors, "3枚を移動してノート作成")
        notes = {fid: p for fid, p in moved}
        check(notes["1"].name != notes["1a"].name, "ノートはタイムスタンプ名")

        (root / "Index-write.md").write_text(
            "---\ntime: 2026-01-01 00:00:00\ntitle: Index-write\n---\n\n"
            "# Index-write\n\n"
            "バナナ: 1,1a,2\n"
            "オザーク: 2\n",
            encoding="utf-8",
        )
        pp.regen(root)

        index_text = index_path.read_text(encoding="utf-8")
        check("[オザーク]" in index_text and "[バナナ]" in index_text,
              "Index にキーワードリンクが並ぶ")
        check(index_text.index("[オザーク]") < index_text.index("[バナナ]"),
              "Index もよみ順（オザーク < バナナ）")

        group = pp.find_group(root, "バナナ")
        check(group is not None, "複数IDはグループノートができる")
        if group:
            group_text = group.read_text(encoding="utf-8")
            check("attribute: group" in group_text, "グループ属性")
            check(group_text.count(f"]({notes['1'].name})") == 1
                  and f"[1a]({notes['1a'].name})" in group_text
                  and f"[2]({notes['2'].name})" in group_text,
                  "グループに各IDノートへのリンク")
        check(pp.find_group(root, "オザーク") is None,
              "単一IDはグループを作らない")
        check(f"[オザーク]({notes['2'].name})" in index_text,
              "単一IDは Index から直接リンク")

        folge_text = (root / "Folgezettel-Index.md").read_text(encoding="utf-8")
        check(folge_text.index(f"[1]({notes['1'].name})")
              < folge_text.index(f"[2]({notes['2'].name})"), "Folgezettel-Index は自然順")
        check("  [1a]" in folge_text, "Folgezettel-Index は子をインデントで階層表示")
        check("### Parent" in folge_text and "[Paper-Zettelkasten-Index]" in folge_text,
              "Folgezettel-Index の Parent は Paper-Zettelkasten-Index")
        dedicated = pp.folge_index_path(root, "1")
        check(dedicated.is_file(), "専用ノート folgezettel-Index-1 ができる")
        if dedicated.is_file():
            d_text = dedicated.read_text(encoding="utf-8")
            check("## 1" in d_text and f"## 1a" in d_text, "専用ノートに ID 見出し")
            check("folgezettel_index: 1" in d_text, "専用ノートの fm マーカー")
            check(d_text.index("## 1") < d_text.index("## 1a"), "専用ノートは folge 順")
            check("![](" in d_text, "専用ノートに画像")
            check("[Paper-Zettelkasten-Index]" in d_text
                  or "[Folgezettel-Index]" in d_text, "専用ノートの Parent")
        iw_text = (root / "Index-write.md").read_text(encoding="utf-8")
        check("### Parent" in iw_text and "[Paper-Zettelkasten-Index]" in iw_text,
              "Index-write の Parent は Paper-Zettelkasten-Index")
        check("PAPER:START" not in index_text and "PAPER:END" not in folge_text,
              "管理コメントは書かない")
        parent_index = (root / "index.md").read_text(encoding="utf-8")
        check("[Paper-Zettelkasten-Index]" in parent_index,
              "vault の index.md にリンクが足される")

        note1 = notes["1"].read_text(encoding="utf-8")
        check(f"[1a]({notes['1a'].name})" in note1, "親ノートの本文に子リンク")
        check("[folgezettel-Index-1](folgezettel-Index-1.md#1)" in note1,
              "根のノートの Parent は folgezettel-Index-1#1")
        note1a = notes["1a"].read_text(encoding="utf-8")
        check(f"[1]({notes['1'].name})" in note1a, "子ノートの Parent は親ID")

        # キーワードから外した ID のグループ Parent 行は掃除される
        (root / "Index-write.md").write_text(
            "---\ntime: 2026-01-01 00:00:00\ntitle: Index-write\n---\n\n"
            "# Index-write\n\nバナナ: 1,1a\nオザーク: 2\n",
            encoding="utf-8",
        )
        pp.regen(root)
        note2 = notes["2"].read_text(encoding="utf-8")
        check("バナナ" not in note2, "外した ID のグループ Parent 行が消える")


def test_topic_index() -> None:
    print("トピック別Index: 1-仏教 + 1-Index グループ")
    with tempfile.TemporaryDirectory() as d:
        root = _make_vault(Path(d))
        index_path = pp.create_paper_index(root)
        src_topic = root / "scan_1b.jpg"
        src_topic.write_bytes(b"x")
        moved, errors = pp.move_images(
            root, root, _add_images(root, ["1"]) + [(src_topic, "1", "仏教")]
        )
        check(len(moved) == 2 and not errors, "ID と トピック を移動してノート作成")
        notes = {fid: p for fid, p in moved}
        check(notes.get("1") is not None and notes.get("1-仏教") is not None,
              "通常IDとトピック表示名のノート")
        topic_text = notes["1-仏教"].read_text(encoding="utf-8")
        check("paper_topic: 1" in topic_text and "title: 1-仏教" in topic_text,
              "トピックノートの fm")
        pp.regen(root)
        gid = pp.find_id_index(root, "1")
        check(gid is not None, "1-Index グループができる")
        if gid:
            gid_text = gid.read_text(encoding="utf-8")
            check("title: 1-Index" in gid_text, "トピックIndex は 1-Index に改名")
            check(f"[1]({notes['1'].name})" in gid_text and "[1-仏教]" in gid_text,
                  "グループに ID ノートと トピック のリンク")
            check("attribute: group" in gid_text, "グループ属性")
            check("[Paper-Zettelkasten-Index]" in gid_text, "グループの Parent は Paper index")
        n1 = notes["1"].read_text(encoding="utf-8")
        check("[folgezettel-Index-1](folgezettel-Index-1.md#1)" in n1,
              "ID ノートの Parent は folgezettel-Index-1#1")
        d_text = pp.folge_index_path(root, "1").read_text(encoding="utf-8")
        check("[1-Index]" in d_text, "専用ノートにトピックIndexへのリンク")
        topic_text = notes["1-仏教"].read_text(encoding="utf-8")
        i_folge = topic_text.find("[folgezettel-Index-1]")
        i_gindex = topic_text.find("[1-Index]")
        check(i_folge != -1 and i_gindex != -1 and i_folge < i_gindex,
              "トピックノートの Parent は folgezettel-Index-1 + 1-Index")
        folge_text = (root / "Folgezettel-Index.md").read_text(encoding="utf-8")
        check("[1-仏教]" not in folge_text, "Folgezettel-Index にトピック名は出ない")

        # 階層トピック: 仏教/四念処 → 1-四念処（tm: 1-仏教）
        src_n = root / "scan_1c.jpg"
        src_n.write_bytes(b"x")
        moved2, errors2 = pp.move_images(root, root, [(src_n, "1", "四念処", "1-仏教")])
        check(len(moved2) == 1 and not errors2, "階層トピックの作成")

        topic_child = next(p for p in pp.iter_md(root)
                           if "title: 1-四念処" in p.read_text(encoding="utf-8"))
        pp.regen(root)
        gid = pp.find_id_index(root, "1")
        check(gid is not None, "階層後も 1-Index あり")
        gid_text = gid.read_text(encoding="utf-8")
        i_buk = gid_text.find("[1-仏教]")
        i_sinen = gid_text.find("  [1-四念処]")
        check(i_buk != -1 and i_sinen > i_buk,
              "四念処は仏教の下にインデント")



    print("move_images: ID 重複の検出")
    with tempfile.TemporaryDirectory() as d:
        root = _make_vault(Path(d))
        pp.create_paper_index(root)
        moved, errors = pp.move_images(root, root, _add_images(root, ["1"]))
        check(len(moved) == 1 and not errors, "1枚目は成功")
        old_note = moved[0][1]
        moved, errors = pp.move_images(root, root, _add_images(root, ["1"]))
        check(len(moved) == 1 and not errors, "同じ ID は上書き（エラーなし）")
        trashed = list((root / ".trash").glob("*"))
        check(any(p.name.endswith(old_note.name) for p in trashed), "旧ノートは .trash 退避")
        moved, errors = pp.move_images(root, root, _add_images(root, ["1a"]) + _add_images(root, ["1a"]))
        check(len(moved) == 1 and len(errors) == 1, "同じバッチ内の重複もエラー")


def test_regen_without_index() -> None:
    print("regen: Paper-Zettelkasten-Index が無ければ False")
    with tempfile.TemporaryDirectory() as d:
        root = _make_vault(Path(d))
        check(pp.regen(root, do_sync=False) is False, "Index 無しで False")


def main() -> int:
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    for t in tests:
        jy.set_reader(fake_reader)
        try:
            t()
        finally:
            jy.reset_reader()
    print()
    if _FAILED:
        print(f"{len(_FAILED)} FAILED")
        return 1
    print("all passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
