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


# 変換不要（変換しても同じ）文字だけの文字列。かな・英数・記号。
# 登録済みの `yomi:` はひらがななので、\S の再ソートで pykakasi を
# 1 万回呼び直さないための近道（1 回の変換は速いが 1 万回で数秒になる）。
_NO_CONVERT_RE = re.compile(
    r"^[ぁ-ゖァ-ヺー・"
    r"A-Za-z0-9０-９"
    r"!\"#$%&'()*+,\-./:;<=>?@\[\\\]^_`{|}~ \t\r\n]*$"
)


def reading_for(text: str) -> str:
    """text のよみを返す。pykakasi 未導入なら text をそのまま返す。"""
    if _READER is not None:
        return _READER(text)
    if _NO_CONVERT_RE.match(text):
        return text
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


# 1 プロセス（= 1 回の sort/set 実行）内で front matter を 1 回だけ読む。
# \S は「未登録よみの書き込み」と「ソート」で同じ 1 万ノートを 2 周参照する。
# 読み直しをやめると 1 万行 Index で数秒変わる。書き込んだらメモも更新する。
_NOTE_MEMO: dict[str, "dict | None"] = {}
_RESOLVE_MEMO: dict[tuple[str, str], "Path | None"] = {}


def clear_memos() -> None:
    _NOTE_MEMO.clear()
    _RESOLVE_MEMO.clear()


def _note_entry(path) -> "dict | None":
    p = Path(path)
    key = os.path.abspath(str(p))
    if key in _NOTE_MEMO:
        return _NOTE_MEMO[key]
    try:
        text = p.read_text(encoding="utf-8")
    except OSError:
        _NOTE_MEMO[key] = None
        return None
    lines = text.split("\n")
    if text.endswith("\n") and lines and lines[-1] == "":
        lines.pop()
    fm, rest = split_front_matter(lines)
    ent = {"path": p, "fm": fm, "rest": rest, "map": parse_yomi_map(fm)}
    _NOTE_MEMO[key] = ent
    return ent


def get_yomi(path, name: str) -> str:
    """ノートの front matter の yomi マップから表示名 name のよみを返す。"""
    ent = _note_entry(path)
    return ent["map"].get(name, "") if ent else ""


def list_yomi_names(path) -> list[str]:
    """ノートの front matter の yomi マップの表示名を登録順に返す。"""
    ent = _note_entry(path)
    return list(ent["map"]) if ent else []


def set_yomi(path, name: str, reading: str) -> bool:
    """ノートの yomi マップに name → reading を登録（reading 空で削除）。

    変更したら True。
    """
    ent = _note_entry(path)
    if ent is None:
        return False
    p = ent["path"]
    fm = ent["fm"] or ["---", "title: " + p.stem, "---"]
    mapping = dict(ent["map"])
    if reading:
        if mapping.get(name) == reading:
            return False
        mapping[name] = reading
    else:
        if name not in mapping:
            return False
        del mapping[name]
    new_fm = set_yomi_map(fm, mapping)
    p.write_text("\n".join(new_fm + ent["rest"]) + "\n", encoding="utf-8")
    ent["fm"] = new_fm
    ent["map"] = mapping
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
    key = (os.path.abspath(str(base_dir)), t)
    if key in _RESOLVE_MEMO:
        return _RESOLVE_MEMO[key]
    p = Path(t) if os.path.isabs(t) else Path(base_dir) / t
    _RESOLVE_MEMO[key] = p
    return p


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


def persist_readings(lines: list[str], base_dir) -> int:
    """リンク行の表示名のよみが未登録なら、pykakasi で作って yomi: に書き込む。

    `\\S` のソート時に呼ぶ。ローマ字のまま等でよみが変わらない表示名は書かない。
    書いた件数を返す。
    """
    count = 0
    seen: set[tuple[str, str]] = set()
    for line in lines:
        m = _LINK_RE.search(line)
        if not m:
            continue
        disp = m.group(1)
        note = resolve_note(base_dir, m.group(2))
        if note is None or not note.is_file():
            continue
        key = (str(note), disp)
        if key in seen:
            continue
        seen.add(key)
        if get_yomi(note, disp):
            continue
        reading = reading_for(disp)
        if not reading or reading == disp:
            continue
        if not any(_RANK.get(ch) is not None for ch in kata2hira(reading)):
            continue
        if set_yomi(note, disp, reading):
            count += 1
    return count
