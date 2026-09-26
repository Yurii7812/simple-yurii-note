#!/usr/bin/env python3
"""ノート形式 v2 用の「展開」機能。

現在のノートを起点に、親（こっちにとって）/ 子（そっちにとって）/ 文中
（バックリンク）方向へノートを辿り、集めたノートの本文を 1 つの使い捨て
md ファイルへ集約する。front matter や見張りコメントは含めない。

出力先は ROOT/_tmp/T_<タイムスタンプ>.md（sync は _tmp を一切見ない。
note_format_v2.EXPAND_TMP_DIR 参照）。編集しても元ノートへは反映されない
一方向のスナップショット。

モード:
    simple   … 親/子/文中を区別せず、全リンクを平等に扱って深さ N まで
                BFS で辿る（1 つの共有カウンタ）。
    detailed … 親・子・文中それぞれ独立の深さ（何回その種類の辺を辿れるか）
                を指定する。他の種類の辺を挟んでも、その種類自身の残り
                回数だけが減る。

detailed で使った深さは ROOT/.pkm_expand_prefs.json に記録し、次回
「保存済み設定」として呼び出せる。

CLI:
    expand_v2.py simple    ROOT START_FILE DEPTH
    expand_v2.py detailed  ROOT START_FILE CHILD_DEPTH PARENT_DEPTH BACKLINK_DEPTH
    expand_v2.py get_prefs ROOT
"""
from __future__ import annotations

import datetime as _dt
import json
import re
import sys
from pathlib import Path

import note_format_v2 as v2

_PREFS_FILE = ".pkm_expand_prefs.json"


# ---------------------------------------------------------------------------
# vault 読み込み・方向づけ
# ---------------------------------------------------------------------------

def _build_index(root: Path):
    by_name = v2._index(root)
    notes: dict[Path, v2.Note] = {}
    for p in v2._iter_md(root):
        try:
            notes[p.resolve()] = v2.parse_note(p)
        except Exception:  # noqa: BLE001
            continue
    ids: dict[Path, str] = {}
    id_to_path: dict[str, Path] = {}
    for k in notes:
        i = v2._nid(k, root)
        if i is not None:
            ids[k] = i
            id_to_path[i] = k
    return by_name, notes, ids, id_to_path


def _directions(n: v2.Note, root: Path, by_name, ids: dict[Path, str]) -> dict[str, set[str]]:
    """このノートから見た (親, 子, 文中) の id 集合。

    親 = こっちにとって側の全リンク先。
    子 = そっちにとって側の全リンク先（バックリンクを除く）。
    文中 = 双方向: このノートの そっちにとって バックリンク: セクションの
           リンク先（＝自分を本文で言及している相手）と、このノート自身の
           本文が言及している相手（型付きの関係が無い、素の本文リンク）の
           どちらも含む。
    """
    def rid(target: str) -> str | None:
        tp = v2._resolve(target, n.path.parent, root, by_name)
        return ids.get(tp.resolve()) if tp is not None else None

    parents: set[str] = set()
    for t, entries in n.up.items():
        if t == v2._EXTRA:
            continue
        for _ti, tg, _ann in entries:
            i = rid(tg)
            if i:
                parents.add(i)

    children: set[str] = set()
    backlinks: set[str] = set()
    for t, entries in n.down.items():
        if t == v2._EXTRA:
            continue
        for _ti, tg, _ann in entries:
            i = rid(tg)
            if i is None:
                continue
            (backlinks if t == v2.BACKLINK else children).add(i)

    for tg in v2._links_in(n.body):
        i = rid(tg)
        if i:
            backlinks.add(i)

    return {"parent": parents, "child": children, "backlink": backlinks}


# ---------------------------------------------------------------------------
# 収集（BFS）
# ---------------------------------------------------------------------------

Collected = tuple[list[str], dict]
"""(発見順の id リスト, {id: 発見元の id（起点は None）})。

`parent_of` は展開結果の木構造（目次のネストに使う）であって、ノート形式の
「親（こっちにとって）」とは無関係 ── ここでの「親」は単に「どのノートを
辿ってこの id にたどり着いたか」を指す。
"""


def collect_simple(start_id: str, dir_of, depth: int) -> Collected:
    """親/子/文中を区別せず、共有の深さ N まで辿る。順番は発見順。"""
    visited = {start_id}
    order = [start_id]
    parent_of: dict = {start_id: None}
    frontier = [start_id]
    for _ in range(max(depth, 0)):
        nxt: list[str] = []
        for nid in frontier:
            d = dir_of(nid)
            for neighbor in d["parent"] | d["child"] | d["backlink"]:
                if neighbor not in visited:
                    visited.add(neighbor)
                    order.append(neighbor)
                    parent_of[neighbor] = nid
                    nxt.append(neighbor)
        frontier = nxt
        if not frontier:
            break
    return order, parent_of


