#!/usr/bin/env python3
"""expand_s.py  -- 任意ノート内の本文リンクを展開して T ノートを作る

usage:
    expand_s.py expand_s FILE ROOT [DEPTH]
    expand_s.py expand_any FILE ROOT [DEPTH]

- FILE の本文と Child セクションにある markdown リンクを展開する
- Back セクション以降は読まない
- 生成先は ROOT/T_YYMMDDhhmmss.md
- DEPTH は再帰展開の深さ
    0: 展開しない（空ファイルになりうる）
    1: 直接リンクのみ
    2: 1段深く再帰
    ...
"""
from __future__ import annotations

import re
import sys
from datetime import datetime
from pathlib import Path

LINK_RE = re.compile(r'\[([^\]]+)\]\(([^)]+)\)')
TITLE_RE = re.compile(r'^title:\s*(.*)$', re.IGNORECASE)
H1_RE = re.compile(r'^#{1,6}\s+(.+)$')


def bare_section_name(text: str) -> str:
    stripped = text.strip()
    stripped = re.sub(r'^#+\s*', '', stripped)
    stripped = re.sub(r':\s*$', '', stripped)
    return stripped.lower()


def section_aliases(name: str) -> set[str]:
    target = name.lower()
    if target in {"parent", "up"}:
        return {"parent", "up"}
    if target in {"child", "down", "branch"}:
        return {"child", "down", "branch"}
    if target in {"back", "backlink"}:
        return {"back", "backlink"}
    return {target}


def is_section_header(text: str, name: str) -> bool:
    return bare_section_name(text) in section_aliases(name)


def is_any_section_header(text: str, names: tuple[str, ...]) -> bool:
    section = bare_section_name(text)
    return any(section in section_aliases(name) for name in names)


def is_markdown_file(path: Path) -> bool:
    return path.suffix.lower() == '.md'


def is_url_target(target: str) -> bool:
    return re.match(r'^\w+://', target) is not None


def path_has_directory(target: str) -> bool:
    return '/' in target or '\\' in target


def ancestor_dirs_until_root(base: Path, root: Path) -> list[Path]:
    dirs: list[Path] = []
    try:
        root_resolved = root.resolve()
    except OSError:
        root_resolved = root

    current = base.resolve()
    while True:
        dirs.append(current)
        if current == root_resolved:
            break
        parent = current.parent
        if parent == current:
            break
        current = parent
    return dirs


def find_unique_file_near_tree(base: Path, root: Path, name: str) -> Path | None:
    files: list[Path] = []
    seen: set[Path] = set()

    for directory in ancestor_dirs_until_root(base, root):
        candidate = (directory / name).resolve()
        if candidate.is_file() and candidate not in seen:
            seen.add(candidate)
            files.append(candidate)
    if len(files) == 1:
        return files[0]
    if len(files) > 1:
        return None

    search_base = root.resolve() if root else base.resolve()
    if not search_base.exists():
        search_base = base.resolve()

    for candidate in search_base.rglob(name):
        resolved = candidate.resolve()
        if resolved in seen:
            continue
        seen.add(resolved)
        parts = set(resolved.parts)
        if candidate.is_file() and '.undo' not in parts and candidate.name == name:
            files.append(resolved)

    return files[0] if len(files) == 1 else None


def resolve_link_target(source_path: Path, target: str, root: Path) -> Path:
    if '\x00' in target or not target or is_url_target(target):
        return source_path.parent / target

    target_path = Path(target).expanduser()
    if target_path.is_absolute():
        return target_path.resolve()

    direct = (source_path.parent / target_path).resolve()
    if direct.is_file():
        return direct

    if not path_has_directory(target):
        found = find_unique_file_near_tree(source_path.parent, root, target)
        if found is not None:
            return found

    return direct


def read_lines(path: Path) -> list[str]:
    if not is_markdown_file(path):
        return []
    return path.read_text(encoding='utf-8').splitlines()


def write_lines(path: Path, lines: list[str]) -> None:
    text = '\n'.join(lines)
    if not text.endswith('\n'):
        text += '\n'
    path.write_text(text, encoding='utf-8')


def timestamp_filename() -> str:
    return datetime.now().strftime('%y%m%d%H%M%S')


