#!/usr/bin/env python3
"""Yurii_PKM ノート形式 v2 の parse / render / sync。

詳細仕様は repo ルートの NOTE_FORMAT.md。要点:

- ファイル名 = タイムスタンプのみ。front matter は time / title。
- 本文の後、``## Parent`` 見張り行から上側（これ＝このノートにとって そのノートが○○）。
- ``## Child`` 見張り行から下側（それ＝そのノートにとって このノートが○○）。
  行全体がそれだけ（コロンも中身も無い）。旧 v1 の ``Parent:``/``Child:``
  （コロン付き・直後にリンク）とは別物。``##`` なしの旧 v2 見張り
  （``Parent``/``Child``）も読める。
- 関係: 索引 / 前提 / 論点 / 見解 / 関連 / ノート（既定）/ 自由入力。
  `グループ` は選ばない ── 相手が `attribute: グループ` / `attribute: 小グループ`
  のどちらでも、選んだ関係に関わらず自分側は自動で `グループ:` になる。
  （旧 `attribute: カテゴリー` / `attribute: キーワード` は前方互換で読める。§ATTR_ALIASES）。
  `関連` は対称。並び順は グループ → 小グループ → 索引 → 前提 → 論点 → 見解 → 関連 → ノート。
  相手が `attribute: グループ` / `attribute: 小グループ` のノートなら、自分側の
  ラベルは値に関わらず常に `グループ:`（相手側の そっちにとって は書かれた関係のまま）。
  自分が `attribute: グループ` なら、相手側の そっちにとって も常に `グループ:`
  （サブ容器として）。自分が `attribute: 小グループ` の場合はこの上書きをしない ──
  相手の そっちにとって には書かれた関係がそのまま出る（小グループは「何に属して
  いるか」を見せるだけで、相手を自分の下位に置く容器ではないため）。
- ノード属性は front matter の `attribute: グループ` / `attribute: 小グループ`
  （容器ノート・サブグループの印）。無ければただのノート。
  論点 / 見解 等は宣言しない（関係とタイトルから分かる）。
- リンク 1 本は ``関係: [t](x.md)`` のインライン、2 本以上は ``関係:`` 改行のブロック。
- 上側が真実。下側は他ノートの上側から導出。上下どちらも編集でき、
  片面の追加 / 削除はもう片面へ反映される（``.pkm_sync_state_v2.json`` で判定）。
  ただしラベルの文言は自動でミラーしない（下記）。
- 本文（散文）中のリンクは、明示の関係が無ければ相手の下側に
  ``バックリンク:`` として現れる。
- 関係ラベルは方向性を持つことが多い（例: ``きっかけ:`` は A 視点の言葉で、
  B からそのままミラーすると意味が通らない）ため、``関連``（対称）と
  ``グループ``（attribute による強制）を除き自動ではミラーしない。
  上側・下側どちらの方向から書いても対称に扱う: 自分の側に既に何か書いて
  あればそれをそのまま使い、無ければ（＝相手側が先にそのペアを書いていた
  場合）``ノート`` はそのまま、それ以外は ``(ラベル):`` と括弧付きの
  既定値になる。一度その位置に行ができたら、以後 sync はラベルを変えない
  （表示名と同じ sticky な扱い。再パースするたびに読み直すだけなので
  自然に sticky になる）。
- リンク表示名は上側・下側とも同じ判定で追従するかどうかが決まる：今書かれて
  いる表示名が前回 sync 時点の相手のタイトルと同じ（＝手で変えていない）なら
  現タイトルへ追従、違っていれば（＝手で変えた）そのまま残す
  （``.pkm_title_state_v2.json`` で前回タイトルを記録）。

sync が書き換えるのは見張りコメント 2 行を持つノートだけ。旧 v1 / 旧 `---` /
日記 / 素の散文は触らない。旧形式の一括変換は `migrate` で明示的に行う。

CLI:
    note_format_v2.py update      ROOT
    note_format_v2.py update_one  FILE ROOT
    note_format_v2.py new         FILE ROOT [TITLE]
    note_format_v2.py migrate     ROOT [FILE]
    note_format_v2.py dupcheck    DIR_A DIR_B
"""
from __future__ import annotations

import datetime as _dt
import json
import os
import re
import sys
from pathlib import Path

RELATIONS: tuple[str, ...] = (
    "group", "索引", "前提", "論点", "見解", "ノート", "関連", "補足", "資料",
)
# 関係名の読み替え
RELATION_ALIASES: dict[str, str] = {
    "ワード": "キーワード",
    "グループ": "group",
    "小グループ": "group",
}
# ノード属性: `attribute: group`（容器ノートの印）。表記は英語 `group` に統一。
# 旧 グループ / 小グループ / カテゴリー / キーワード はすべて `group` として扱う。
ATTR_KEYS = ("attribute", "属性")
CATEGORY_ATTR = "group"  # attribute の値 / 内部ラベル
ATTR_ALIASES: dict[str, str] = {
    "グループ": CATEGORY_ATTR,
    "カテゴリー": CATEGORY_ATTR,
    "キーワード": CATEGORY_ATTR,
    "小グループ": CATEGORY_ATTR,
}
ATTR_LABELS: frozenset[str] = frozenset({CATEGORY_ATTR})  # attribute として使える値
# 対称関係: 上側には出さず、両ノートの下側に現れる。
SYMMETRIC: frozenset[str] = frozenset({"関連"})
BACKLINK = "バックリンク"

UP_MARK = "## Parent"
DOWN_MARK = "## Child"
# 旧見張り（新しい順）。parse だけが読む。render は新表記（## Parent / ## Child）に統一する。
LEGACY_UP_MARK3 = "Parent"  # `##` なしの旧 v2 見張り
LEGACY_DOWN_MARK3 = "Child"
LEGACY_UP_MARK2 = "<!-- こっちにとって -->"
LEGACY_DOWN_MARK2 = "<!-- そっちにとって -->"
LEGACY_UP_MARK = "<!-- している -->"
LEGACY_DOWN_MARK = "<!-- されている -->"

