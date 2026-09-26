#!/usr/bin/env python3
"""note_format_v2 の自己完結テスト（pytest 非依存）。

    python3 test_note_format_v2.py
"""
from __future__ import annotations

import re
import sys
import tempfile
from pathlib import Path

import note_format_v2 as v2

_FAILED: list[str] = []


def check(cond: bool, msg: str) -> None:
    if cond:
        print(f"  ok   {msg}")
    else:
        print(f"  FAIL {msg}")
        _FAILED.append(msg)


UP_MARK = v2.UP_MARK
DOWN_MARK = v2.DOWN_MARK


def regions(text: str) -> tuple[str, str]:
    """(上側リージョン, 下側リージョン) を返す。見張りコメント行で区切る。"""
    lines = text.split("\n")
    sl = [l.strip() for l in lines]
    if UP_MARK not in sl or DOWN_MARK not in sl:
        return "", ""
    u, d = sl.index(UP_MARK), sl.index(DOWN_MARK)
    return "\n".join(lines[u + 1:d]), "\n".join(lines[d + 1:])


def note(path: Path, title: str, up: str = "", down: str = "") -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    txt = f"---\ntime: 2026-01-01 00:00:00\ntitle: {title}\n---\n\n# {title}\n\n本文。\n\n{UP_MARK}\n"
    if up:
        txt += up.strip("\n") + "\n"
    txt += DOWN_MARK + "\n"
    if down:
        txt += down.strip("\n") + "\n"
    path.write_text(txt, encoding="utf-8")


def retitle(path: Path, new_title: str) -> None:
    """front matter の title だけ書き換える（sync 済みの関係セクションは触らない）。"""
    txt = path.read_text(encoding="utf-8")
    txt = re.sub(r"^title:.*$", f"title: {new_title}", txt, count=1, flags=re.M)
    path.write_text(txt, encoding="utf-8")


# ---------------------------------------------------------------------------

def test_parse_inline_and_block_roundtrip() -> None:
    print("parse: インライン / ブロックの往復")
    src = (
        "---\ntime: 2026-01-01 00:00:00\ntitle: A\n---\n\n# A\n\n"
        "散文。ここに ワード: と書いても本文。ここに --- も書ける。\n\n"
        "<!-- こっちにとって -->\n"
        "所属: [瞑想](20250101.md)\n"
        "論点:\n[問い](20250111.md) — メモ\n[別の問い](20250112.md)\n"
        "<!-- そっちにとって -->\n"
        "関連: [呼吸法](20250107.md)\n"
    )
    n = v2.parse_note(Path("/x/A.md"), src)
    check(n.title == "A", "title を front matter から取得")
    check("ワード:" in "\n".join(n.body), "本文の『ワード:』は本文のまま（型にしない）")
    check(n.up["所属"] == [("瞑想", "20250101.md", None)], "インライン 1 本")
    check(len(n.up["論点"]) == 2, "ブロック 2 本")
    check(n.up["論点"][0][2] == "メモ", "注釈を保持")
    check(n.down["関連"] == [("呼吸法", "20250107.md", None)], "下側インライン")
    out = v2.render_note(n)
    check("所属:\n[瞑想](20250101.md)" in out, "1 本もブロックで出力")
    check("論点:\n[問い](20250111.md) — メモ" in out, "2 本はブロックで出力")
    check(UP_MARK in out and DOWN_MARK in out, "見張りコメントが両方ある")
    check(out.count("\n---\n") == 1, "--- は front matter の 1 箇所だけ（本文の --- は保持）")


def test_normalize_counts() -> None:
    print("normalize: 本数に応じた整形")
    src = (
        "---\ntitle: A\n---\n\n# A\n\n"
        "<!-- こっちにとって -->\n"
        "論点: [x](20250101.md)\n[y](20250102.md)\n"  # インライン記法だが 2 本
        "前提:\n[z](20250103.md)\n"                     # ブロック記法だが 1 本
        "<!-- そっちにとって -->\n"
    )
    n = v2.parse_note(Path("/x/A.md"), src)
    out = v2.render_note(n)
    check("論点:\n[x](20250101.md)\n[y](20250102.md)" in out, "2 本 → ブロックへ")
    check("前提:\n[z](20250103.md)" in out, "1 本もブロックのまま")


def test_sync_generates_down() -> None:
    print("sync: 上側 → 相方の下側 生成（`:` 終端の新規ペアは括弧付きで自動ミラー）")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        note(root / "20250104.md", "集中と気づき", up="論点: [問い](20250111.md)")
        note(root / "20250111.md", "瞑想のコツがわからない")
        v2.sync_vault(root)
        _u, dn = regions((root / "20250111.md").read_text(encoding="utf-8"))
        check("(論点):\n[集中と気づき](20250104.md)" in dn,
              "B の下側は新規ペアだが、A が `:` で書いたので括弧付きで自動ミラーされる")


def test_sync_symmetric_down_edit() -> None:
    print("sync: 下側の手編集（有向）→ 相方の上側へ反映（`:` 終端は括弧付きで自動ミラー）")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        note(root / "20250104.md", "A")
        note(root / "20250120.md", "C", down="論点: [A](20250104.md)")
        v2.sync_vault(root)
        up, _dn = regions((root / "20250104.md").read_text(encoding="utf-8"))
        check("(論点):\n[C](20250120.md)" in up,
              "A の上側は新規ペアだが、C が `:` で書いたので括弧付きで自動ミラーされる")


