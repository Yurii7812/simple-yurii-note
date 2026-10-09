#!/usr/bin/env python3
"""japanese_yomi / sort_yomi の自己完結テスト（pytest 非依存・pykakasi 非依存）。

読みは注入するので pykakasi が無くても通る。

    python3 test_sort_yomi.py
"""
from __future__ import annotations

import contextlib
import io
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import japanese_yomi as jy  # noqa: E402
import note_format_v2 as nf  # noqa: E402
import paper_pkm as pp  # noqa: E402
import sort_yomi  # noqa: E402

_FAILED: list[str] = []

# テスト用の読み（pykakasi の代わり）
_YOMI = {
    "日記": "にっき",
    "ハーブ・薬草": "はーぶやくそう",
    "行動のために": "こうどうのために",
    "タルパ": "たるぱ",
    "解剖学": "かいぼうがく",
    "就職": "しゅうしょく",
    "知識管理": "ちしきかんり",
    "筋トレ": "すじとれ",
}


def fake_reader(text: str) -> str:
    return _YOMI.get(text, text)


def check(cond: bool, msg: str) -> None:
    if cond:
        print(f"  ok   {msg}")
    else:
        print(f"  FAIL {msg}")
        _FAILED.append(msg)


def _link_lines(lines: list[str]) -> list[str]:
    return [ln for ln in lines if jy._LINK_RE.search(ln)]


def test_reading_key_order() -> None:
    print("reading_key: 五十音順（かな）")
    keys = {w: jy.reading_key(w) for w in ["日記", "解剖学", "就職", "タルパ"]}
    check(keys["解剖学"] < keys["就職"] < keys["タルパ"] < keys["日記"], "かいぼう < しゅう < たるぱ < にっき")


def test_reading_key_latin_last() -> None:
    print("reading_key: ローマ字は末尾で英字順")
    check(jy.reading_key("日記") < jy.reading_key("AI"), "かな < ローマ字")
    check(jy.reading_key("AI") < jy.reading_key("Discord") < jy.reading_key("linux"), "AI < Discord < linux")


def test_reading_key_ignores_long_vowel_middot() -> None:
    print("reading_key: 長音・中黒を無視")
    check(jy.reading_key("ハーブ・薬草") == jy.reading_key("はぶやくそう"), "ハーブ・薬草 == はぶやくそう")


def test_reading_key_dakuten_same_rank() -> None:
    print("reading_key: 濁音・半濁音は清音と同じ扱い（区別しない）")
    check(jy.reading_key("ぐらふ") < jy.reading_key("こうりつか"), "ぐ < こ（ぐはくと同じ位置）")
    check(jy.reading_key("じぶん") < jy.reading_key("すじとれ"), "じ < す")
    check(jy.reading_key("だんみん") < jy.reading_key("ちしき"), "だ < ち")
    check(jy.reading_key("ぱそこん") < jy.reading_key("ひらがな"), "ぱ < ひ")
    check(jy.reading_key("かき") == jy.reading_key("がき"), "か = が（同ランク）")


def test_reading_key_latin_first_last() -> None:
    print("reading_key: 英字で始まるよみはかなを含んでも末尾")
    key = jy.reading_key("simple-yurii-note そうさがいど")
    check(jy.reading_key("日記") < key, "かな < 英字始まり")
    check(jy.reading_key("AI") < key < jy.reading_key("Vim"), "AI < simple… < Vim")


def test_yomi_map_roundtrip() -> None:
    print("yomi map: parse / set の往復")
    fm = ["---", "time: 1", "title: 筋トレ", "---"]
    new_fm = jy.set_yomi_map(fm, {"筋トレ": "きんとれ", "筋トレ日記": "きんとれにっき"})
    check(new_fm[0:3] == ["---", "time: 1", "title: 筋トレ"], "先頭は保持")
    check(jy.parse_yomi_map(new_fm) == {"筋トレ": "きんとれ", "筋トレ日記": "きんとれにっき"}, "往復一致")
    removed = jy.set_yomi_map(new_fm, {})
    check(jy.parse_yomi_map(removed) == {}, "空マップでブロック削除")
    check("yomi:" not in "\n".join(removed), "yomi 行が残らない")


def test_set_get_yomi_file() -> None:
    print("set/get_yomi: ノートファイルに保存")
    with tempfile.TemporaryDirectory() as d:
        p = Path(d) / "x.md"
        p.write_text("---\ntime: 1\ntitle: 筋トレ\nattribute: group\n---\n\n# 筋トレ\n", encoding="utf-8")
        check(jy.set_yomi(p, "筋トレ", "きんとれ") is True, "登録で True")
        check(jy.set_yomi(p, "筋トレ", "きんとれ") is False, "同値は False")
        check(jy.get_yomi(p, "筋トレ") == "きんとれ", "登録値を取得")
        check(jy.set_yomi(p, "筋トレ", "") is True, "空で削除")
        text = p.read_text(encoding="utf-8")
        check("yomi:" not in text and "attribute: group" in text, "削除後も他キーは保持")