def split_note(path: Path) -> tuple[str, list[str]]:
    """ノートを (title, body_lines) に分解する。

    対応順:
    1. YAML title
    2. 先頭付近の H1
    3. 本文最初の非空行をタイトル扱い

    Parent / Child / BackLink / Back セクション以降は本文に含めない。
    Branch 見出し単独行は無視する。
    """
    lines = read_lines(path)
    i = 0
    yaml_title = ''

    if lines and lines[0].strip() == '---':
        i = 1
        while i < len(lines):
            stripped = lines[i].strip()
            if stripped == '---':
                i += 1
                break
            m = TITLE_RE.match(lines[i])
            if m:
                yaml_title = m.group(1).strip().strip('"\'')
            i += 1

    while i < len(lines) and lines[i].strip() == '':
        i += 1

    title = yaml_title.strip()
    if i < len(lines):
        h1 = H1_RE.match(lines[i].strip())
        if h1:
            if not title:
                title = h1.group(1).strip()
            i += 1
            while i < len(lines) and lines[i].strip() == '':
                i += 1
        elif not title and lines[i].strip() and not is_section_header(lines[i].strip(), 'back'):
            # リンクのみ行はタイトルとして取り込まない（本文として展開させる）
            candidate = lines[i].strip()
            if not LINK_RE.match(candidate):
                title = candidate
                i += 1
                while i < len(lines) and lines[i].strip() == '':
                    i += 1

    if not title:
        title = path.stem

    body: list[str] = []
    in_fence = False
    for line in lines[i:]:
        stripped = line.strip()
        if stripped.startswith('```'):
            in_fence = not in_fence
            body.append(line)
            continue
        if not in_fence and is_any_section_header(stripped, ('parent', 'child', 'backlink', 'back')):
            break
        if not in_fence and is_section_header(stripped, 'branch'):
            continue
        body.append(line)

    while body and body[0].strip() == '':
        body.pop(0)
    while body and body[-1].strip() == '':
        body.pop()
    return title, body


def section_lines(path: Path, name: str) -> list[str]:
    """指定セクション内の行を返す（次の既知セクション手前まで）。"""
    lines = read_lines(path)
    result: list[str] = []
    in_section = False
    in_fence = False

    first_content_seen = False

    for line in lines:
        stripped = line.strip()
        if not first_content_seen:
            if stripped == '':
                continue
            first_content_seen = True
            if H1_RE.match(stripped):
                continue
        if stripped.startswith('```'):
            if in_section:
                result.append(line)
            in_fence = not in_fence
            continue

        if not in_fence and is_any_section_header(stripped, ('parent', 'child', 'backlink', 'back')):
            if in_section:
                break
            if is_section_header(stripped, name):
                in_section = True
            continue

        if in_section:
            result.append(line)

    return result


def linked_markdown_targets(lines: list[str], source_path: Path, root: Path) -> list[Path]:
    """行群に含まれる展開可能な Markdown リンク先を順番通り返す。"""
    targets: list[Path] = []
    seen: set[Path] = set()
    in_fence = False

    for line in lines:
        stripped = line.strip()
        if stripped.startswith('```'):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        for _, target in LINK_RE.findall(line):
            if '\x00' in target:
                continue
            target_path = resolve_link_target(source_path, target, root)
            if not is_markdown_file(target_path) or not target_path.exists():
                continue
            resolved = target_path.resolve()
            if resolved in seen:
                continue
            seen.add(resolved)
            targets.append(resolved)

    return targets


def child_links(path: Path, root: Path) -> list[Path]:
    """Child/Down/Branch セクションにある Markdown リンク先を返す。"""
    return linked_markdown_targets(section_lines(path, 'child'), path, root)


def extract_body_until_back(path: Path) -> list[str]:
    return split_note(path)[1]


def note_title(lines: list[str], path: Path) -> str:
    del lines
    return split_note(path)[0]


def body_links(path: Path, root: Path) -> list[tuple[str, Path]]:
    """本文（Back 以前）にあるリンクを順番通り返す。重複は 1 回。"""
    body = extract_body_until_back(path)
    seen: set[Path] = set()
    result: list[tuple[str, Path]] = []
    in_fence = False
    for line in body:
        stripped = line.strip()
        if stripped.startswith('```'):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        for text, target in LINK_RE.findall(line):
            if '\x00' in target:
                continue
            target_path = resolve_link_target(path, target, root)
            if not is_markdown_file(target_path):
                continue
            if not target_path.exists():
                continue
            if target_path in seen:
                continue
            seen.add(target_path)
            result.append((text, target_path))
    return result


def heading_for_depth(depth: int, title: str) -> str:
    level = max(2, min(depth, 6))
    return ('#' * level) + ' ' + title


def expand_target(target_path: Path, root: Path, heading_depth: int, expand_depth: int,
                  active_stack: set[Path]) -> list[str]:
    """リンク先ノートを、区切り付きの見出し＋本文として展開する。"""
    out: list[str] = []
    resolved = target_path.resolve()

    if resolved in active_stack:
        out.append(heading_for_depth(heading_depth, resolved.stem))
        out.append('')
        out.append('_(recursive cycle skipped)_')
        out.append('')
        out.append('##')
        out.append('')
        return out

    title, nested_body = split_note(resolved)
    out.append(heading_for_depth(heading_depth, title))
    out.append('')

    if expand_depth > 0:
        next_stack = set(active_stack)
        next_stack.add(resolved)

        if nested_body:
            if expand_depth == 1:
                out.extend(nested_body)
            else:
                expanded = expand_body_inline(
                    nested_body,
                    resolved,
                    root,
                    min(heading_depth + 1, 6),
                    expand_depth - 1,
                    next_stack,
                )
                out.extend(expanded)

        for child_path in child_links(resolved, root):
            if child_path in next_stack:
                continue
            if out and out[-1].strip() != '':
                out.append('')
            out.extend(
                expand_target(
                    child_path,
                    root,
                    min(heading_depth + 1, 6),
                    expand_depth - 1,
                    next_stack,
                )
            )

    # 展開内容後、空行を確保して ## 区切り
    if out and out[-1].strip() != '':
        out.append('')
    out.append('##')
    out.append('')
    return out