def test_semicolon_suppresses_auto_mirror() -> None:
    print("sync: `;` 終端で書くと、相手側は自動ミラーされず既定の『ノート』のまま")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        note(root / "20250104.md", "集中と気づき", up="論点; [問い](20250111.md)")
        note(root / "20250111.md", "瞑想のコツがわからない")
        v2.sync_vault(root)
        up, dn2 = regions((root / "20250104.md").read_text(encoding="utf-8"))
        _u, dn = regions((root / "20250111.md").read_text(encoding="utf-8"))
        check("論点;\n[問い](20250111.md)" in up, "書いた側はそのまま `論点;`")
        check("[集中と気づき](20250104.md)" in dn and "ノート:" not in dn,
              "`;` なので相手側は既定の裸リンク（ノート: ラベル無し）のまま")


def test_semicolon_clears_previous_mirrored_label() -> None:
    print("sync: 相手側に既に自動ミラー行があっても、`;` に変えたら既定の『ノート』へ戻す")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        note(root / "20250104.md", "A", up="きっかけ: [B](20250111.md)")
        note(root / "20250111.md", "B")
        v2.sync_vault(root)
        b = root / "20250111.md"
        check("(きっかけ):\n[A](20250104.md)" in regions(b.read_text(encoding="utf-8"))[1],
              "まず `:` 終端なので括弧付きで自動ミラーされる")
        # A が `;` 終端に変える = 「このラベルは相手側に見せない」の意。
        note(root / "20250104.md", "A", up="きっかけ; [B](20250111.md)")
        v2.sync_vault(root)
        _u, dn = regions(b.read_text(encoding="utf-8"))
        check("きっかけ" not in dn, "相手側から『きっかけ』が消える")
        check("[A](20250104.md)" in dn and "ノート:" not in dn,
              "`;` なので相手側は既定の裸リンクへ戻る（sticky より優先）")


def test_colon_suffix_variants() -> None:
    print("`:` は相手 (語): / `:;` は相手も 語:; / `;` は書かない / `::` は両方 語:")
    # `:;` … 相手側も `語:;`（括弧なし）
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        note(root / "20250104.md", "A", down="foo:; [B](20250111.md)")
        note(root / "20250111.md", "B")
        v2.sync_vault(root)
        up, _dn = regions((root / "20250111.md").read_text(encoding="utf-8"))
        check("foo:;" in up, "`:;` は相手側も `foo:;`")
    # `::` … 両方の同じセクションに `語:`
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        note(root / "20250104.md", "A", down="bar:: [B](20250111.md)")
        note(root / "20250111.md", "B")
        v2.sync_vault(root)
        _ua, dna = regions((root / "20250104.md").read_text(encoding="utf-8"))
        _ub, dnb = regions((root / "20250111.md").read_text(encoding="utf-8"))
        check("bar:\n[B](20250111.md)" in dna, "A の Child に `bar:`")
        check("bar:\n[A](20250104.md)" in dnb, "B の Child にも `bar:`")
        v2.sync_vault(root)
        check("bar:\n[A](20250104.md)" in regions(
            (root / "20250111.md").read_text(encoding="utf-8"))[1],
            "`::` は 2 回目も安定（idempotent）")


def test_group_label_colon_and_semicolon() -> None:
    print("group: は相手側に (group) でミラー、group; は相手側に書かない")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        note(root / "20250104.md", "A", up="group: [B](20250111.md)")
        note(root / "20250111.md", "B")
        v2.sync_vault(root)
        up, _dn = regions((root / "20250104.md").read_text(encoding="utf-8"))
        _u, dn = regions((root / "20250111.md").read_text(encoding="utf-8"))
        check("group:" in up and "[B](20250111.md)" in up, "書いた側は group: のまま")
        check("(group):" in dn and "[A](20250104.md)" in dn, "相手側は (group): でミラー")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        note(root / "20250104.md", "A", up="group; [B](20250111.md)")
        note(root / "20250111.md", "B")
        v2.sync_vault(root)
        _u, dn = regions((root / "20250111.md").read_text(encoding="utf-8"))
        check("group" not in dn and "[A](20250104.md)" in dn,
              "group; は相手側には書かない（裸リンク）")


def test_bare_link_under_marker_defaults_to_note() -> None:
    print("sync: 見張りの直下にラベル無しで書いたリンクは既定の『ノート』として相方へ反映")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        note(root / "20250104.md", "A")
        (root / "20250111.md").write_text(
            f"---\ntime: 2026-01-01 00:00:00\ntitle: B\n---\n\n# B\n\n本文。\n\n"
            f"{UP_MARK}\n{DOWN_MARK}\n[A](20250104.md)\n",
            encoding="utf-8",
        )
        v2.sync_vault(root)
        up_a, _ = regions((root / "20250104.md").read_text(encoding="utf-8"))
        check("[B](20250111.md)" in up_a,
              "ラベル無しリンクでも A の上側に裸リンク B が入る（親子が反映される）")


def test_kanren_down_edit_mirrors() -> None:
    print("sync: 関連 を下側に手書き → 相方の下側にも入る")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        note(root / "20250104.md", "A")
        note(root / "20250120.md", "C", down="関連: [A](20250104.md)")
        v2.sync_vault(root)
        _u, a_dn = regions((root / "20250104.md").read_text(encoding="utf-8"))
        check("関連:\n[C](20250120.md)" in a_dn, "A の下側に 関連: C")