DIVIDER_RE = re.compile(r"^-{3,}\s*$")
# 任意の `語:` / `語;` 見出し（先頭が空白 / # / : / ; でない）。
# 散文除けは _looks_like_header で行う。`;` は「相手には自動で書かない」の意
# （§4）。ラベルは内部的には `;` を含んだ文字列として保持する（例: `きっかけ;`）。
HEADER_RE = re.compile(r"^([^\s:;#][^:;]*?)\s*([:;])\s*(.*)$")
# [表示]() 形式のリンク行（末尾に「 — 注釈」を許す）
LINK_LINE_RE = re.compile(r"^\s*\[([^\]]*)\]\(([^)]+)\)\s*(?:—\s*(.*\S))?\s*$")
# 本文どこにでも現れるリンク（バックリンク判定用）
ANY_LINK_RE = re.compile(r"\[[^\]]*\]\(([^)]+)\)")
# 旧 v1 の構造見出し
LEGACY_HDR_RE = re.compile(r"^(Parent|Child|Branch|BackLink|Back)\s*:\s*(.*)$", re.I)

_EXTRA = "_extra"
_RESERVED = {_EXTRA, BACKLINK}


class Note:
    __slots__ = (
        "path", "fm", "title", "body", "up", "down", "managed",
        "down_raw", "down_rendered",
    )

    def __init__(self, path, fm, title, body, up, down, managed=True,
                 down_raw=None):
        self.path: Path = Path(path)
        self.fm: list[str] = fm
        self.title: str = title
        self.body: list[str] = body
        # managed=False: PKM 形式でない外部ファイル（日記など）。sync は書き換えない。
        self.managed: bool = managed
        self.up: dict[str, list[tuple[str, str, str | None]]] = up
        self.down: dict[str, list[tuple[str, str, str | None]]] = down
        # 下側（Child）の生の行。位置を保存したまま再描画するために保持する。
        self.down_raw: list[str] | None = down_raw
        # sync が位置保存で組み立てた下側の確定行（None なら通常描画）。
        self.down_rendered: list[str] | None = None


# ---------------------------------------------------------------------------
# parse
# ---------------------------------------------------------------------------

def _split_front_matter(lines: list[str]) -> tuple[list[str], list[str]]:
    if lines and lines[0].strip() == "---":
        for i in range(1, len(lines)):
            if lines[i].strip() == "---":
                return lines[: i + 1], lines[i + 1:]
    return [], list(lines)


def _fm_title(fm: list[str]) -> str:
    for ln in fm:
        m = re.match(r"^\s*title\s*:\s*(.+?)\s*$", ln)
        if m:
            return m.group(1)
    return ""


def _fm_attr(fm: list[str]) -> str:
    keys = "|".join(ATTR_KEYS)
    for ln in fm:
        m = re.match(rf"^\s*(?:{keys})\s*:\s*(.+?)\s*$", ln)
        if m:
            v = m.group(1).strip().strip("\"'")
            return ATTR_ALIASES.get(v, v)
    return ""


def _looks_like_header(m: re.Match, lines: list[str], idx: int) -> bool:
    inline = m.group(3).strip()
    # `語:: …` / `語:; …` は、余分な `:` / `;` 1 文字を落としてから見る。
    if inline.startswith(":") or inline.startswith(";"):
        inline = inline[1:].lstrip()
    if inline:
        return bool(LINK_LINE_RE.match(inline))
    for j in range(idx + 1, min(idx + 4, len(lines))):
        s = lines[j].strip()
        if s == "":
            continue
        return bool(LINK_LINE_RE.match(s))
    return False


def _header_label(m: re.Match) -> str:
    """HEADER_RE のマッチから内部ラベル文字列を作る。`;` 終端なら末尾に `;` を
    残す（例: `きっかけ;` -> `きっかけ;`）。エイリアス変換は素の語に対して行う。

    `group` だけは位置（先頭ブロックの裸リンク）でも表せる。明示的に `group:`
    と書いた場合は、裸（位置）の `group` と区別して `group:` を残す ── そう
    しないと `:` の「相手に `(group)` でミラー」が効かなくなるため。
    """
    name = RELATION_ALIASES.get(m.group(1).strip(), m.group(1).strip())
    if m.group(2) == ";":
        return name + ";"
    rest = m.group(3).lstrip()
    if rest.startswith(":"):
        return name + "::"   # `語::` … 両方の同じセクションに `語:`
    if rest.startswith(";"):
        return name + ":;"   # `語:;` … 相手側も `語:;`（括弧なし・終端）
    return name + ":" if name == CATEGORY_ATTR else name


def _parse_sections(lines: list[str], allow_body: bool):
    body: list[str] = []
    sections: dict[str, list] = {}
    cur: str | None = None
    seen_header = False
    i, n = 0, len(lines)
    while i < n:
        ln = lines[i]
        s = ln.strip()
        m = HEADER_RE.match(s)
        if m and _looks_like_header(m, lines, i):
            cur = _header_label(m)
            seen_header = True
            sections.setdefault(cur, [])
            inline = m.group(3).strip()
            if inline.startswith(":") or inline.startswith(";"):
                inline = inline[1:].lstrip()  # `語:: …` / `語:; …` の余分な 1 文字
            lm = LINK_LINE_RE.match(inline)
            if lm:
                sections[cur].append((lm.group(1), lm.group(2), lm.group(3) or None))
            i += 1
            continue
        lm = LINK_LINE_RE.match(s)
        if lm and cur is None and not allow_body:
            # 見張りの直下にラベル無しで書かれたリンクは、既定の `ノート:`
            # （特別な役割の無い関係）とみなす。手でリンクだけ書いた子/親も
            # 相方へちゃんと反映されるようにするため（旧 v1 的な書き方の救済）。
            cur = "ノート"
            sections.setdefault(cur, [])
            sections[cur].append((lm.group(1), lm.group(2), lm.group(3) or None))
            i += 1
            continue
        if lm and cur is not None:
            sections[cur].append((lm.group(1), lm.group(2), lm.group(3) or None))
            i += 1
            continue
        cur = None
        if s == "":
            if allow_body and not seen_header:
                body.append(ln)
        elif allow_body and not seen_header:
            body.append(ln)
        else:
            sections.setdefault(_EXTRA, []).append(ln)
        i += 1
    while body and body[-1].strip() == "":
        body.pop()
    return body, sections


def _has_relation_header(lines: list[str]) -> bool:
    for j, l in enumerate(lines):
        m = HEADER_RE.match(l.strip())
        if m and _looks_like_header(m, lines, j):
            return True
    return False


def _route_legacy_link(up: dict, ti: str, tg: str, ann: str | None) -> None:
    base = tg.split("#", 1)[0].rsplit("/", 1)[-1].lower()
    kind = CATEGORY_ATTR if base in ("index.md", "index") else "関連"  # v1 の Index -> グループ
    up.setdefault(kind, [])
    if all(e[1] != tg for e in up[kind]):
        up[kind].append((ti, tg, ann))