def test_list_yomi_names() -> None:
    print("list_yomi_names: 登録順の表示名一覧")
    with tempfile.TemporaryDirectory() as d:
        p = Path(d) / "x.md"
        p.write_text(
            "---\ntime: 1\ntitle: ハーブ・薬草\nyomi:\n"
            '  "ハーブ": "はーぶ"\n  "薬草": "やくそう"\n---\n',
            encoding="utf-8",
        )
        check(jy.list_yomi_names(p) == ["ハーブ", "薬草"], "登録順に返す")
        check(jy.list_yomi_names(Path(d) / "none.md") == [], "無いファイルは空")


def test_sort_lines_display_name() -> None:
    print("sort_lines: リンク行だけ表示名で並ぶ・非リンク行は動かない")
    lines = [
        "# Index",
        "",
        "[日記](a.md)",
        "[解剖学](b.md)",
        "[タルパ](c.md)",
        "[AI](i.md)",
        "[Discord](h.md)",
        "",
        "散文",
    ]
    with tempfile.TemporaryDirectory() as d:
        out = jy.sort_lines(lines, d)
    check(out[0:2] == ["# Index", ""], "先頭の見出し・空行はそのまま")
    check(out[7:9] == ["", "散文"], "末尾の空行・散文はそのまま")
    check(_link_lines(out) == [
        "[解剖学](b.md)",
        "[タルパ](c.md)",
        "[日記](a.md)",
        "[AI](i.md)",
        "[Discord](h.md)",
    ], "かな→ローマ字末尾の順")


def test_sort_lines_yomi_override() -> None:
    print("sort_lines: ノートの yomi: が pykakasi より優先")
    with tempfile.TemporaryDirectory() as d:
        note = Path(d) / "x.md"
        note.write_text(
            "---\ntitle: 筋トレ\nyomi:\n  \"筋トレ\": \"きんとれ\"\n---\n", encoding="utf-8"
        )
        lines = ["[筋トレ](x.md)", "[就職](f.md)"]
        out = jy.sort_lines(lines, d)
    check(out == ["[筋トレ](x.md)", "[就職](f.md)"], "きんとれ < しゅうしょく（すじとれなら負ける）")


def test_sort_lines_stable() -> None:
    print("sort_lines: 同じよみは元の順（安定）")
    lines = ["[A](a.md)", "[B](b.md)", "[C](c.md)"]
    with tempfile.TemporaryDirectory() as d:
        out = jy.sort_lines(lines, d)
    check(out == lines, "同よみは不変")


def test_sort_lines_ignores_sections() -> None:
    print("sort_lines: ### Parent / ### BackLink のリンクは動かさない")
    lines = [
        "[タルパ](c.md)",
        "[解剖学](b.md)",
        "### Parent",
        "[日記](a.md)",
        "### BackLink",
        "[就職](e.md)",
    ]
    with tempfile.TemporaryDirectory() as d:
        out = jy.sort_lines(lines, d)
    check(out[0:2] == ["[解剖学](b.md)", "[タルパ](c.md)"], "本文リンクは並ぶ")
    check(out[2:5] == ["### Parent", "[日記](a.md)", "### BackLink"], "Parent はそのまま")
    check(out[5] == "[就職](e.md)", "BackLink はそのまま")


def test_sort_lines_inline_link_untouched() -> None:
    print("sort_lines: 文章中に埋もれたリンクは動かさない")
    lines = [
        "前置きの文。[日記](a.md) を参照。",
        "[タルパ](c.md)",
        "[解剖学](b.md)",
    ]
    with tempfile.TemporaryDirectory() as d:
        out = jy.sort_lines(lines, d)
    check(out[0] == "前置きの文。[日記](a.md) を参照。", "文章行はそのまま")
    check(out[1:] == ["[解剖学](b.md)", "[タルパ](c.md)"], "リンクだけの行だけ並ぶ")