def test_sync_delete_from_down_removes_up() -> None:
    print("sync: 下側から削除 → 相方の上側からも消える")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        note(root / "20250104.md", "A", up="論点: [B](20250111.md)")
        note(root / "20250111.md", "B")
        v2.sync_vault(root)
        b_path = root / "20250111.md"
        check("(論点):\n[A](20250104.md)" in regions(b_path.read_text(encoding="utf-8"))[1],
              "まず下側に生成（`:` 終端なので括弧付きで自動ミラー）")
        # ユーザが B の下側から論点行を削除
        b_path.write_text(
            "---\ntitle: B\n---\n\n# B\n\n本文。\n\n---\n", encoding="utf-8"
        )
        v2.sync_vault(root)
        up, _dn = regions((root / "20250104.md").read_text(encoding="utf-8"))
        check("20250111.md" not in up, "A の上側から論点リンクが消える")


def test_kanren_is_symmetric() -> None:
    print("sync: 関連 は対称（両方の下側に出る、上側には出ない）")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        note(root / "20250104.md", "A", up="関連: [B](20250111.md)")  # 旧スタイルの上側
        note(root / "20250111.md", "B")
        v2.sync_vault(root)
        a_up, a_dn = regions((root / "20250104.md").read_text(encoding="utf-8"))
        b_up, b_dn = regions((root / "20250111.md").read_text(encoding="utf-8"))
        check("関連:\n[B](20250111.md)" in a_dn, "A の下側に 関連: B")
        check("関連:\n[A](20250104.md)" in b_dn, "B の下側に 関連: A")
        check("関連" not in a_up and "関連" not in b_up, "どちらの上側にも 関連 は無い")


def test_title_refresh() -> None:
    print("sync: 相手のタイトル変更をリンク表示名へ追従（前回タイトルを記録した上で変更）")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        note(root / "20250104.md", "A", up="論点: [ふるいタイトル](20250111.md)")
        note(root / "20250111.md", "ふるいタイトル")
        v2.sync_vault(root)
        a = (root / "20250104.md").read_text(encoding="utf-8")
        check("[ふるいタイトル](20250111.md)" in a,
              "最初は表示名とタイトルが一致（＝手で変えていない）ので追従対象のまま")
        retitle(root / "20250111.md", "新しいタイトル")
        v2.sync_vault(root)
        a = (root / "20250104.md").read_text(encoding="utf-8")
        check("[新しいタイトル](20250111.md)" in a,
              "前回タイトルと表示名が一致していたので、新タイトルへ追従する")


def test_title_refresh_preserves_first_sync_customization() -> None:
    print("sync: 前回タイトルの記録が無い状態で表示名が違う場合は、手で変えたとみなして残す")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        note(root / "20250104.md", "A", up="論点: [カスタム表示名](20250111.md)")
        note(root / "20250111.md", "実際のタイトル")
        v2.sync_vault(root)
        a = (root / "20250104.md").read_text(encoding="utf-8")
        check("[カスタム表示名](20250111.md)" in a,
              "前回タイトルの記録が無いので、既に違う表示名は手で変えたものとして残す")

    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        note(root / "20250104.md", "A", up="論点: [ふるいタイトル](20250111.md)")
        note(root / "20250111.md", "ふるいタイトル")
        v2.sync_vault(root)
        # 表示名が相手のタイトルと一致した状態を記録した後、手で違う名前に変える
        a_path = root / "20250104.md"
        a_path.write_text(
            a_path.read_text(encoding="utf-8").replace(
                "[ふるいタイトル](20250111.md)", "[自分で付けた名前](20250111.md)"),
            encoding="utf-8")
        retitle(root / "20250111.md", "また変わったタイトル")
        v2.sync_vault(root)
        a = a_path.read_text(encoding="utf-8")
        check("[自分で付けた名前](20250111.md)" in a,
              "手で違う名前に変えた後は、相手のタイトルが変わっても追従しない")


def test_title_refresh_when_display_is_filename_before_first_sync() -> None:
    print("sync: 表示名がファイル名（作成時の初期表示）なら、初回 sync 前に"
          "タイトルを変えても追従する")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        # 作成直後: 表示名もタイトルもファイル名（まだ sync していない）
        note(root / "20250111.md", "20250111")
        note(root / "20250104.md", "A", up="論点: [20250111](20250111.md)")
        # sync 前にタイトルだけ変える（リンク表示名はファイル名のまま）
        retitle(root / "20250111.md", "みかん")
        v2.sync_vault(root)
        a = (root / "20250104.md").read_text(encoding="utf-8")
        check("[みかん](20250111.md)" in a,
              "ファイル名表示は自動扱いで、新しいタイトルへ追従する")


def test_subdir_relative_path() -> None:
    print("sync: サブフォルダ間は相対パス")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        note(root / "20250104.md", "A", up="関連: [B](sub/20250111.md)")
        note(root / "sub" / "20250111.md", "B")
        v2.sync_vault(root)
        b = (root / "sub" / "20250111.md").read_text(encoding="utf-8")
        check("[A](../20250104.md)" in b, "B から見て ../ 付きで生成")


def test_new_skeleton() -> None:
    print("new: 骨組み生成")
    with tempfile.TemporaryDirectory() as d:
        p = Path(d) / "20260909120000.md"
        v2.make_new(p, "テスト")
        txt = p.read_text(encoding="utf-8")
        check(txt.startswith("---\ntime: "), "front matter で始まる")
        check("# テスト" in txt, "H1 を含む")
        check(txt.rstrip().endswith(UP_MARK + "\n" + DOWN_MARK), "末尾に見張りコメント 2 行")