def _migrate_legacy(lines: list[str]):
    """旧 v1（Parent:/Child:/BackLink:）を v2 の形へ寄せる。

    Parent/Child/Branch のリンク -> ``関連:``、``[Index](index.md)`` -> ``グループ:``。
    BackLink は捨てる（sync が下側に再生成する）。リンクは失わない。
    """
    body: list[str] = []
    up: dict[str, list] = {}
    down: dict[str, list] = {}
    zone: object = None  # None | "up" | "back" | ("rel", 関係)
    seen = False
    for idx, ln in enumerate(lines):
        s = ln.strip()
        lm = LINK_LINE_RE.match(s)
        if lm and lm.group(2).split("#", 1)[0].rsplit("/", 1)[-1].lower() in ("index.md", "index"):
            _route_legacy_link(up, lm.group(1), lm.group(2), lm.group(3) or None)
            continue
        lg = LEGACY_HDR_RE.match(s)
        if lg:
            seen = True
            name = lg.group(1).lower()
            zone = "back" if name in ("backlink", "back") else "up"
            inln = LINK_LINE_RE.match(lg.group(2).strip())
            if inln and zone == "up":
                _route_legacy_link(up, inln.group(1), inln.group(2), inln.group(3) or None)
            continue
        tm = HEADER_RE.match(s)
        if tm and _looks_like_header(tm, lines, idx):
            seen = True
            _r = _header_label(tm)
            zone = ("rel", _r)
            up.setdefault(zone[1], [])
            inln = LINK_LINE_RE.match(tm.group(3).strip())
            if inln:
                up[zone[1]].append((inln.group(1), inln.group(2), inln.group(3) or None))
            continue
        if lm:
            if zone == "up":
                _route_legacy_link(up, lm.group(1), lm.group(2), lm.group(3) or None)
            elif isinstance(zone, tuple):
                up[zone[1]].append((lm.group(1), lm.group(2), lm.group(3) or None))
            continue
        if not seen:
            body.append(ln)
    while body and body[-1].strip() == "":
        body.pop()
    return body, up, down


def parse_note(path, text: str | None = None) -> Note:
    p = Path(path)
    if text is None:
        text = p.read_text(encoding="utf-8")
    raw = text.split("\n")
    fm, rest = _split_front_matter(raw)
    title = _fm_title(fm) or p.stem

    stripped = [ln.strip() for ln in rest]

    # sync が触るのは見張り 2 行を持つファイルだけ。
    # それ以外（旧 v1 / 旧 --- / 日記 / 素の散文）は managed=False で読むだけ。
    # 見張りは新表記（## Parent / ## Child）・旧表記（`##` なしの Parent/Child）・
    # 旧表記（こっちにとって/そっちにとって の HTML コメント）・さらに旧い表記
    # （している/されている）のどれでも読める。
    # render は常に新表記で書き直す（＝次の sync で自動移行）。
    up_mark = UP_MARK if UP_MARK in stripped else (
        LEGACY_UP_MARK3 if LEGACY_UP_MARK3 in stripped else (
            LEGACY_UP_MARK2 if LEGACY_UP_MARK2 in stripped else (
                LEGACY_UP_MARK if LEGACY_UP_MARK in stripped else None)))
    down_mark = DOWN_MARK if DOWN_MARK in stripped else (
        LEGACY_DOWN_MARK3 if LEGACY_DOWN_MARK3 in stripped else (
            LEGACY_DOWN_MARK2 if LEGACY_DOWN_MARK2 in stripped else (
                LEGACY_DOWN_MARK if LEGACY_DOWN_MARK in stripped else None)))
    marked = up_mark is not None and down_mark is not None
    frozen = bool(re.search(
        r"^\s*(pkm\s*:\s*raw|sync\s*:\s*(?:false|off|no))\s*$",
        "\n".join(fm), re.I | re.M))

    if not marked or frozen:
        body = list(rest)
        while body and body[-1].strip() == "":
            body.pop()
        return Note(p, fm, title, body, {}, {}, managed=False)

    u = len(stripped) - 1 - stripped[::-1].index(up_mark)
    d = len(stripped) - 1 - stripped[::-1].index(down_mark)
    if u > d:
        u = stripped.index(up_mark)
    # 本文は 1 行も削らない。見張りの直前に空いている行は「書くための余白」で、
    # テンプレートが意図して置いたもの（カーソルはそこに来る）。
    body = list(rest[:u])
    _, up = _parse_sections(rest[u + 1: d], allow_body=False)
    _, down = _parse_sections(rest[d + 1:], allow_body=False)
    # 下側の生の行を保持（位置を変えずに再描画するため）。
    return Note(p, fm, title, body, up, down, down_raw=list(rest[d + 1:]))


def migrate_note(text: str, path: str = "note.md") -> str | None:
    """旧形式（v1 の Parent:/Child:/BackLink: / 旧 `---` v2）を v2 テキストへ変換。

    既に見張りコメントがある / 旧形式と認識できない場合は None。
    """
    raw = text.split("\n")
    fm, rest = _split_front_matter(raw)
    stripped = [ln.strip() for ln in rest]
    if (UP_MARK in stripped and DOWN_MARK in stripped) or (
            LEGACY_UP_MARK3 in stripped and LEGACY_DOWN_MARK3 in stripped) or (
            LEGACY_UP_MARK2 in stripped and LEGACY_DOWN_MARK2 in stripped) or (
            LEGACY_UP_MARK in stripped and LEGACY_DOWN_MARK in stripped):
        return None
    title = _fm_title(fm) or Path(path).stem
    div_idx = [i for i, s in enumerate(stripped) if DIVIDER_RE.match(s)]

    if len(div_idx) >= 2 and (
        _has_relation_header(rest[div_idx[-2] + 1:])
        or all(x == "" for x in stripped[div_idx[-2] + 1:])
    ):
        body_lines = rest[:div_idx[-2]]
        _, up = _parse_sections(rest[div_idx[-2] + 1: div_idx[-1]], allow_body=False)
        _, down = _parse_sections(rest[div_idx[-1] + 1:], allow_body=False)
    elif len(div_idx) == 1 and (
        _has_relation_header(rest[div_idx[0] + 1:])
        or all(x == "" for x in stripped[div_idx[0] + 1:])
    ):
        body_lines = rest[:div_idx[0]]
        _, up = _parse_sections(rest[div_idx[0] + 1:], allow_body=False)
        down = {}
    elif any(LEGACY_HDR_RE.match(s) for s in stripped):
        body_lines, up, down = _migrate_legacy(rest)
    else:
        return None

    body = list(body_lines)
    while body and body[-1].strip() == "":
        body.pop()
    return render_note(Note(Path(path), fm, title, body, up, down))


