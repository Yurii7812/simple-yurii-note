#!/usr/bin/env python3
"""expand_v2 の自己完結テスト（pytest 非依存）。

現行のノート形式（`### Parent` / `### Related` / `### BackLink`。子 = 本文リンク）と
現役エンジン `simple_sync` で動かす。

    python3 test_expand_v2.py
"""
from __future__ import annotations

import sys
import tempfile
from pathlib import Path

import expand_v2 as ex
import note_format_v2 as v2

_FAILED: list[str] = []


def check(cond: bool, msg: str) -> None:
    if cond:
        print(f"  ok   {msg}")
    else:
        print(f"  FAIL {msg}")
        _FAILED.append(msg)


UP_MARK = v2.UP_MARK
RELATED_MARK = v2.RELATED_MARK
DOWN_MARK = v2.DOWN_MARK


def note(path: Path, title: str, body: str = "", parent: str = "",
         related: str = "", back: str = "", attr: str = "") -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    txt = f"---\ntime: 2026-01-01 00:00:00\ntitle: {title}\n"
    if attr:
        txt += f"attribute: {attr}\n"
    txt += "---\n\n# " + title + "\n\n"
    if body:
        txt += body.strip("\n") + "\n\n"
    txt += f"{UP_MARK}\n"
    if parent:
        txt += parent.strip("\n") + "\n"
    if related:
        txt += f"{RELATED_MARK}\n" + related.strip("\n") + "\n"
    txt += f"{DOWN_MARK}\n"
    if back:
        txt += back.strip("\n") + "\n"
    path.write_text(txt, encoding="utf-8")


def _fixture(root: Path) -> None:
    """G(グループ) の子が A。A の本文は B。D が本文で A に言及。A と R は Related。"""
    note(root / "G.md", "G", body="[A](A.md)", attr="group")
    note(root / "A.md", "A", body="Aの本文。参照: [B](B.md)", related="[R](R.md)")
    note(root / "B.md", "B")
    note(root / "D.md", "D", body="Dの本文。言及: [A](A.md)")
    note(root / "R.md", "R", related="[A](A.md)")
    v2.simple_sync(root)


def _dir_of(root: Path, by_name, notes, ids, id_to_path):
    def dir_of(nid: str):
        p = id_to_path[nid]
        return ex._directions(p, notes[p], root, by_name, ids)
    return dir_of


def test_directions_parent_child_backlink_related() -> None:
    print("directions: 現行形式の 親(Parent)/子(本文)/文中(BackLink+Related)")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        _fixture(root)
        by_name, notes, ids, id_to_path = ex._build_index(root)
        a_p = (root / "A.md").resolve()
        d_a = ex._directions(a_p, notes[a_p], root, by_name, ids)
        check(d_a["parent"] == {ids[(root / "G.md").resolve()]}, "A の親は ### Parent の G")
        check(d_a["child"] == {ids[(root / "B.md").resolve()]}, "A の子は本文リンクの B")
        check(d_a["backlink"] == {ids[(root / "D.md").resolve()]},
              "A の文中（### BackLink）は D だけ（Related を混ぜない）")
        check(d_a["related"] == {ids[(root / "R.md").resolve()]},
              "A の関連（### Related）は R（独立した方向）")


def test_simple_mode_depth1() -> None:
    print("simple: 深さ1で親・子・文中すべてを平等に1階層集める")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        _fixture(root)
        by_name, notes, ids, id_to_path = ex._build_index(root)
        start_id = ids[(root / "A.md").resolve()]
        order, _po = ex.collect_simple(start_id, _dir_of(root, by_name, notes, ids, id_to_path), 1)
        titles = {notes[id_to_path[i]]["title"] for i in order}
        check(titles == {"A", "G", "B", "D", "R"}, "深さ1で親G・子B・文中D・関連Rが全部入る")


def test_simple_mode_depth0_only_start() -> None:
    print("simple: 深さ0なら起点だけ")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        _fixture(root)
        by_name, notes, ids, id_to_path = ex._build_index(root)
        start_id = ids[(root / "A.md").resolve()]
        order, _po = ex.collect_simple(
            start_id, _dir_of(root, by_name, notes, ids, id_to_path), 0)
        check(order == [start_id], "深さ0は起点ノートのみ")


def test_detailed_mode_independent_budgets() -> None:
    print("detailed: 種類ごとに独立した深さで絞り込める（子/親/文中/関連）")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        _fixture(root)
        by_name, notes, ids, id_to_path = ex._build_index(root)
        start_id = ids[(root / "A.md").resolve()]
        dir_of = _dir_of(root, by_name, notes, ids, id_to_path)

        order, _po = ex.collect_detailed(start_id, dir_of, 1, 0, 0, 0)
        titles = {notes[id_to_path[i]]["title"] for i in order}
        check(titles == {"A", "B"}, "子だけ許可だと A と B だけ")

        order2, _po2 = ex.collect_detailed(start_id, dir_of, 0, 1, 0, 0)
        titles2 = {notes[id_to_path[i]]["title"] for i in order2}
        check(titles2 == {"A", "G"}, "親だけ許可だと A と G だけ")

        order3, _po3 = ex.collect_detailed(start_id, dir_of, 0, 0, 1, 0)
        titles3 = {notes[id_to_path[i]]["title"] for i in order3}
        check(titles3 == {"A", "D"}, "文中だけ許可だと A と D だけ（関連の R は入らない）")

        order4, _po4 = ex.collect_detailed(start_id, dir_of, 0, 0, 0, 1)
        titles4 = {notes[id_to_path[i]]["title"] for i in order4}
        check(titles4 == {"A", "R"}, "関連だけ許可だと A と R だけ（文中の D は入らない）")