def test_migrate_legacy_v1_note() -> None:
    print("migrate: 旧 v1 (Parent/Child/BackLink) を v2 へ寄せる")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        (root / "260909061513.md").write_text(
            "---\ntitle: parent-note\n---\n\n# parent-note\n\n<!-- こっちにとって -->\n<!-- そっちにとって -->\n", encoding="utf-8")
        legacy = (
            "---\ntime: 2026-09-09 06:15:21\ntitle: 260909061521\n---\n\n"
            "# 260909061521\n\n\n\nParent:\n[260909061513](260909061513.md)\n"
            "Child:\nBackLink:\n[Index](index.md)\n"
        )
        p = root / "260909061521.md"
        p.write_text(legacy, encoding="utf-8")
        v2.sync_vault(root)
        check(p.read_text(encoding="utf-8") == legacy, "sync 単体では旧 v1 を触らない")
        p.write_text(v2.migrate_note(legacy, str(p)), encoding="utf-8")
        v2.sync_vault(root)
        txt = p.read_text(encoding="utf-8")
        up, dn = regions(txt)
        check("Parent:" not in txt and "Child:" not in txt and "BackLink:" not in txt,
              "旧見出しが消える")
        check("関連:\n[parent-note](260909061513.md)" in dn, "Parent リンク -> 関連:（対称なので下側・表示名は現タイトルへ）")
        check("[Index](index.md)" in up and "グループ:" not in up,
              "[Index] -> グループ（見出しなしの裸リンク）")
        check(UP_MARK in txt and DOWN_MARK in txt, "見張りコメント形式に変換される")



def test_kenkai_and_custom_type() -> None:
    print("type: 見解 と自由入力の型")
    src = ("---\ntitle: A\n---\n\n# A\n\n本文。\n\n<!-- こっちにとって -->\n"
           "見解: [x](20250101.md)\n補足: [y](20250102.md)\n<!-- そっちにとって -->\n")
    n = v2.parse_note(Path("/x/A.md"), src)
    check(n.up.get("見解") == [("x", "20250101.md", None)], "見解: を型として認識")
    check(n.up.get("補足") == [("y", "20250102.md", None)], "自由な語:( 補足 ) も型として保持")
    out = v2.render_note(n)
    check("見解:\n[x](20250101.md)" in out and "補足:\n[y](20250102.md)" in out, "両方 round-trip")


def test_body_link_becomes_backlink() -> None:
    print("backlink: 本文中のリンク -> 相手の バックリンク:")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        (root / "20250104.md").write_text(
            "---\ntitle: A\n---\n\n# A\n\n詳しくは [B の話](20250111.md) を参照。\n\n<!-- こっちにとって -->\n<!-- そっちにとって -->\n",
            encoding="utf-8")
        note(root / "20250111.md", "B")
        v2.sync_vault(root)
        up, dn = regions((root / "20250111.md").read_text(encoding="utf-8"))
        check("バックリンク:\n[A](20250104.md)" in dn, "B の下側に バックリンク: A")
        check("関連:" not in dn and "論点:" not in dn, "型セクションには入らない")


def test_typed_link_suppresses_backlink() -> None:
    print("backlink: 型付きの関係があれば バックリンク: にしない")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        (root / "20250104.md").write_text(
            "---\ntitle: A\n---\n\n# A\n\n本文で [B](20250111.md) に触れる。\n\n<!-- こっちにとって -->\n"
            "論点: [B](20250111.md)\n<!-- そっちにとって -->\n", encoding="utf-8")
        note(root / "20250111.md", "B")
        v2.sync_vault(root)
        _up, dn = regions((root / "20250111.md").read_text(encoding="utf-8"))
        check("(論点):\n[A](20250104.md)" in dn, "(論点): A は出る（`:` 終端なので括弧付きで自動ミラー）")
        check("バックリンク" not in dn, "バックリンク: A は出さない（型で表示済み）")


def test_typed_link_from_down_side_suppresses_backlink() -> None:
    print("backlink: 型付きの関係が相手の そっちにとって 側にあっても バックリンク: にしない")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        # A の本文で B に触れつつ、A の そっちにとって（子）側にも同じ B を載せる
        # （nc/ca 相当。関係の向きは B->A で、本文リンクの向き A->B とは逆）。
        (root / "20250104.md").write_text(
            "---\ntitle: A\n---\n\n# A\n\n本文で [B](20250111.md) に触れる。\n\n"
            "<!-- こっちにとって -->\n<!-- そっちにとって -->\nノート: [B](20250111.md)\n",
            encoding="utf-8")
        note(root / "20250111.md", "B")
        v2.sync_vault(root)
        up, dn = regions((root / "20250111.md").read_text(encoding="utf-8"))
        check("[A](20250104.md)" in up, "B の こっちにとって に裸リンク A は出る")
        check("バックリンク" not in dn, "B の そっちにとって に バックリンク: A は出さない（重複のため）")



