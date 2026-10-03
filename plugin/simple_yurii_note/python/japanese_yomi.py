#!/usr/bin/env python3
"""日本語のよみ（読み）ユーティリティ（simple_yurii_note 用）。

- front matter の ``yomi:`` マップ（表示名 → よみ）の parse / 保存
- pykakasi による かな化（未導入時は入力をそのまま使うフォールバック）
- 五十音順のソートキー（ローマ字は末尾）

``yomi:`` の形::

    yomi:
      "筋トレ": "きんとれ"

キーはリンクの表示名、値はよみ。行は JSON のダブルクォート文字列で保存する
（YAML のダブルクォートスカラーとしても読める）。pykakasi は遅延 import なので
このモジュールは未導入でも import できる。
"""
from __future__ import annotations

import json
import os
import re
from pathlib import Path

# 五十音の並び。濁点・半濁点・小書きは対応する清音の直後。
# 促音 っ は と の直後、ゔ は う の直後。
_GOJUON = (
    "あぁいぃうぅゔえぇおぉ"
    "かきくけこがぎぐげご"
    "さしすせそざじずぜぞ"
    "たちつてとだぢづでどっ"
    "なにぬねの"
    "はひふへほばびぶべぼぱぴぷぺぽ"
    "まみむめも"
    "やゃゆゅよょ"
    "らりるれろ"
    "わゎをん"
)
_RANK = {ch: i for i, ch in enumerate(_GOJUON)}
# 並べ替えで無視する文字（長音・中黒・空白・句読点など）
_IGNORE = set("ー・･ 　\t〜～-－=~.，,、。!！?？「」『』（）()［］[]")
_MIX_SEP = "\uffff"

_LINK_RE = re.compile(r"\[([^\]]*)\]\(([^)]+)\)")
_YOMI_HEAD_RE = re.compile(r"^yomi\s*:\s*$")
_YOMI_PAIR_RE = re.compile(r'^\s+("(?:[^"\\]|\\.)*")\s*:\s*("(?:[^"\\]|\\.)*")\s*$')

# --- pykakasi（遅延 import） ------------------------------------------------

_pykakasi = None
_pykakasi_checked = False


def _load_pykakasi():
    global _pykakasi, _pykakasi_checked
    if not _pykakasi_checked:
        _pykakasi_checked = True
        try:
            import pykakasi  # type: ignore

            _pykakasi = pykakasi.kakasi()
        except Exception:
            _pykakasi = None
    return _pykakasi


def has_pykakasi() -> bool:
    return _load_pykakasi() is not None


# テスト用に読み関数を差し替える（None で既定へ戻す）
_READER = None


def set_reader(fn) -> None:
    global _READER
    _READER = fn


def reset_reader() -> None:
    global _READER
    _READER = None


def reading_for(text: str) -> str:
    """text のよみを返す。pykakasi 未導入なら text をそのまま返す。"""
    if _READER is not None:
        return _READER(text)
    kks = _load_pykakasi()
    if kks is None:
        return text
    try:
        return "".join(item.get("hira", "") for item in kks.convert(text))
    except Exception:
        return text


def kata2hira(text: str) -> str:
    out = []
    for ch in text:
        code = ord(ch)
        if 0x30A1 <= code <= 0x30F6:
            out.append(chr(code - 0x60))
        else:
            out.append(ch)
    return "".join(out)


def reading_key(text: str) -> tuple:
    """五十音順のソートキー。かな語 → (0, ...)、ローマ字等 → (1, ...)。"""
    hira = kata2hira(reading_for(text))
    ranks: list[str] = []
    others: list[str] = []
    for ch in hira:
        if ch in _IGNORE or ch.isspace():
            continue
        r = _RANK.get(ch)
        if r is not None:
            ranks.append(chr(0x100 + r))
        else:
            others.append(ch.lower() if ch.isascii() else ch)
    if ranks and not others:
        return (0, "".join(ranks), "")
    if ranks:
        return (0, "".join(ranks) + _MIX_SEP + "".join(others), "")
    if others:
        return (1, "".join(others), "")
    return (2, "", text.casefold())


# --- yomi マップ（front matter） -------------------------------------------


def parse_yomi_map(fm: list[str]) -> dict[str, str]:
    """front matter 行から ``yomi:`` マップを取り出す（順序保持）。"""
    out: dict[str, str] = {}
    in_block = False
    for ln in fm:
        if not in_block:
            if _YOMI_HEAD_RE.match(ln):
                in_block = True
            continue
        m = _YOMI_PAIR_RE.match(ln)
        if m:
            try:
                out[json.loads(m.group(1))] = json.loads(m.group(2))
            except Exception:
                pass
            continue
        if ln.strip() == "":
            continue
        if not ln[:1].isspace():
            in_block = False
    return out