def test_sort_lines_group_with_prose_and_parent() -> None:
    print("sort_lines: グループ（文章 + Parent つき）の本文だけ並ぶ")
    yomi = {
        "移動": "いどう",
        "紙のPKMのスキャン": "かみのPKMのすきゃん",
        "効率化": "こうりつか",
        "グラフビュー": "ぐらふびゅー",
        "グループ・索引": "ぐるーぷ・さくいん",
        "simple-yurii-note 操作ガイド": "simple-yurii-note そうさがいど",
        "プログラミング": "ぷろぐらみんぐ",
        "知識管理": "ちしきかんり",
    }
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        for i, (name, reading) in enumerate(yomi.items()):
            (root / f"{i}.md").write_text(
                f'---\ntitle: {name}\nyomi:\n  "{name}": "{reading}"\n---\n',
                encoding="utf-8")
        links = {name: f"[{name}]({i}.md)" for i, name in enumerate(yomi)}
        lines = [
            "# グループ",
            "",
            "グループの説明文。",
            links["プログラミング"],
            links["効率化"],
            links["移動"],
            links["simple-yurii-note 操作ガイド"],
            links["グラフビュー"],
            links["紙のPKMのスキャン"],
            links["グループ・索引"],
            "### Parent",
            links["知識管理"],
            "### BackLink",
        ]
        out = jy.sort_lines(lines, d)
    check(out[2] == "グループの説明文。", "文章はそのまま")
    check(out[3:10] == [
        links["移動"],
        links["紙のPKMのスキャン"],
        links["グラフビュー"],
        links["グループ・索引"],
        links["効率化"],
        links["プログラミング"],
        links["simple-yurii-note 操作ガイド"],
    ], "本文は い→か→く→く→こ→英字末尾")
    check(out[10:] == ["### Parent", links["知識管理"], "### BackLink"], "Parent は動かない")


def _keyword_key(line: str):
    reading = pp.keyword_reading(line)
    return jy.reading_key(reading) if reading else None


def test_sort_keyword_lines() -> None:
    print("sort_lines: --keyword-lines で Index_write のキーワード行も並ぶ")
    lines = [
        "---",
        "time: 2026-01-01 00:00:00",
        "title: Index_write",
        "---",
        "",
        "# Index_write",
        "",
        "バナナ: 1,2",
        "オザーク: 3",
        "知識管理: 4",
        "ただの文",
    ]
    with tempfile.TemporaryDirectory() as d:
        out = jy.sort_lines(lines, d, extra_key_fn=_keyword_key)
    check(out[0:7] == lines[0:7], "front matter・見出し・空行は動かない")
    check(out[7:10] == ["オザーク: 3", "知識管理: 4",
                        "バナナ: 1,2"],
          "おざーく < ちしき < ばなな")
    check(out[10] == "ただの文", "キーワード行でない文は動かない")
    with tempfile.TemporaryDirectory() as d:
        out2 = jy.sort_lines(lines, d)
    check(out2 == lines, "フラグ無しならキーワード行は動かない")


def test_cli_keyword_lines() -> None:
    print("sort_yomi CLI: --keyword-lines")
    data = ("---\ntime: 2026-01-01 00:00:00\ntitle: Index_write\n---\n\n"
            "バナナ: 1,2\nオザーク: 3\n")
    buf = io.StringIO()
    old_stdin = sys.stdin
    sys.stdin = io.StringIO(data)
    try:
        with contextlib.redirect_stdout(buf):
            rc = sort_yomi.main(["sort", "--base", ".", "--keyword-lines", "--dry-run"])
    finally:
        sys.stdin = old_stdin
    check(rc == 0 and buf.getvalue() == (
        "---\ntime: 2026-01-01 00:00:00\ntitle: Index_write\n---\n\n"
        "オザーク: 3\nバナナ: 1,2\n"
    ), "CLI がキーワード行だけをよみ順に（front matter は不変）")


def test_used_and_prune() -> None:
    print("sync 掃除: 使われていない表示名の yomi を落とす")
    notes = {
        Path("/tmp/a.md"): {
            "fm": [
                "---",
                "title: 筋トレ",
                "yomi:",
                '  "筋トレ": "きんとれ"',
                '  "消えた名前": "けえた"',
                "---",
            ],
            "title": "筋トレ",
            "body": [],
            "parent": [],
            "back": [],
        },
        Path("/tmp/b.md"): {
            "fm": ["---", "title: 日記", "yomi:",
                   '  "日記": "にっき"',
                   '  "使われない": "つかわれない"', "---"],
            "title": "日記",
            "body": ["[筋トレ](a.md)"],
            "parent": ["[Index](index.md)"],
            "back": [],
        },
    }
    incoming = {Path("/tmp/a.md"): [Path("/tmp/b.md")], Path("/tmp/b.md"): []}
    used = nf._used_display_names(notes, incoming)
    check({"筋トレ", "Index"} <= used, "使用中の表示名と title を収集")
    check("日記" not in used, "リンクの無いノートの title は未使用")
    changed = nf._prune_yomi_maps(notes, used)
    check(changed == 2, "2 ノートを掃除")
    check(jy.parse_yomi_map(notes[Path("/tmp/a.md")]["fm"]) == {"筋トレ": "きんとれ"}, "使用中は残る")
    check(jy.parse_yomi_map(notes[Path("/tmp/b.md")]["fm"]) == {}, "未使用は消える（title も）")