def test_detailed_mode_parent_does_not_leak_siblings() -> None:
    print("detailed: 親を辿った先（ハブ）の他の子までは展開しない")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        # G(グループ) の子は A と H。A は深い子チェーン A->C1->C2 を持つ。
        # G の別の子 H やその子 HC は、A から見た展開には一切出てはいけない
        # （親チェーンは「純粋に親だけ」を辿り、途中のノードの子は展開しない）。
        note(root / "G.md", "G", body="[A](A.md)\n[H](H.md)", attr="group")
        note(root / "A.md", "A", body="[C1](C1.md)")
        note(root / "C1.md", "C1", parent="[A](A.md)", body="[C2](C2.md)")
        note(root / "C2.md", "C2", parent="[C1](C1.md)")
        note(root / "H.md", "H", body="[HC](HC.md)")
        note(root / "HC.md", "HC", parent="[H](H.md)")
        v2.simple_sync(root)

        by_name, notes, ids, id_to_path = ex._build_index(root)
        start_id = ids[(root / "A.md").resolve()]

        # 子を深く(3)・親は浅く(1)。子チェーン A->C1->C2 と、A 自身の親 G は
        # 含まれるが、G のもう一つの子 H やその子 HC は含まれない。
        order, _po = ex.collect_detailed(
            start_id, _dir_of(root, by_name, notes, ids, id_to_path),
            child_depth=3, parent_depth=1, backlink_depth=0, related_depth=0)
        titles = {notes[id_to_path[i]]["title"] for i in order}
        check(titles == {"A", "C1", "C2", "G"},
              "親を1回辿った先(G)がハブでも、G の他の子(H)やその子(HC)までは展開しない")


def test_detailed_mode_each_child_chain_node_gets_own_parent_and_backlink() -> None:
    print("detailed: 子チェーン上の各ノードそれぞれが、自分自身の親・文中・関連を独立に持ってくる")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        # A(起点) の親は G。A の子 C1 の親は別の note P（A の親ではない）。
        # C1 は本文で自分に言及している D1 を BackLink に、R1 を Related に持つ。
        note(root / "G.md", "G", body="[A](A.md)", attr="group")
        note(root / "P.md", "P", body="Pの本文。参照: [C1](C1.md)")
        note(root / "A.md", "A", body="[C1](C1.md)")
        note(root / "C1.md", "C1", parent="[P](P.md)", related="[R1](R1.md)")
        note(root / "D1.md", "D1", body="D1の本文。言及: [C1](C1.md)")
        note(root / "R1.md", "R1", related="[C1](C1.md)")
        v2.simple_sync(root)

        by_name, notes, ids, id_to_path = ex._build_index(root)
        start_id = ids[(root / "A.md").resolve()]

        order, _po = ex.collect_detailed(
            start_id, _dir_of(root, by_name, notes, ids, id_to_path),
            child_depth=1, parent_depth=1, backlink_depth=1, related_depth=1)
        titles = {notes[id_to_path[i]]["title"] for i in order}
        check(titles == {"A", "C1", "G", "P", "D1", "R1"},
              "起点(A)の親G・子C1に加えて、C1自身の親P・文中D1・関連R1も独立に含まれる")


def test_relation_links_shown_even_for_terminal_nodes() -> None:
    print("render: 展開されなかったノート（終端）でも、そのノートの関係リンクは表示する")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        # Index は子（本文リンク）に 日記・simple_yurii_note を持つが、この展開では
        # 深さの都合で Index 自体は含まれても、その子は展開されない。
        note(root / "index.md", "Index",
             body="[日記](diary.md)\n[simple_yurii_note](pkm.md)\n[A](A.md)")
        note(root / "diary.md", "日記", parent="[Index](index.md)")
        note(root / "pkm.md", "simple_yurii_note", parent="[Index](index.md)")
        note(root / "A.md", "A", parent="[Index](index.md)")
        v2.simple_sync(root)

        out_path = ex._run(root, root / "A.md",
                            lambda sid, dir_of: ex.collect_detailed(sid, dir_of, 0, 1, 0, 0))
        text = out_path.read_text(encoding="utf-8")
        check("## Index" in text, "Index 自体は展開結果に含まれる（終端として）")
        check("## 日記" not in text and "## simple_yurii_note" not in text,
              "Index の子（日記・simple_yurii_note）はこの深さでは展開されない")
        check("[日記](" in text and "[simple_yurii_note](" in text,
              "それでも Index の関係リンクとして 日記・simple_yurii_note へのリンクは表示される")
        check("- 子（本文）: [日記](" in text, "関係リンクは現行セクション名（子（本文））で出る")