def test_foreign_file_untouched() -> None:
    print("integrate: 見張り無しの外部ファイル（日記）は書き換えない")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        diary = root / "diary" / "2024-05-01.md"
        diary.parent.mkdir(parents=True)
        raw = ("# 2024-05-01\n\n今日は晴れ。\n\n---\n\n"
               "考えごと。ワード: これも本文。詳しくは [瞑想メモ](../20250104.md)。\n")
        diary.write_text(raw, encoding="utf-8")
        note(root / "20250104.md", "瞑想メモ")
        v2.sync_vault(root)
        check(diary.read_text(encoding="utf-8") == raw, "日記ファイルはバイト単位で不変")
        _up, dn = regions((root / "20250104.md").read_text(encoding="utf-8"))
        check("バックリンク:\n[2024-05-01](diary/2024-05-01.md)" in dn,
              "日記からの本文リンクは PKM 側に バックリンク として出る")


def test_pkm_raw_optout() -> None:
    print("integrate: front matter の pkm: raw で除外")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        raw = ("---\ntitle: 生ログ\npkm: raw\n---\n\n# 生ログ\n\n"
               "<!-- こっちにとって -->\n所属: [x](20250104.md)\n<!-- そっちにとって -->\n")
        p = root / "20250101.md"
        p.write_text(raw, encoding="utf-8")
        note(root / "20250104.md", "X")
        v2.sync_vault(root)
        check(p.read_text(encoding="utf-8") == raw, "見張りがあっても pkm: raw なら不変")



def test_unmarked_notes_frozen_by_sync() -> None:
    print("integrate: 見張り無し（v1 形式含む）は sync では絶対に触らない")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        old = root / "diary" / "20200101120000.md"
        old.parent.mkdir(parents=True)
        v1raw = ("# 2020-01-01\n\n昔のメモ。\n\nParent:\n[何か](20200102120000.md)\n"
                 "Child:\nBackLink:\n[Index](index.md)\n")
        old.write_text(v1raw, encoding="utf-8")
        note(root / "20250104.md", "現ノート", up="論点: [昔のメモ](diary/20200101120000.md)")
        v2.sync_vault(root)
        check(old.read_text(encoding="utf-8") == v1raw, "v1 形式ノートは sync で 1 バイト不変")
        up, _dn = regions((root / "20250104.md").read_text(encoding="utf-8"))
        check("論点:\n[昔のメモ](diary/20200101120000.md)" in up, "リンクは打った通りに残る（表示名も固定）")
        # migrate を明示的に呼ぶと変換される
        conv = v2.migrate_note(v1raw, str(old))
        check(conv is not None and UP_MARK in conv, "migrate は v2 化する")


def test_legacy_marks_upgraded_by_sync() -> None:
    print("integrate: 旧見張り（している/されている）は sync で新表記へ書き換わる")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        legacy = (
            "---\ntime: 2026-01-01 00:00:00\ntitle: A\n---\n\n# A\n\n本文。\n\n"
            f"{v2.LEGACY_UP_MARK}\n論点: [B](20250111.md)\n{v2.LEGACY_DOWN_MARK}\n"
        )
        p = root / "20250104.md"
        p.write_text(legacy, encoding="utf-8")
        note(root / "20250111.md", "B")
        v2.sync_vault(root)
        txt = p.read_text(encoding="utf-8")
        check(v2.LEGACY_UP_MARK not in txt and v2.LEGACY_DOWN_MARK not in txt,
              "旧見張りは残らない")
        check(UP_MARK in txt and DOWN_MARK in txt, "新見張りに書き換わる")
        check("論点:\n[B](20250111.md)" in txt, "関係の中身は保持される")


def _note_with_attr(path: Path, title: str, attr: str, up: str = "", down: str = "") -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    txt = (
        f"---\ntime: 2026-01-01 00:00:00\ntitle: {title}\nattribute: {attr}\n---\n\n"
        f"# {title}\n\n本文。\n\n{UP_MARK}\n"
    )
    if up:
        txt += up.strip("\n") + "\n"
    txt += DOWN_MARK + "\n"
    if down:
        txt += down.strip("\n") + "\n"
    path.write_text(txt, encoding="utf-8")


def test_attribute_group_labels_member_up_side() -> None:
    print("attribute: グループ は非対称：メンバー側の上側だけ常に グループ: になる")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        _note_with_attr(root / "20250101.md", "哲学", v2.CATEGORY_ATTR)
        note(root / "20250104.md", "認識論とは何か", up="論点: [哲学](20250101.md)")
        v2.sync_vault(root)
        up, _dn = regions((root / "20250104.md").read_text(encoding="utf-8"))
        _u, dn = regions((root / "20250101.md").read_text(encoding="utf-8"))
        check("[哲学](20250101.md)" in up and "グループ:" not in up,
              "手で 論点 を選んでいても、相手が グループ なら上側は裸リンク（グループ扱い）")
        check("論点:\n[認識論とは何か](20250104.md)" in dn,
              "容器ノート自身の下側は非対称：メンバーが打った実際の関係名がそのまま並ぶ（§3 の例外）")


def test_attribute_group_subgroup_labels_down_side_too() -> None:
    print("自分（サブ容器）も attribute: グループ なら、相手の下側も グループ: になる")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        _note_with_attr(root / "20250101.md", "哲学", v2.CATEGORY_ATTR)
        _note_with_attr(root / "20250104.md", "認識論", v2.CATEGORY_ATTR,
                         up="ノート: [哲学](20250101.md)")
        v2.sync_vault(root)
        _u, dn = regions((root / "20250101.md").read_text(encoding="utf-8"))
        check("[認識論](20250104.md)" in dn and "グループ:" not in dn,
              "自分もグループノードなので、相手の下側も裸リンク（グループ扱い）になる")