def test_used_display_names_ignores_backlinks() -> None:
    print("sync 掃除: 自動生成の BackLink 表示名は使用中に数えない")
    notes = {
        Path("/tmp/y.md"): {
            "fm": ["---", "title: 自分でA", "yomi:",
                   '  "自分でA": "じぶんでえ"', "---"],
            "title": "自分でA", "body": [], "parent": [], "related": [], "back": [],
        },
        Path("/tmp/x.md"): {
            "fm": ["---", "title: X", "---"],
            "title": "X", "body": ["[別名](y.md)"], "parent": [], "related": [],
            "back": ["[自分でA](y.md)"],
        },
    }
    incoming = {Path("/tmp/y.md"): [Path("/tmp/x.md")], Path("/tmp/x.md"): []}
    used = nf._used_display_names(notes, incoming)
    check("別名" in used, "本文リンクの表示名は使用中")
    check("自分でA" not in used, "BackLink の表示名だけでは使用中にしない")
    check(nf._prune_yomi_maps(notes, used) == 1, "y.md の yomi を掃除")
    check(jy.parse_yomi_map(notes[Path("/tmp/y.md")]["fm"]) == {}, "存在しないよみが残らない")


def test_persist_readings() -> None:
    print("persist_readings: \\S のとき未登録のよみを yomi: に書く")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        (root / "a.md").write_text("---\ntitle: 日記\n---\n", encoding="utf-8")
        (root / "b.md").write_text("---\ntitle: AI\n---\n", encoding="utf-8")
        lines = ["[日記](a.md)", "[AI](b.md)", "[無い](none.md)"]
        check(jy.persist_readings(lines, d) == 1, "かなに変わる表示名だけ追加")
        check(jy.get_yomi(root / "a.md", "日記") == "にっき", "a.md に登録")
        check(jy.get_yomi(root / "b.md", "AI") == "", "ローマ字のままは書かない")
        check(jy.persist_readings(lines, d) == 0, "2 回目は追加なし")
        jy.set_yomi(root / "a.md", "日記", "ひびき")
        check(jy.persist_readings(["[日記](a.md)"], d) == 0, "既存の手動よみは上書きしない")
        check(jy.get_yomi(root / "a.md", "日記") == "ひびき", "手動よみが残る")


def test_persist_readings_skips_sections() -> None:
    print("persist_readings: Parent 以降と文章内リンクは書き込まない")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        (root / "a.md").write_text("---\ntitle: 日記\n---\n", encoding="utf-8")
        (root / "b.md").write_text("---\ntitle: 解剖学\n---\n", encoding="utf-8")
        lines = ["文章 [日記](a.md) の話", "### Parent", "[解剖学](b.md)"]
        check(jy.persist_readings(lines, d) == 0, "対象外は 0 件")
        check(jy.get_yomi(root / "a.md", "日記") == "", "文章内は未登録のまま")
        check(jy.get_yomi(root / "b.md", "解剖学") == "", "Parent は未登録のまま")


def test_cli() -> None:
    print("sort_yomi CLI: set / get / sort")
    with tempfile.TemporaryDirectory() as d:
        note = Path(d) / "x.md"
        note.write_text("---\ntitle: 筋トレ\n---\n", encoding="utf-8")
        rc = sort_yomi.main(["set", "--note", str(note), "--name", "筋トレ", "--reading", "きんとれ"])
        check(rc == 0, "set が成功")
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            sort_yomi.main(["get", "--note", str(note), "--name", "筋トレ"])
        check(buf.getvalue().strip() == "きんとれ", "get が登録値を返す")
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            sort_yomi.main(["list", "--note", str(note)])
        check(buf.getvalue().split() == ["筋トレ"], "list が登録順に表示名を返す")
        data = "[日記](a.md)\n[解剖学](b.md)\n"
        report = Path(d) / "report.txt"
        buf = io.StringIO()
        old_stdin = sys.stdin
        sys.stdin = io.StringIO(data)
        try:
            with contextlib.redirect_stdout(buf):
                rc = sort_yomi.main(
                    ["sort", "--base", str(d), "--report-file", str(report)]
                )
        finally:
            sys.stdin = old_stdin
        check(rc == 0 and buf.getvalue() == "[解剖学](b.md)\n[日記](a.md)\n", "sort がよみ順")
        check(report.read_text(encoding="utf-8").strip() == "0", "report-file に追加件数 0")


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