def _links_in(lines: list[str]) -> list[str]:
    out: list[str] = []
    for ln in lines:
        for m in ANY_LINK_RE.finditer(ln):
            t = m.group(1).split("#", 1)[0].strip()
            if t.lower().endswith(".md"):
                out.append(t)
    return out


# ---------------------------------------------------------------------------
# render
# ---------------------------------------------------------------------------

def _render_section(t: str, entries: list[tuple[str, str, str | None]]) -> list[str]:
    """既定の `ノート` はラベルを書かず、リンクだけを裸で並べる
    （`ノート:` 見出しは不要、という方針）。それ以外はブロック形で書く。

        ラベル:
        [表示名](target.md)

    1 本でもインラインにしない。増えたときに行の形が変わらず、追記が
    「1 行足すだけ」で済むため。読み込み側はインライン形も受け付ける。
    """
    if not entries:
        return []
    out: list[str] = []
    # 既定の `ノート` と強制ラベルの `グループ` は、位置（ブロック順）で
    # 分かるので見出しを書かない。`グループ;` / `ノート;` のように `;` を
    # 明示した時だけ見出しを残す（自動ミラー抑止の意思表示のため）。
    if t not in ("ノート", CATEGORY_ATTR):
        if t.endswith("::"):
            out.append(t[:-2] + ":")   # `語::` は `語:` として出す（両側）
        elif t.endswith(":;") or t.endswith(";") or t.endswith(":"):
            out.append(t)              # `語:;` / `語;` / `group:` はそのまま
        else:
            out.append(f"{t}:")
    for ti, tg, ann in entries:
        s = f"[{ti}]({tg})"
        out.append(s + f" — {ann}" if ann else s)
    return out


def _join_blocks(blocks: list[list[str]]) -> list[str]:
    """ブロック（連続する行のまとまり）を空行 1 つで区切って繋ぐ。"""
    out: list[str] = []
    for i, blk in enumerate(blocks):
        if not blk:
            continue
        if i > 0:
            out.append("")
        out += blk
    return out


def _render_group(d: dict[str, list], is_down: bool = False) -> list[str]:
    """上側（Parent）は **グループ（`group`）を先頭に固定**するだけ。それ以外
    のブロック（既定の `ノート` や手で書いた `ワード:`）の並びは d の順序
    （＝ユーザーが最後に書いた/並べ替えた順）をそのまま尊重する。下側（Child）
    も d の順序を尊重する（`関連` は対称、`バックリンク` は最後）。どちらも
    ブロックの間は空行 1 つで区切る（既定の `ノート` は見出しが無いので、
    空行が無いと前のブロックのリンクと区別できないため）。
    """
    if is_down:
        blocks = [
            _render_section(t, d[t])
            for t in d if t not in _RESERVED and d.get(t)
        ]
        if d.get(BACKLINK):
            blocks.append(_render_section(BACKLINK, d[BACKLINK]))
        out = _join_blocks(blocks)
        extra = list(d.get(_EXTRA, []))
        if extra:
            if out:
                out.append("")
            out += extra
        return out

    # グループだけ先頭に固定。それ以外は d の順序（ユーザーの並び）のまま。
    labels: list[str] = []
    if d.get(CATEGORY_ATTR):
        labels.append(CATEGORY_ATTR)
    for t in d:
        if t in _RESERVED or t == CATEGORY_ATTR:
            continue
        if d.get(t):
            labels.append(t)
    blocks = [_render_section(t, d[t]) for t in labels]
    out = _join_blocks(blocks)
    extra = list(d.get(_EXTRA, []))
    if extra:
        if out:
            out.append("")
        out += extra
    return out


def _squeeze_blanks(lines: list[str]) -> list[str]:
    res: list[str] = []
    prev_blank = False
    for ln in lines:
        blank = ln.strip() == ""
        if blank and prev_blank:
            continue
        res.append(ln)
        prev_blank = blank
    return res


def _render_down_preserving(note: Note, key_fn) -> list[str] | None:
    """Child（下側）をできるだけ「元のまま」に保って組み立てる。

    空行・見出し・並びをそのまま残し、リンク行は位置を動かさず表示名だけ更新。
    見出しは必要なら同じ位置で書き換える（既定に戻る場合は見出し行を外す）。
    消えた関係の行だけ取り除き、新しい関係の行は末尾に足す。並べ替え・
    まとめ直しは一切しない。位置はユーザーが h/Enter/o/p と手編集で決める。
    """
    raw = note.down_raw
    if raw is None:
        return None

    def key(tg: str):
        k = key_fn(tg)
        return k if k is not None else ("raw", tg)

    desired: dict[object, tuple[str, str, str | None, str]] = {}
    for label, entries in note.down.items():
        if label == _EXTRA:
            continue
        for disp, tg, ann in entries:
            desired.setdefault(key(tg), (disp, tg, ann, label))

    def header_line(label: str) -> str | None:
        if label in ("ノート", CATEGORY_ATTR):
            return None  # 見出しを書かない（位置で表す裸リンク）
        if label.endswith("::"):
            return label[:-2] + ":"   # `語::` は `語:` で出す（両側）
        if label.endswith(":;") or label.endswith(";") or label.endswith(":"):
            return label
        return f"{label}:"

    out: list[str] = []
    used: set = set()
    prev_label: str | None = None  # 直前に出したリンクのラベル

    def emit_link(disp: str, tg: str, ann: str | None, label: str) -> None:
        nonlocal prev_label
        if label != prev_label:
            hl = header_line(label)
            if hl is not None:
                out.append(hl)
            prev_label = label
        t = f"[{disp}]({tg})"
        out.append(t + f" — {ann}" if ann else t)

    for i, ln in enumerate(raw):
        s = ln.strip()
        m = HEADER_RE.match(s)
        lm = None
        if m and _looks_like_header(m, raw, i):
            # 見出し行。インラインのリンクがあればそれを 1 本として扱う。
            rest = m.group(3).lstrip()
            if rest.startswith(":") or rest.startswith(";"):
                rest = rest[1:].lstrip()
            lm = LINK_LINE_RE.match(rest)
            if lm is None:
                continue  # 見出しのみ（リンクは以降の行）。見出しは出し直す
        else:
            lm = LINK_LINE_RE.match(s)
        if lm:
            k = key_fn(lm.group(2))
            if k is not None and k in desired and k not in used:
                used.add(k)
                disp, _tg, ann, label = desired[k]
                ann2 = ann if ann else (lm.group(3) or None)
                emit_link(disp, lm.group(2), ann2, label)
                continue
            if k is not None:
                continue  # 消えた関係 / 重複
            out.append(ln)  # 解決できないリンクはそのまま残す
            prev_label = None
            continue
        # リンク行以外（空行・散文）
        out.append(ln)
        if s != "":
            prev_label = None  # 散文などでブロックが切れる
        for mm in ANY_LINK_RE.finditer(ln):
            kk = key_fn(mm.group(1))
            if kk is not None and kk in desired:
                used.add(kk)

    for k, (disp, tg, ann, label) in desired.items():
        if k in used:
            continue
        used.add(k)
        if label != prev_label and out and out[-1].strip() != "":
            out.append("")
        emit_link(disp, tg, ann, label)
    return out