def test_attribute_subgroup_target_forces_group_not_subgroup() -> None:
    print("旧 attribute: 小グループ も グループ 扱い：自分の上側は グループ: になる")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        _note_with_attr(root / "20250101.md", "実在論", "小グループ")
        note(root / "20250104.md", "普遍は実在するか", up="資料: [実在論](20250101.md)")
        v2.sync_vault(root)
        up, _dn = regions((root / "20250104.md").read_text(encoding="utf-8"))
        _u, dn = regions((root / "20250101.md").read_text(encoding="utf-8"))
        check("[実在論](20250101.md)" in up and "グループ:" not in up,
              "手で 資料 を選んでいても、相手が グループ（旧 小グループ）なら上側は裸リンク")
        check("資料:\n[普遍は実在するか](20250104.md)" in dn,
              "容器ノート自身の下側は打った実際の関係名（資料:）がそのまま並ぶ（§3 の例外）")


def test_attribute_subgroup_alias_forces_target_down_side_like_group() -> None:
    print("旧 attribute: 小グループ も グループ として扱う（相手の下側も グループ: になる）")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        note(root / "20250101.md", "実在論")
        _note_with_attr(root / "20250104.md", "唯名論", "小グループ",
                         up="論点: [実在論](20250101.md)")
        v2.sync_vault(root)
        _u, dn = regions((root / "20250101.md").read_text(encoding="utf-8"))
        check("[唯名論](20250104.md)" in dn and "グループ:" not in dn,
              "小グループ はグループに統合されたので、相手（実在論）の下側も裸リンク（グループ扱い）になる")
        check("論点:\n[唯名論](20250104.md)" not in dn,
              "打った関係名（論点:）は容器の下側では上書きされる")


def test_attribute_subgroup_child_view_differs_by_side() -> None:
    print("グループ（旧 小グループ）ノードの子：容器側の下側は打った関係名、子自身の上側は グループ:")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        _note_with_attr(root / "20250101.md", "実在論", "小グループ")
        note(root / "20250104.md", "普遍は実在するか", up="資料: [実在論](20250101.md)")
        v2.sync_vault(root)
        up, _dn = regions((root / "20250104.md").read_text(encoding="utf-8"))
        _u, dn = regions((root / "20250101.md").read_text(encoding="utf-8"))
        check("資料:\n[普遍は実在するか](20250104.md)" in dn,
              "実在論（グループ）側の下側からは、打った実際の関係名（資料:）で見える")
        check("[実在論](20250101.md)" in up and "グループ:" not in up,
              "その子（普遍は実在するか）自身の上側からは裸リンク（グループ扱い）で見える")


def test_legacy_attribute_names_still_recognized() -> None:
    print("旧 attribute: カテゴリー / キーワード は前方互換で認識される（グループ / 小グループ扱い）")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        _note_with_attr(root / "20250101.md", "哲学", "カテゴリー")
        note(root / "20250104.md", "認識論とは何か", up="論点: [哲学](20250101.md)")
        v2.sync_vault(root)
        up, _dn = regions((root / "20250104.md").read_text(encoding="utf-8"))
        check("[哲学](20250101.md)" in up and "グループ:" not in up,
              "front matter が旧名でも、機能としては グループ 属性として扱われる")
        txt = (root / "20250101.md").read_text(encoding="utf-8")
        check("attribute: カテゴリー" in txt,
              "front matter 自体は書き換えない（sync は関係セクションしか触らない）")


def test_down_side_display_name_is_sticky() -> None:
    print("下側（子リスト）の表示名は手で変えたらそのまま残る（相手のタイトルへ戻らない）")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        note(root / "20250104.md", "A", up="論点: [B](20250111.md)")
        note(root / "20250111.md", "B")
        v2.sync_vault(root)
        _u, dn = regions((root / "20250111.md").read_text(encoding="utf-8"))
        check("(論点):\n[A](20250104.md)" in dn,
              "初回は相手の現タイトルで、新規ペアだが `:` 終端なので括弧付きで自動ミラーされる")

        # B の下側の表示名を手で書き換える
        b_path = root / "20250111.md"
        b_text = b_path.read_text(encoding="utf-8")
        b_path.write_text(b_text.replace("[A](20250104.md)", "[カスタム表示名](20250104.md)"),
                           encoding="utf-8")
        v2.sync_vault(root)
        _u2, dn2 = regions(b_path.read_text(encoding="utf-8"))
        check("(論点):\n[カスタム表示名](20250104.md)" in dn2,
              "sync をもう一度走らせても、手で付けた表示名が相手の現タイトルへ戻らない")


def test_new_pair_custom_label_auto_mirrors_parenthesized() -> None:
    print("sync: `:` 終端の新規ペアは、相手側の言葉をそのままはミラーせず括弧付きで自動ミラーする")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        note(root / "20250104.md", "何もしないは苦痛だから", up="きっかけ: [就職について考え始めたきっかけ](20250111.md)")
        note(root / "20250111.md", "就職について考え始めたきっかけ")
        v2.sync_vault(root)
        up, _dn = regions((root / "20250104.md").read_text(encoding="utf-8"))
        _u, dn = regions((root / "20250111.md").read_text(encoding="utf-8"))
        check("きっかけ:\n[就職について考え始めたきっかけ](20250111.md)" in up,
              "書いた側（A の上側）はそのまま『きっかけ:』")
        check("(きっかけ):\n[何もしないは苦痛だから](20250104.md)" in dn,
              "相手側（B の下側）は新規ペアだが、`:` 終端なので括弧付きで自動ミラーされる")