def _collect_pure_chain(start_id: str, dir_of, depth: int, kind: str) -> Collected:
    """起点から、指定した 1 種類の辺だけを辿って深さ N まで集める（純粋なチェーン。
    他の種類へは一切切り替えない）。"""
    visited = {start_id}
    order = [start_id]
    parent_of: dict = {start_id: None}
    frontier = [start_id]
    for _ in range(max(depth, 0)):
        nxt: list[str] = []
        for nid in frontier:
            for neighbor in dir_of(nid)[kind]:
                if neighbor not in visited:
                    visited.add(neighbor)
                    order.append(neighbor)
                    parent_of[neighbor] = nid
                    nxt.append(neighbor)
        frontier = nxt
        if not frontier:
            break
    return order, parent_of


def collect_detailed(start_id: str, dir_of, child_depth: int, parent_depth: int,
                      backlink_depth: int) -> Collected:
    """子方向を主軸に再帰展開し、その経路上の各ノート（起点含む）それぞれから
    独立に親・文中を指定の深さだけ辿って付け加える。

    - 子: 起点から純粋な子チェーンを depth=child_depth まで再帰的に展開する
      （各ノードの本文を全部見せる。「掘り下げる」方向）。
    - 親・文中: 上の子チェーンに含まれる**各ノードそれぞれ**について、その
      ノートを起点とした純粋な親チェーン（depth=parent_depth）・純粋な
      文中チェーン（depth=backlink_depth）を独立に辿って加える。ここでも
      種類は切り替わらない（親を辿った先でさらに子や文中には進まない）ので、
      例えば親の先がハブ的なノート（Index 等）でも、そのハブの他の子まで
      展開されることはない。
    - 全体を通して同じノートは 1 回だけ（重複除去）。
    """
    order = [start_id]
    seen = {start_id}
    parent_of: dict = {start_id: None}

    child_chain, child_parent_of = _collect_pure_chain(start_id, dir_of, child_depth, "child")
    for nid in child_chain[1:]:
        if nid not in seen:
            seen.add(nid)
            order.append(nid)
            parent_of[nid] = child_parent_of[nid]

    for anchor in child_chain:
        for kind, depth in (("parent", parent_depth), ("backlink", backlink_depth)):
            if depth <= 0:
                continue
            sub_chain, sub_parent_of = _collect_pure_chain(anchor, dir_of, depth, kind)
            for nid in sub_chain[1:]:
                if nid not in seen:
                    seen.add(nid)
                    order.append(nid)
                    parent_of[nid] = sub_parent_of[nid]

    return order, parent_of


# ---------------------------------------------------------------------------
# 出力レンダリング
# ---------------------------------------------------------------------------

def _anchor(index: int) -> str:
    return f"note-{index}"


_H1_RE = re.compile(r"^#\s+(.+?)\s*$")


def _body_without_own_h1(n: v2.Note) -> list[str]:
    """本文の先頭が自分のタイトルと同じ H1 なら、見出しの二重表示を避けて
    その行（と直後の空行）を取り除く（展開側で `## タイトル` を別途出すため）。"""
    body = list(n.body)
    idx = 0
    while idx < len(body) and body[idx].strip() == "":
        idx += 1
    if idx < len(body):
        m = _H1_RE.match(body[idx].strip())
        if m and m.group(1) == n.title:
            idx += 1
            while idx < len(body) and body[idx].strip() == "":
                idx += 1
            return body[idx:]
    return body


def _relation_lines(n: v2.Note, root: Path, by_name, tmp_dir: Path) -> list[str]:
    """このノートの関係リンク（こっちにとって・そっちにとって）を、展開先には
    含まれていないものも含めてそのままリンクとして書き出す（そこから先は
    展開しない ── あくまで「このノートは他に何にリンクしているか」を見せる
    だけ）。リンク先は展開ファイル（_tmp 配下）から見た相対パスに直す。"""
    lines: list[str] = []
    for side in (n.up, n.down):
        for label, entries in side.items():
            if label == v2._EXTRA:
                continue
            links: list[str] = []
            for title, tg, _ann in entries:
                tp = v2._resolve(tg, n.path.parent, root, by_name)
                rel = v2._rel(tmp_dir, tp) if tp is not None else tg
                links.append(f"[{title}]({rel})")
            if links:
                lines.append(f"- {label}: " + "、".join(links))
    return lines