def render_note(note: Note) -> str:
    """本文はユーザーのもの。空行を含めてそのまま通す。

    整形するのは見張りコメント以降（関係セクション）だけ。本文の空行を
    潰すと、テンプレートが置いた「書くための余白」が毎回消えてしまう。
    """
    out: list[str] = list(note.fm)
    body = list(note.body)
    # front matter の直後は 1 行空ける（本文が既に空行始まりならそれを使う）
    if not body or body[0].strip() != "":
        out.append("")
    out += body

    # 本文 → こっちにとって見張り → 上側 → そっちにとって見張り → 下側
    # 本文が空行で終わっていなければ 1 行だけ空ける（余白があるならそのまま）
    if out and out[-1].strip() != "":
        out.append("")
    out.append(UP_MARK)
    out += _squeeze_blanks(_render_group(note.up))
    out.append(DOWN_MARK)
    if note.down_rendered is not None:
        # sync が位置保存で組み立てた生の下側をそのまま使う（並べ替えない）。
        out += note.down_rendered
    else:
        out += _squeeze_blanks(_render_group(note.down, is_down=True))

    while out and out[-1].strip() == "":
        out.pop()
    return "\n".join(out) + "\n"


# ---------------------------------------------------------------------------
# resolution helpers
# ---------------------------------------------------------------------------

EXPAND_TMP_DIR = "_tmp"  # 展開（pe）の使い捨て出力先。sync は一切関知しない。


def _iter_md(root: Path):
    for p in sorted(root.rglob("*.md")):
        parts = p.relative_to(root).parts
        if any(part.startswith(".") for part in parts) or EXPAND_TMP_DIR in parts:
            continue
        yield p


def _index(root: Path) -> dict[str, list[Path]]:
    by_name: dict[str, list[Path]] = {}
    for p in _iter_md(root):
        rp = p.resolve()
        by_name.setdefault(p.name, []).append(rp)
        by_name.setdefault(p.stem, []).append(rp)
    return by_name


def _resolve(target: str, note_dir: Path, root: Path, by_name: dict[str, list[Path]]) -> Path | None:
    t = target.split("#", 1)[0].strip()
    if not t or "://" in t:
        return None
    cand = note_dir / t
    try:
        cand = cand.resolve()
    except OSError:
        cand = None
    if cand is not None and cand.suffix.lower() == ".md" and cand.exists():
        return cand
    key = Path(t).name
    lst = by_name.get(key) or by_name.get(key[:-3] if key.endswith(".md") else key)
    if lst:
        uniq = set(lst)
        if len(uniq) == 1:
            return next(iter(uniq))
    return None


def _rel(from_dir: Path, target: Path) -> str:
    return os.path.relpath(target, from_dir).replace(os.sep, "/")


# ---------------------------------------------------------------------------
# sync
# ---------------------------------------------------------------------------

_STATE_FILE = ".pkm_sync_state_v2.json"
# 前回 sync 時点での各ノートのタイトル。リンク表示名を「追従させるか、打った
# 通り残すか」の判定に使う（_tracked_disp）。
_TITLE_STATE_FILE = ".pkm_title_state_v2.json"
Rel = tuple[str, str, str]  # (src_id, type, tgt_id)  id = root からの相対 posix パス


def _nid(path: Path, root: Path) -> str | None:
    try:
        return path.resolve().relative_to(root).as_posix()
    except ValueError:
        return None


def _load_state(root: Path) -> set[tuple]:
    """有向関係 = `from\\tto`（2 要素）、対称関係 = `a\\t関連\\tb`（3 要素）。"""
    fp = root / _STATE_FILE
    if not fp.exists():
        return set()
    try:
        data = json.loads(fp.read_text(encoding="utf-8"))
        out: set[tuple] = set()
        for x in data:
            if not isinstance(x, str):
                continue
            parts = x.split("\t")
            if len(parts) in (2, 3):
                out.add(tuple(parts))
        return out
    except Exception:  # noqa: BLE001
        return set()


def _save_state(root: Path, entries: set[tuple]) -> None:
    fp = root / _STATE_FILE
    payload = sorted("\t".join(r) for r in entries)
    fp.write_text(json.dumps(payload, ensure_ascii=False, indent=0), encoding="utf-8")


def _load_title_state(root: Path) -> dict[str, str]:
    fp = root / _TITLE_STATE_FILE
    if not fp.exists():
        return {}
    try:
        data = json.loads(fp.read_text(encoding="utf-8"))
        return {k: v for k, v in data.items() if isinstance(k, str) and isinstance(v, str)}
    except Exception:  # noqa: BLE001
        return {}


def _save_title_state(root: Path, titles: dict[str, str]) -> None:
    fp = root / _TITLE_STATE_FILE
    fp.write_text(json.dumps(titles, ensure_ascii=False, indent=0, sort_keys=True), encoding="utf-8")


def _tracked_disp(target_id: str, written: str | None, now_title: str,
                   prev_titles: dict[str, str]) -> str:
    """表示名の追従判定。今書かれている表示名(written)が自動生成されたもの
    （＝手で変えていない）なら現タイトルへ追従させる。手で変えたものは残す。

    自動生成とみなすのは次のいずれか:
      - 表示名が無い
      - 表示名が前回 sync 時点の相手タイトルと同じ（＝追従してきただけ）
      - 表示名が相手のファイル名（拡張子なし）と同じ（＝作成時の初期表示）
    最後の条件が大事で、初回 sync の前にタイトルを変えても追従できる
    （前回タイトルの記録が無くても、ファイル名表示は手書きと区別できる）。
    """
    if written is None:
        return now_title
    stem = Path(target_id).stem
    if written == now_title or written == prev_titles.get(target_id) or written == stem:
        return now_title
    return written