def test_semicolon_on_new_pair_stays_plain_note() -> None:
    print("sync: `;` 終端の新規ペアは自動ミラーせず、既定の『ノート』のまま")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        note(root / "20250104.md", "何もしないは苦痛だから", up="きっかけ; [就職について考え始めたきっかけ](20250111.md)")
        note(root / "20250111.md", "就職について考え始めたきっかけ")
        v2.sync_vault(root)
        up, _dn = regions((root / "20250104.md").read_text(encoding="utf-8"))
        _u, dn = regions((root / "20250111.md").read_text(encoding="utf-8"))
        check("きっかけ;\n[就職について考え始めたきっかけ](20250111.md)" in up,
              "書いた側（A の上側）はそのまま『きっかけ;』")
        check("[何もしないは苦痛だから](20250104.md)" in dn and "ノート:" not in dn,
              "相手側（B の下側）は `;` なので自動ミラーされず、既定の裸リンクのまま")


def test_default_note_label_is_not_parenthesized() -> None:
    print("sync: 既定の『ノート』は括弧を付けない")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        note(root / "20250104.md", "A", up="ノート: [B](20250111.md)")
        note(root / "20250111.md", "B")
        v2.sync_vault(root)
        _u, dn = regions((root / "20250111.md").read_text(encoding="utf-8"))
        check("[A](20250104.md)" in dn and "ノート:" not in dn,
              "既定の『ノート』はラベルを書かず裸リンクで出る")
        check("(ノート)" not in dn, "『(ノート)』のように括弧は付かない")


def test_label_is_sticky_once_written() -> None:
    print("sync: ラベルも表示名と同じく一度書かれたら sync が変えない（自動ミラーの括弧付き既定値には戻らない）")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        note(root / "20250104.md", "A", up="きっかけ: [B](20250111.md)")
        note(root / "20250111.md", "B")
        v2.sync_vault(root)
        b_path = root / "20250111.md"
        _u, dn = regions(b_path.read_text(encoding="utf-8"))
        check("(きっかけ):\n[A](20250104.md)" in dn, "初回は `:` 終端の自動ミラーで括弧付き既定値")

        # 手で「後押し」という言葉に書き換える
        b_text = b_path.read_text(encoding="utf-8")
        b_path.write_text(b_text.replace("(きっかけ):", "後押し:"), encoding="utf-8")
        v2.sync_vault(root)
        _u2, dn2 = regions(b_path.read_text(encoding="utf-8"))
        check("後押し:\n[A](20250104.md)" in dn2,
              "手で書き換えた『後押し:』はそのまま残り、(きっかけ) には戻らない")


def test_mirror_label_follows_source_change_and_delete() -> None:
    print("自動ミラー (括弧付き) は相手側のラベル変更・削除・リンク削除に追従する")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        a = root / "20250104.md"
        b = root / "20250111.md"
        note(a, "A", up="aa: [B](20250111.md)")
        note(b, "B")
        v2.sync_vault(root)
        _u, dn = regions(b.read_text(encoding="utf-8"))
        check("(aa):\n[A](20250104.md)" in dn, "初回 (aa): が自動ミラー")

        note(a, "A", up="[B](20250111.md)")  # ラベルを消す
        v2.sync_vault(root)
        _u, dn = regions(b.read_text(encoding="utf-8"))
        check("(aa)" not in dn and "[A](20250104.md)" in dn, "削除すると裸リンクに戻る")

        note(a, "A", up="bb: [B](20250111.md)")  # 別のラベルに変更
        v2.sync_vault(root)
        _u, dn = regions(b.read_text(encoding="utf-8"))
        check("(bb):\n[A](20250104.md)" in dn and "(aa)" not in dn,
              "変更すると (bb): に追従")

        # 手で別の言葉に書き換えたら sticky（もう自動追従しない）
        b.write_text(b.read_text(encoding="utf-8").replace("(bb):", "手書き:"), encoding="utf-8")
        v2.sync_vault(root)
        _u, dn = regions(b.read_text(encoding="utf-8"))
        check("手書き:\n[A](20250104.md)" in dn, "手書きラベルは sticky のまま")

        note(a, "A")  # リンク自体を削除
        v2.sync_vault(root)
        _u, dn = regions(b.read_text(encoding="utf-8"))
        check("[A](20250104.md)" not in dn, "リンクを消すと相手側からも消える")


def test_hand_written_label_before_first_sync_is_respected() -> None:
    print("sync: 初回 sync 前から両側に別々の言葉が手書きされていても、そのまま尊重する")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        note(root / "20250104.md", "A", up="きっかけ: [B](20250111.md)")
        note(root / "20250111.md", "B", down="後押し: [A](20250104.md)")
        v2.sync_vault(root)
        _u, dn = regions((root / "20250111.md").read_text(encoding="utf-8"))
        check("後押し:\n[A](20250104.md)" in dn,
              "初回 sync 前から手で書いてあった『後押し:』は括弧付き既定値で上書きされない")