def _toc_lines(start_id: str, order: list[str], parent_of: dict, notes_by_id: dict[str, v2.Note],
               anchors: dict[str, str]) -> list[str]:
    """`parent_of`（＝どのノートを辿ってこの id に着いたか）に沿って、
    段落（インデント）で経路が分かる目次を作る。"""
    children: dict[str, list[str]] = {}
    for nid in order:
        p = parent_of.get(nid)
        if p is not None:
            children.setdefault(p, []).append(nid)

    lines: list[str] = []

    def walk(nid: str, depth: int) -> None:
        indent = "  " * depth
        lines.append(f"{indent}- [{notes_by_id[nid].title}](#{anchors[nid]})")
        for c in children.get(nid, []):
            walk(c, depth + 1)

    walk(start_id, 0)
    return lines


def _render(order: list[str], parent_of: dict, notes_by_id: dict[str, v2.Note],
            root: Path, by_name, tmp_dir: Path) -> str:
    anchors = {i: _anchor(idx) for idx, i in enumerate(order)}
    start_id = order[0]
    start_title = notes_by_id[start_id].title

    out = [f"# 展開: {start_title}", "", "## 目次", ""]
    out.extend(_toc_lines(start_id, order, parent_of, notes_by_id, anchors))
    out.append("")
    out.append("---")

    for i in order:
        n = notes_by_id[i]
        out.append("")
        out.append(f'<a id="{anchors[i]}"></a>')
        out.append(f"## {n.title}")
        out.append("")
        out.extend(_body_without_own_h1(n))
        rel_lines = _relation_lines(n, root, by_name, tmp_dir)
        if rel_lines:
            out.append("")
            out.append("**関係リンク:**")
            out.extend(rel_lines)
        out.append("")
        out.append("---")

    text = "\n".join(out)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.rstrip() + "\n"


def _make_filename() -> str:
    ts = _dt.datetime.now().strftime("%y%m%d%H%M%S")
    return f"T_{ts}.md"


# ---------------------------------------------------------------------------
# 詳細モードの前回設定
# ---------------------------------------------------------------------------

def _load_prefs(root: Path) -> dict[str, int] | None:
    fp = root / _PREFS_FILE
    if not fp.exists():
        return None
    try:
        d = json.loads(fp.read_text(encoding="utf-8"))
        return {"child": int(d["child"]), "parent": int(d["parent"]), "backlink": int(d["backlink"])}
    except Exception:  # noqa: BLE001
        return None


def _save_prefs(root: Path, child: int, parent: int, backlink: int) -> None:
    fp = root / _PREFS_FILE
    fp.write_text(
        json.dumps({"child": child, "parent": parent, "backlink": backlink}, ensure_ascii=False),
        encoding="utf-8",
    )


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def _run(root: Path, start_file: Path, order_fn) -> Path:
    by_name, notes, ids, id_to_path = _build_index(root)
    start_id = ids.get(start_file.resolve())
    if start_id is None:
        raise SystemExit("expand_v2: 起点ノートが vault 内で見つからない（sync 済みか確認して）")

    dir_cache: dict[str, dict[str, set[str]]] = {}

    def dir_of(nid: str) -> dict[str, set[str]]:
        if nid not in dir_cache:
            dir_cache[nid] = _directions(notes[id_to_path[nid]], root, by_name, ids)
        return dir_cache[nid]

    order, parent_of = order_fn(start_id, dir_of)
    notes_by_id = {i: notes[id_to_path[i]] for i in order}

    tmp_dir = root / v2.EXPAND_TMP_DIR
    tmp_dir.mkdir(parents=True, exist_ok=True)
    text = _render(order, parent_of, notes_by_id, root, by_name, tmp_dir)
    out_path = tmp_dir / _make_filename()
    out_path.write_text(text, encoding="utf-8")
    return out_path


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print(__doc__, file=sys.stderr)
        return 2
    mode = argv[1]
    root = Path(argv[2]).resolve()

    if mode == "get_prefs":
        prefs = _load_prefs(root)
        if prefs:
            print(f"{prefs['child']} {prefs['parent']} {prefs['backlink']}")
        return 0

    if len(argv) < 4:
        print(__doc__, file=sys.stderr)
        return 2
    start_file = Path(argv[3])

    if mode == "simple":
        if len(argv) < 5:
            print("usage: expand_v2.py simple ROOT START_FILE DEPTH", file=sys.stderr)
            return 2
        depth = int(argv[4])
        out_path = _run(root, start_file, lambda sid, dir_of: collect_simple(sid, dir_of, depth))
    elif mode == "detailed":
        if len(argv) < 7:
            print("usage: expand_v2.py detailed ROOT START_FILE CHILD PARENT BACKLINK",
                  file=sys.stderr)
            return 2
        cd, pd, bd = int(argv[4]), int(argv[5]), int(argv[6])
        out_path = _run(root, start_file,
                         lambda sid, dir_of: collect_detailed(sid, dir_of, cd, pd, bd))
        _save_prefs(root, cd, pd, bd)
    else:
        print(f"unknown mode: {mode}", file=sys.stderr)
        return 2

    print(str(out_path))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