def sync_vault(root) -> int:
    """vault 全体を 1 パスで整合させる。見張りコメントを持つノートだけを書き換える。"""
    root = Path(root).resolve()
    by_name = _index(root)

    notes: list[Note] = []
    for p in _iter_md(root):
        try:
            notes.append(parse_note(p))
        except Exception as exc:  # noqa: BLE001
            print(f"note_format_v2: skip {p}: {exc}", file=sys.stderr)

    by_path: dict[Path, Note] = {n.path.resolve(): n for n in notes}
    ids: dict[Path, str] = {}
    id_to_path: dict[str, Path] = {}
    for k in by_path:
        i = _nid(k, root)
        if i is not None:
            ids[k] = i
            id_to_path[i] = k

    prev_titles = _load_title_state(root)

    def rid(target: str, base: Path) -> str | None:
        tp = _resolve(target, base, root, by_name)
        return ids.get(tp.resolve()) if tp is not None else None

    # 有向関係の同一性は (from_id, to_id) のペア。ラベルは別管理（表示のみ）。
    up_label: dict[tuple[str, str], str] = {}    # (A,B) <- A の こっちにとって 行 `label: [B]`
    down_label: dict[tuple[str, str], str] = {}  # (A,B) <- B の そっちにとって 行 `label: [A]`
    up_ann: dict[tuple[str, str], str] = {}
    up_unresolved: dict[Path, dict[str, list]] = {k: {} for k in by_path}
    body_links: dict[str, set[str]] = {}
    sym_face: dict[tuple[str, frozenset], set[str]] = {}  # (関係, {id,id}) -> 端点

    # `語::` のベース語を集める。対称なので、reciprocal 側の素の `語:` も
    # 対称として扱わないと 2 回目の sync で消えてしまう。`::` は描画で `語:` に
    # 化けて消えるので、前回の状態（3 つ組＝対称）からも引き継ぐ。
    prev_state = _load_state(root)
    dc_labels: set[str] = {r[1] for r in prev_state if len(r) == 3}
    for _n in by_path.values():
        for _d in (_n.up, _n.down):
            for _t in _d:
                if _t.endswith("::"):
                    dc_labels.add(_t[:-2])

    def _sym_label(t: str) -> str | None:
        if t in SYMMETRIC:
            return t
        if t.endswith("::"):
            return t[:-2]
        if t in dc_labels:
            return t
        return None

    for k, n in by_path.items():
        sid = ids.get(k)
        if sid is None:
            continue
        for t, entries in n.up.items():
            if t == _EXTRA:
                continue
            for ti, tg, ann in entries:
                tid = rid(tg, n.path.parent)
                if tid is None:
                    up_unresolved[k].setdefault(t, []).append((ti, tg, ann))
                    continue
                _sym = _sym_label(t)
                if _sym is not None:
                    if tid != sid:
                        sym_face.setdefault((_sym, frozenset((sid, tid))), set()).add(sid)
                    continue
                up_label[(sid, tid)] = t
                if ann:
                    up_ann[(sid, tid)] = ann
        for t, entries in n.down.items():
            if t in _RESERVED:
                continue
            for _ti, tg, _ann in entries:
                src_id = rid(tg, n.path.parent)
                if src_id is None:
                    continue
                _sym = _sym_label(t)
                if _sym is not None:
                    if src_id != sid:
                        sym_face.setdefault((_sym, frozenset((sid, src_id))), set()).add(sid)
                    continue
                down_label[(src_id, sid)] = t
        bl: set[str] = set()
        for tg in _links_in(n.body):
            tid = rid(tg, n.path.parent)
            if tid is not None and tid != sid:
                bl.add(tid)
        body_links[sid] = bl

    prev = prev_state
    prev_pairs = {(a, b) for r in prev if len(r) == 2 for a, b in [r]}
    prev_pairs |= {(r[0], r[2]) for r in prev if len(r) == 3 and _sym_label(r[1]) is None}
    prev_sym = {r for r in prev if len(r) == 3 and _sym_label(r[1]) is not None}

    # --- 有向関係の解決（ペア単位） ---
    present: set[tuple[str, str]] = set()
    for pair in set(up_label) | set(down_label) | prev_pairs:
        up_face = pair in up_label
        down_face = pair in down_label
        if up_face and down_face:
            present.add(pair)
        elif (up_face != down_face) and pair not in prev_pairs:
            present.add(pair)  # 片面だけ & 前回に無い = 今追加
    present = {p for p in present if p[0] in id_to_path and p[1] in id_to_path}

    # --- 対称関係（関連） ---
    present_sym: set[Rel] = set()
    for (t, pair), faces in sym_face.items():
        a, b = sorted(pair)
        if a not in id_to_path or b not in id_to_path:
            continue
        if len(faces) >= 2 or (len(faces) == 1 and (a, t, b) not in prev_sym):
            present_sym.add((a, t, b))

    directed = set(present)
    directed |= {(a, b) for (a, _t, b) in present_sym}
    directed |= {(b, a) for (a, _t, b) in present_sym}

    attr_of: dict[str, str] = {
        i: a for kk, nn in by_path.items()
        if (i := ids.get(kk)) is not None and (a := _fm_attr(nn.fm)) in ATTR_LABELS
    }

    def _mirrored_default(raw: str | None) -> str:
        """相手側が何も書いていない時の既定値（手打ちの `:` / `;` 記法用）。

        相手（source）が `語;`（セミコロン終端）で書いていれば、自動では
        一切ミラーせず素の `ノート`。`語:`（コロン、既定の語も含む）で
        書いていれば、`(語)` の括弧付き（「相手から見た呼び方」の意。
        `ノート` 自体は括弧を付けずそのまま）。何も書かれていなければ
        `ノート`。
        """
        if raw is None:
            return "ノート"
        if raw.endswith(":;"):
            return raw  # `語:;` は相手側も `語:;`（括弧なし・終端）
        if raw.endswith(";"):
            return "ノート"  # `語;` は相手に書かない
        if raw.endswith("::"):
            return raw[:-2] + ":"  # 対称ラベル（両側 `語:`）
        base = raw[:-1] if raw.endswith(":") else raw  # `group:` -> `group`
        return base if base == "ノート" else f"({base})"

    def _is_mirror(lbl: str) -> bool:
        """相手側の自動ミラー表記 `(語)` かどうか。手打ちラベルと区別する。"""
        return len(lbl) >= 2 and lbl.startswith("(") and lbl.endswith(")")

    def up_side_label(pair: tuple[str, str]) -> str:
        """sid 自身の こっちにとって 側を再構築する時のラベル判定。

        - 既に自分で書いている（up_label）ラベルは sticky。ただし `(語)` の
          括弧付き（＝相手側からの自動ミラー）は自分で消しても追従できるよう
          自動扱いにし、相手の現在の書き方に従って更新・削除する。
        - 既定 `ノート` のときに相手が `語:` で書いていればミラーして格上げ。
        - 何も書いていなければ相手の書き方に従う（`_mirrored_default`）。

        例外: sid 自身が attribute（group）を持つ容器ノードの場合は、相手が
        書いた実際の関係名をそのまま使う（§3 の非対称ルールを逆方向にも保つ）。
        """
        sid = pair[0]
        if attr_of.get(sid) in ATTR_LABELS:
            return down_label.get(pair) or "ノート"
        if pair in up_label:
            cur = up_label[pair]
            mirrored = _mirrored_default(down_label.get(pair))
            if _is_mirror(cur):
                # 自動ミラーは相手の現在の書き方に追従（変更・削除も反映）
                return mirrored
            if cur == "ノート" and mirrored != "ノート":
                return mirrored
            return cur
        return _mirrored_default(down_label.get(pair))

    # --- 上側を再構築。相手が attribute 持ちなら自分側はグループ扱い（先頭表示） ---
    # incoming[to] = [from_id]。下側の再構築では `グループ` を特別扱いしない
    # （普通のノートとして扱う）。Child の並びは ユーザーが h/Enter/o/p や
    # 手編集で決めるもので、sync は並べ替えない（sticky）。
    incoming: dict[str, list[str]] = {}
    for (a, b) in present:
        incoming.setdefault(b, []).append(a)

    for k, n in by_path.items():
        sid = ids.get(k)
        if sid is None:
            continue
        # 相手（b）が attribute 持ち（group）でも、こちら側に明示ラベルがあれば
        # それを尊重する。裸（既定ノート）のときだけグループ扱い（先頭の裸リンク）
        # にする ── こうしないと、グループ宛に `aa:` と書いても `(aa)` に
        # ミラーされず、`:` / `;` が効かなくなる。
        def _up_label_for(b: str) -> str:
            lbl = up_side_label((sid, b))
            if b in attr_of and lbl == "ノート":
                return CATEGORY_ATTR
            return lbl

        outgoing = [(b, _up_label_for(b)) for (a, b) in present if a == sid]
        # 既存の並び順と、手で打った表示名を尊重
        order: list[str] = []
        orig_title: dict[str, str] = {}
        for t, es in n.up.items():
            if t == _EXTRA:
                continue
            for _ti, tg, _a in es:
                r = rid(tg, n.path.parent)
                if r:
                    order.append(r)
                    orig_title.setdefault(r, _ti)
        outgoing.sort(key=lambda x: order.index(x[0]) if x[0] in order else 1_000_000)
        new_up: dict[str, list] = {}
        for tid, lbl in outgoing:
            tp = id_to_path[tid]
            tn = by_path.get(tp)
            now_title = tn.title if tn is not None else Path(tid).stem
            disp = _tracked_disp(tid, orig_title.get(tid), now_title, prev_titles)
            new_up.setdefault(lbl, []).append(
                (disp, _rel(n.path.parent, tp), up_ann.get((sid, tid))))
        for t, es in up_unresolved[k].items():
            for e in es:
                new_up.setdefault(t, []).append(e)
        if n.up.get(_EXTRA):
            new_up[_EXTRA] = n.up[_EXTRA]
        n.up = new_up

    # --- 下側を再構築（関係 + 対称 + バックリンク） ---
    for k, n in by_path.items():
        nid = ids.get(k)
        new_down: dict[str, list] = {}
        if nid is not None:
            # 下側（子リスト・バックリンク含む）の表示名は _tracked_disp で判定
            # （書かれている表示名が前回 sync 時点の相手のタイトルと同じなら
            # 現タイトルへ追従、違えば手で変えたとみなしそのまま残す）。
            # ラベルも同様に sticky にする: 既にその相手向けの行があれば、
            # そこに今書かれているラベル（手で変えたものも含む）をそのまま使い
            # 続ける。新規のペアは常に既定の `ノート`（相手側の言葉を勝手に
            # 借りることはしない。関連・カテゴリー属性による強制は対象外）。
            # 表示順も sticky にする: ファイル内で手で並び替えた順序をそのまま
            # 保つ（sync が勝手にソートし直さない）。新規のものだけ末尾に足す。
            orig_down_title: dict[str, str] = {}
            orig_down_label: dict[str, str] = {}
            orig_down_order: list[str] = []
            orig_label_order: list[str] = []
            for t, es in n.down.items():
                if t == _EXTRA:
                    continue
                if t not in orig_label_order:
                    orig_label_order.append(t)
                for _ti, tg, _ann in es:
                    r = rid(tg, n.path.parent)
                    if r:
                        orig_down_title.setdefault(r, _ti)
                        orig_down_label.setdefault(r, t)
                        if r not in orig_down_order:
                            orig_down_order.append(r)

            def _down_sort_key(s: str) -> int:
                return orig_down_order.index(s) if s in orig_down_order else 1_000_000

            by_lbl: dict[str, list[str]] = {}
            for a in incoming.get(nid, []):
                if (nid, a) in present:  # 相互は下側に出さない
                    continue
                src_up = up_label.get((a, nid))       # 相手（a）側のラベル
                src_down = down_label.get((a, nid))   # 自分側のラベル
                src_raw = src_up or src_down
                # 下側（Child）では `グループ` を普通のノートとして扱う。
                # 位置をガチガチに固定するのは Parent（上側）の表示だけ。
                if src_up is not None and src_up.endswith(":;"):
                    # 相手（a）が `語:;` … こちら側も `語:;`（括弧なし・終端）
                    lbl = src_up
                elif src_up is not None and src_up.endswith(";"):
                    # 相手（a）が `語;` = 「このラベルは相手側に見せない」の意。
                    # 既に自動ミラーで入った行が残っていても既定の『ノート』へ戻す。
                    lbl = "ノート"
                elif a in orig_down_label:
                    cur = orig_down_label[a]
                    m = _mirrored_default(src_raw)
                    if _is_mirror(cur):
                        lbl = m  # 自動ミラー `(語)` は相手の変更・削除に追従
                    elif cur == "ノート" and m != "ノート":
                        lbl = m  # 既定の裸リンクは相手が `語:` なら自動ミラーへ格上げ
                    else:
                        lbl = cur  # 手で書いたラベルは sticky（`語;` もそのまま残す）
                elif attr_of.get(nid) in ATTR_LABELS:
                    # §3 の例外: 容器ノード自身の そっちにとって には、実際に
                    # 選んだ関係名がそのまま並ぶ（ノート の既定値に落とさない）。
                    lbl = src_raw or "ノート"
                else:
                    lbl = _mirrored_default(src_raw)
                if lbl.rstrip(";") == CATEGORY_ATTR:
                    lbl = "ノート"  # 下側では グループ を普通のノートとして扱う
                by_lbl.setdefault(lbl, []).append(a)
            for (a, t, b) in present_sym:
                other = b if a == nid else (a if b == nid else None)
                if other is not None:
                    by_lbl.setdefault(t, []).append(other)
            # Child の並びは基本 sticky（既存ラベルはファイル内の元の順、新規は
            # 末尾）。`グループ` は下側では普通のノートに正規化済みなので、
            # 既定リンクは 1 つの裸ブロックにまとまり、ユーザーが決めた並びのまま
            # 保たれる。sync は並べ替えない（位置は h/Enter/o/p と手編集で決める）。
            ordered_lbls = [l for l in orig_label_order if l in by_lbl]
            ordered_lbls += [l for l in by_lbl if l not in orig_label_order]
            for lbl in ordered_lbls:
                srcs = by_lbl[lbl]
                new_down[lbl] = [
                    (_tracked_disp(s, orig_down_title.get(s), by_path[id_to_path[s]].title,
                                   prev_titles),
                     _rel(n.path.parent, id_to_path[s]), None)
                    for s in sorted(set(srcs), key=_down_sort_key)
                ]
            back = sorted(
                (s for s, targets in body_links.items()
                 if nid in targets and (s, nid) not in directed
                 and (nid, s) not in directed and s in id_to_path),
                key=_down_sort_key,
            )
            if back:
                new_down[BACKLINK] = [
                    (_tracked_disp(s, orig_down_title.get(s), by_path[id_to_path[s]].title,
                                   prev_titles),
                     _rel(n.path.parent, id_to_path[s]), None)
                    for s in back
                ]
        if n.down.get(_EXTRA):
            new_down[_EXTRA] = n.down[_EXTRA]
        n.down = new_down
        if nid is not None:
            n.down_rendered = _render_down_preserving(
                n, lambda tg, base=n.path.parent: rid(tg, base))

    _save_state(root, set(present) | present_sym)
    _save_title_state(root, {i: by_path[p].title for i, p in id_to_path.items()})

    changed = 0
    for n in notes:
        if not n.managed:  # 外部ファイル（日記など）は絶対に書き換えない
            continue
        new_text = render_note(n)
        if new_text != n.path.read_text(encoding="utf-8"):
            n.path.write_text(new_text, encoding="utf-8")
            changed += 1
    return changed