def test_down_authored_label_auto_mirrors_to_up_side() -> None:
    print("sync: 相手（そっちにとって）が `:` で書いたラベルは、自分の上側へ括弧付きで自動ミラーされる"
          "（nc/ca のようにダウン側から書くケース）")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        # C の下側（そっちにとって）から「論点: [A]」を書く（nc/ca が下側へ
        # 書き込むのと同じ経路）。A 自身は何も書いていない。
        note(root / "20250104.md", "A")
        note(root / "20250120.md", "C", down="論点: [A](20250104.md)")
        v2.sync_vault(root)
        up, _dn = regions((root / "20250104.md").read_text(encoding="utf-8"))
        check("(論点):\n[C](20250120.md)" in up,
              "A は何も書いていないが、C が `:` で書いたので括弧付きで自動ミラーされる")

        # 手で自分の言葉に書き換える
        a_path = root / "20250104.md"
        a_text = a_path.read_text(encoding="utf-8")
        a_path.write_text(a_text.replace("(論点):", "参照元:"), encoding="utf-8")
        v2.sync_vault(root)
        up2, _dn2 = regions(a_path.read_text(encoding="utf-8"))
        check("参照元:\n[C](20250120.md)" in up2,
              "手で書き換えた『参照元:』はそのまま残り、(論点) には戻らない（上側も sticky）")


def test_semicolon_down_authored_stays_plain_note_on_up_side() -> None:
    print("sync: 相手（そっちにとって）が `;` で書いたラベルは、自分の上側には自動ミラーされない")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        note(root / "20250104.md", "A")
        note(root / "20250120.md", "C", down="論点; [A](20250104.md)")
        v2.sync_vault(root)
        up, _dn = regions((root / "20250104.md").read_text(encoding="utf-8"))
        check("[C](20250120.md)" in up and "ノート:" not in up,
              "C が `;` で書いたので、A の上側は自動ミラーされず既定の裸リンクのまま")


def test_attribute_container_down_authored_keeps_picked_relation_on_own_up_side() -> None:
    print("sync: 容器（グループ）が そっちにとって 側から追加された（ca 相当）場合も、"
          "容器自身の こっちにとって は既定の『ノート』に落とさず、実際に選んだ関係名を保つ")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        _note_with_attr(root / "20250101.md", "G", v2.CATEGORY_ATTR)
        # A の そっちにとって から G へ「索引: [G]」（ca が下側へ書くのと同じ経路）。
        # G 自身は何も書いていない。
        note(root / "20250104.md", "A", down="索引: [G](20250101.md)")
        v2.sync_vault(root)
        up, _dn = regions((root / "20250101.md").read_text(encoding="utf-8"))
        check("索引:\n[A](20250104.md)" in up,
              "G は容器なので既定の『ノート』ではなく、A が実際に選んだ『索引』のまま")


def test_down_side_order_is_sticky() -> None:
    print("sync: 下側（子リスト）の並び順は手で並び替えたらそのまま保つ（sync がソートし直さない）")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        note(root / "20250104.md", "A")
        note(root / "20250101.md", "先に作った方")
        note(root / "20250199.md", "後に作った方")
        # 両方とも A の下側（そっちにとって）に論点として登録。ID順なら
        # 20250101 が先に来るはずだが、ここでは意図的に逆の順で手書きする。
        a_path = root / "20250104.md"
        a_text = a_path.read_text(encoding="utf-8")
        a_text = a_text.replace(
            "Child",
            "Child\n論点:\n[後に作った方](20250199.md)\n[先に作った方](20250101.md)")
        a_path.write_text(a_text, encoding="utf-8")
        v2.sync_vault(root)
        _u, dn = regions(a_path.read_text(encoding="utf-8"))
        idx_first = dn.index("20250199.md")
        idx_second = dn.index("20250101.md")
        check(idx_first < idx_second,
              "ID 順（20250101 が先）ではなく、手で書いた順（20250199 が先）のまま")


def test_down_section_order_is_sticky() -> None:
    print("sync: 下側のセクション順（複数の関係ラベル）も並べ替えたらその順を保つ")
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        note(root / "20250104.md", "A")
        note(root / "20250111.md", "B", up="索引: [A](20250104.md)")
        note(root / "20250120.md", "C", up="ノート: [A](20250104.md)")
        v2.sync_vault(root)
        a_path = root / "20250104.md"
        text1 = a_path.read_text(encoding="utf-8")
        _u, dn = regions(text1)
        check("(索引):" in dn and "[C](20250120.md)" in dn,
              "索引は新規ペアなので (索引): として、既定ノートは裸リンクで反映される")

        # 実際に生成された並びを取得し、手で逆順に並べ替える
        idx_note = dn.index("[C](20250120.md)")
        idx_sk = dn.index("(索引):")
        first_is_note = idx_note < idx_sk
        block_note = "[C](20250120.md)"
        block_sk = "(索引):\n[B](20250111.md)"
        if first_is_note:
            swapped = a_path.read_text(encoding="utf-8").replace(
                block_note + "\n\n" + block_sk, block_sk + "\n\n" + block_note)
        else:
            swapped = a_path.read_text(encoding="utf-8").replace(
                block_sk + "\n\n" + block_note, block_note + "\n\n" + block_sk)
        check(swapped != text1, "テスト前提: 並べ替えの置換が実際に効いた")
        a_path.write_text(swapped, encoding="utf-8")
        v2.sync_vault(root)
        _u2, dn2 = regions(a_path.read_text(encoding="utf-8"))
        idx_note2 = dn2.index("[C](20250120.md)")
        idx_sk2 = dn2.index("(索引):")
        new_first_is_note = idx_note2 < idx_sk2
        check(new_first_is_note != first_is_note,
              "並べ替え後に再syncしても、入れ替えた順のまま強制的に戻されない")


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