def set_yomi_map(fm: list[str], mapping: dict[str, str]) -> list[str]:
    """front matter 行の ``yomi:`` ブロックを mapping で置き換える。

    mapping が空ならブロックを削除する。title 行の直後に置く。
    """
    lines = list(fm)
    start = None
    for i, ln in enumerate(lines):
        if _YOMI_HEAD_RE.match(ln):
            start = i
            break
    if start is not None:
        end = start + 1
        while end < len(lines) and (lines[end][:1].isspace() or lines[end].strip() == ""):
            end += 1
        del lines[start:end]
    if mapping:
        block = ["yomi:"] + [
            "  %s: %s"
            % (json.dumps(k, ensure_ascii=False), json.dumps(v, ensure_ascii=False))
            for k, v in mapping.items()
        ]
        at = None
        for i, ln in enumerate(lines):
            if re.match(r"^\s*title\s*:", ln):
                at = i + 1
                break
        if at is None:
            at = max(1, len(lines) - 1)
        at = min(at, len(lines))
        lines[at:at] = block
    return lines


def split_front_matter(lines: list[str]) -> tuple[list[str], list[str]]:
    if lines and lines[0].strip() == "---":
        for i in range(1, len(lines)):
            if lines[i].strip() == "---":
                return lines[: i + 1], lines[i + 1:]
    return [], list(lines)


def get_yomi(path, name: str) -> str:
    """ノートの front matter の yomi マップから表示名 name のよみを返す。"""
    try:
        text = Path(path).read_text(encoding="utf-8")
    except OSError:
        return ""
    fm, _rest = split_front_matter(text.split("\n"))
    return parse_yomi_map(fm).get(name, "")


def set_yomi(path, name: str, reading: str) -> bool:
    """ノートの yomi マップに name → reading を登録（reading 空で削除）。

    変更したら True。
    """
    p = Path(path)
    text = p.read_text(encoding="utf-8")
    trailing_nl = text.endswith("\n")
    lines = text.split("\n")
    if trailing_nl and lines and lines[-1] == "":
        lines.pop()
    fm, rest = split_front_matter(lines)
    if not fm:
        fm = ["---", "title: " + p.stem, "---"]
    mapping = parse_yomi_map(fm)
    if reading:
        if mapping.get(name) == reading:
            return False
        mapping[name] = reading
    else:
        if name not in mapping:
            return False
        del mapping[name]
    new_fm = set_yomi_map(fm, mapping)
    out = new_fm + rest
    p.write_text("\n".join(out) + "\n", encoding="utf-8")
    return True


# --- ソート -----------------------------------------------------------------


def display_name(line: str) -> str:
    """行の最初の Markdown リンクの表示名。リンクが無ければ行全体。"""
    m = _LINK_RE.search(line)
    if m:
        return m.group(1)
    return line.strip()


def link_target(line: str) -> str:
    m = _LINK_RE.search(line)
    return m.group(2) if m else ""


def resolve_note(base_dir, target: str) -> Path | None:
    t = (target or "").strip()
    if t.startswith("file://"):
        t = t[7:]
    t = t.split("#", 1)[0]
    if not t.lower().endswith(".md"):
        return None
    return Path(t) if os.path.isabs(t) else Path(base_dir) / t


def line_reading(line: str, base_dir) -> str:
    """行のよみ。リンク行は表示名（対象ノートに yomi があれば優先）。"""
    m = _LINK_RE.search(line)
    if not m:
        return line.strip()
    disp = m.group(1)
    note = resolve_note(base_dir, m.group(2))
    if note is not None:
        y = get_yomi(note, disp)
        if y:
            return y
    return disp


def sort_lines(lines: list[str], base_dir) -> list[str]:
    """リンク行だけを表示名のよみ順に安定ソートする。

    リンクでない行は位置ごと動かさない（元の index に残る）。
    """
    slots = [i for i, ln in enumerate(lines) if _LINK_RE.search(ln)]
    keyed = []
    for i in slots:
        keyed.append((reading_key(line_reading(lines[i], base_dir)), i, lines[i]))
    keyed.sort(key=lambda t: (t[0], t[1]))
    out = list(lines)
    for slot, (_k, _i, ln) in zip(slots, keyed):
        out[slot] = ln
    return out