def update_one(file_path, root) -> str:
    changed = sync_vault(root)
    return f"yurii_PKM: v2 synced {changed} file(s)" if changed else "yurii_PKM: no changes"


# ---------------------------------------------------------------------------
# new note
# ---------------------------------------------------------------------------

def make_new(path, title: str = "") -> Path:
    p = Path(path)
    ts = _dt.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    t = title.strip() or p.stem
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(
        f"---\ntime: {ts}\ntitle: {t}\n---\n\n# {t}\n\n\n{UP_MARK}\n{DOWN_MARK}\n",
        encoding="utf-8",
    )
    return p


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print(__doc__, file=sys.stderr)
        return 2
    mode = argv[1]
    if mode == "update":
        changed = sync_vault(argv[2])
        print(f"yurii_PKM: v2 updated {changed} file(s) under {argv[2]}")
        return 0
    if mode == "update_one":
        if len(argv) < 4:
            print("usage: note_format_v2.py update_one FILE ROOT", file=sys.stderr)
            return 2
        print(update_one(argv[2], argv[3]))
        return 0
    if mode == "new":
        if len(argv) < 4:
            print("usage: note_format_v2.py new FILE ROOT [TITLE]", file=sys.stderr)
            return 2
        title = argv[4] if len(argv) > 4 else ""
        p = make_new(argv[2], title)
        sync_vault(argv[3])
        print(str(p))
        return 0
    if mode == "retitle_links":
        if len(argv) >= 4:
            sync_vault(argv[3])
        print("yurii_PKM: v2 retitle via sync")
        return 0
    if mode == "migrate":
        # 明示的な変換。sync は旧形式を触らないので、これを 1 回走らせて v2 化する。
        if len(argv) < 3:
            print("usage: note_format_v2.py migrate ROOT [FILE]", file=sys.stderr)
            return 2
        root = Path(argv[2]).resolve()
        targets = [Path(argv[3])] if len(argv) > 3 else list(_iter_md(root))
        done = 0
        for tp in targets:
            try:
                cur = tp.read_text(encoding="utf-8")
            except OSError:
                continue
            new = migrate_note(cur, str(tp))
            if new and new != cur:
                tp.write_text(new, encoding="utf-8")
                done += 1
        if done:
            sync_vault(root)
        print(f"yurii_PKM: v2 migrated {done} file(s)")
        return 0
    if mode == "dupcheck":
        # 2 つの vault を merge する前に、同名 .md（＝タイムスタンプ衝突）を洗い出す。
        if len(argv) < 4:
            print("usage: note_format_v2.py dupcheck DIR_A DIR_B", file=sys.stderr)
            return 2
        a = {p.name for p in Path(argv[2]).rglob("*.md")} - {"index.md"}
        b = {p.name for p in Path(argv[3]).rglob("*.md")} - {"index.md"}
        dup = sorted(a & b)
        if dup:
            print("衝突するファイル名（merge 前にどちらかを改名）:")
            for name in dup:
                print(f"  {name}")
            return 1
        print("衝突なし（index.md を除く）")
        return 0
    if mode in {"update_titles", "rename_prefix", "reparent_down_children", "nf"}:
        print(f"yurii_PKM: v2 ignores mode '{mode}'", file=sys.stderr)
        return 0
    print(f"unsupported mode: {mode}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