def expand_body_inline(body: list[str], source_path: Path, root: Path, heading_depth: int,
                       expand_depth: int, active_stack: set[Path]) -> list[str]:
    """本文を行ごとに走査し、リンクを読みやすく展開して返す。

    - 文章中の展開できるリンク: Markdown リンクを表示テキストに戻して文脈を残す
    - リンクだけの行: 元リンク行を重複表示せず、リンク先だけを展開する
    - 展開対象外のリンクやリンクを含まない行: そのまま出力する
    - コードフェンス内はリンク展開しない
    """
    out: list[str] = []
    in_fence = False
    seen: set[Path] = set()

    for line in body:
        stripped = line.strip()

        # コードフェンスの開閉を追跡
        if stripped.startswith('```'):
            in_fence = not in_fence
            out.append(line)
            continue

        if in_fence:
            out.append(line)
            continue

        expanded_targets: list[Path] = []
        total_links = 0

        def replace_link(match: re.Match[str]) -> str:
            nonlocal total_links
            total_links += 1
            target = match.group(2)
            target_path = resolve_link_target(source_path, target, root)
            can_expand = (
                '\x00' not in target
                and is_markdown_file(target_path)
                and target_path.exists()
                and target_path not in seen
            )
            if not can_expand:
                return match.group(0)

            seen.add(target_path)
            expanded_targets.append(target_path)
            return match.group(1)

        readable_line = LINK_RE.sub(replace_link, line)

        if not expanded_targets:
            # 展開対象リンクなし行: そのまま出力
            out.append(line)
            continue

        # 展開できたリンクだけで構成された行では、元リンク行を表示すると
        # 見出しと重複して読みにくい。文中リンクや未展開リンクが残る行だけ、
        # リンクを表示テキストに戻した文脈行を先に残す。
        non_link_text = LINK_RE.sub('', line).strip()
        only_expanded_links = not non_link_text and total_links == len(expanded_targets)
        if readable_line.strip() and not only_expanded_links:
            out.append(readable_line)
            out.append('')

        for target_path in expanded_targets:
            out.extend(expand_target(target_path, root, heading_depth, expand_depth, active_stack))

    return out


def build_expanded_content(source_path: Path, root: Path, depth: int) -> list[str]:
    """ソースファイルの本文をインライン展開して返す。

    depth == 0 のときはソース本文をそのまま出力（展開なし）。
    """
    title, body = split_note(source_path)

    if depth <= 0:
        content = list(body)
    else:
        active_stack = {source_path.resolve()}
        content = expand_body_inline(
            body,
            source_path,
            root,
            heading_depth=2,
            expand_depth=depth,
            active_stack=active_stack,
        )
        for child_path in child_links(source_path, root):
            if child_path in active_stack:
                continue
            if content and content[-1].strip() != '':
                content.append('')
            content.extend(expand_target(child_path, root, 2, depth, active_stack))

    header = ['# ' + title, '']
    content = header + content

    while content and content[-1].strip() == '':
        content.pop()
    content.append('')
    return content


def expand_note(file_path: Path, root: Path, depth: int) -> Path:
    ts = timestamp_filename()
    t_path = root / f'T_{ts}.md'
    root.mkdir(parents=True, exist_ok=True)
    write_lines(t_path, build_expanded_content(file_path, root, depth))
    return t_path


def parse_depth(arg: str | None) -> int:
    if arg is None:
        return 1
    try:
        depth = int(arg)
    except ValueError:
        raise SystemExit('Error: DEPTH must be an integer')
    if depth < 0:
        raise SystemExit('Error: DEPTH must be >= 0')
    return depth


def main(argv: list[str]) -> int:
    if len(argv) < 4 or argv[1] not in {'expand_s', 'expand_any'}:
        print('usage: expand_s.py expand_s FILE ROOT [DEPTH]', file=sys.stderr)
        print('   or: expand_s.py expand_any FILE ROOT [DEPTH]', file=sys.stderr)
        return 2

    file_path = Path(argv[2])
    root = Path(argv[3])
    depth = parse_depth(argv[4] if len(argv) >= 5 else None)

    if not file_path.exists():
        print(f'Error: file not found: {file_path}', file=sys.stderr)
        return 1
    if not is_markdown_file(file_path):
        print(f'Error: not a markdown file: {file_path}', file=sys.stderr)
        return 1

    t_path = expand_note(file_path, root, depth)
    print(str(t_path))
    return 0


if __name__ == '__main__':
    raise SystemExit(main(sys.argv))