def test_relation_links_show_all_sections() -> None:
    print("render: 関係リンクは 親/関連/子（本文）/バックリンク を区別して表示する")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        _fixture(root)
        out_path = ex._run(root, root / "A.md",
                            lambda sid, dir_of: ex.collect_simple(sid, dir_of, 1))
        text = out_path.read_text(encoding="utf-8")
        check("- 親: [G](" in text, "親セクションが出る")
        check("- 関連: [R](" in text, "関連セクションが出る（ノートに混ざらない）")
        check("- 子（本文）: [B](" in text, "子（本文）セクションが出る")
        check("- バックリンク: [D](" in text, "バックリンクセクションが出る")


def test_toc_is_nested_by_discovery_path() -> None:
    print("目次: 発見経路に沿ってインデントされる（フラットな一覧ではない）")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        _fixture(root)
        out_path = ex._run(root, root / "A.md",
                            lambda sid, dir_of: ex.collect_simple(sid, dir_of, 1))
        text = out_path.read_text(encoding="utf-8")
        toc = text.split("## 目次")[1].split("---")[0]
        toc_lines = [ln for ln in toc.split("\n") if ln.strip().startswith("-")]
        check(toc_lines[0].startswith("- ["), "起点はインデント0")
        check(all(ln.startswith("  - [") for ln in toc_lines[1:]),
              "起点から直接発見されたものは1段インデントされる")


def test_render_strips_own_h1_and_frontmatter() -> None:
    print("render: front matter・見張りコメントは出さず、自分の H1 も二重にしない")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        _fixture(root)
        out_path = ex._run(root, root / "A.md",
                            lambda sid, dir_of: ex.collect_simple(sid, dir_of, 1))
        text = out_path.read_text(encoding="utf-8")
        check("attribute:" not in text, "front matter は含まれない")
        check(UP_MARK not in text and DOWN_MARK not in text and RELATED_MARK not in text,
              "見張り（### Parent / ### Related / ### BackLink）は含まれない")
        lines = text.split("\n")
        check("# A" not in lines, "本文側の重複 H1 (# A) は除去される（## A だけが残る）")
        check("## A" in text and "## G" in text and "## B" in text and "## D" in text,
              "各ノートが見出しとして出る")
        check("Aの本文。参照:" in text, "本文の中身は保持される")


def test_run_creates_file_under_tmp_dir() -> None:
    print("run: 出力先は ROOT/_tmp/T_<timestamp>.md")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        _fixture(root)
        out_path = ex._run(root, root / "A.md",
                            lambda sid, dir_of: ex.collect_simple(sid, dir_of, 0))
        check(out_path.parent == root / v2.EXPAND_TMP_DIR, "_tmp ディレクトリの下に作られる")
        check(out_path.name.startswith("T_") and out_path.suffix == ".md",
              "ファイル名は T_ + タイムスタンプ")


def test_tmp_dir_excluded_from_sync_scan() -> None:
    print("sync: _tmp 配下のファイルは vault スキャンから除外される")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        _fixture(root)
        out_path = ex._run(root, root / "A.md",
                            lambda sid, dir_of: ex.collect_simple(sid, dir_of, 1))
        check(out_path.exists(), "展開ファイル自体は作られている")
        found = [p for p in v2._iter_md(root) if v2.EXPAND_TMP_DIR in p.relative_to(root).parts]
        check(found == [], "_iter_md は _tmp 配下を無視する")


def test_prefs_roundtrip() -> None:
    print("prefs: detailed 実行後に前回設定を記録・復元できる")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        _fixture(root)
        check(ex._load_prefs(root) is None, "初回は前回設定なし")
        ex._run(root, root / "A.md",
                lambda sid, dir_of: ex.collect_detailed(sid, dir_of, 2, 1, 0, 1))
        ex._save_prefs(root, 2, 1, 0, 1)
        prefs = ex._load_prefs(root)
        check(prefs == {"child": 2, "parent": 1, "backlink": 0, "related": 1},
              "保存した数値がそのまま読み出せる")


def test_prefs_old_format_defaults_related_zero() -> None:
    print("prefs: 関連が無い旧形式の保存値は related=0 として読める")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        (root / ex._PREFS_FILE).write_text(
            '{"child": 1, "parent": 2, "backlink": 3}', encoding="utf-8")
        prefs = ex._load_prefs(root)
        check(prefs == {"child": 1, "parent": 2, "backlink": 3, "related": 0},
              "旧 prefs（related 無し）は 0 で補完される")


def main() -> int:
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    for t in tests:
        t()
    print()
    if _FAILED:
        print(f"{len(_FAILED)} FAILED")
        return 1
    print("all passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
