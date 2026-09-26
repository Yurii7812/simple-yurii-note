#!/usr/bin/env python3
from __future__ import annotations

import re
import sys
from dataclasses import dataclass, field
from pathlib import Path
from datetime import datetime
from os import path as ospath
from typing import Iterable

# ---------------------------------------------------------------------------
# Regex
# ---------------------------------------------------------------------------
LINK_RE    = re.compile(r'\[([^\]]+)\]\(([^)]+)\)')
FIXED_LINK_TEXT_MARKER = "pkm:fixed-text"
TITLE_RE   = re.compile(r'^title:\s*(.*)$', re.IGNORECASE)
FILETYPE_RE = re.compile(r'^filetype:\s*(.*)$', re.IGNORECASE)
H1_RE      = re.compile(r'^#\s+(.+)$')
SEP_RE     = re.compile(r'^_{3,}\s*$')
SECTION_NAMES = {"parent", "child", "up", "down", "branch", "back", "backlink"}



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


def canonical_section_title(name: str) -> str:
    target = name.lower()
    if target in {"parent", "up"}:
        return "Parent:"
    if target in {"child", "down", "branch"}:
        return "Child:"
    if target in {"back", "backlink"}:
        return "BackLink:"
    return f"{name.capitalize()}:"


def is_section_header(text: str, name: str) -> bool:
    return bare_section_name(text) in section_aliases(name)


def is_markdown_file(path: Path) -> bool:
    return path.suffix.lower() == '.md'


def is_t_note(path: Path) -> bool:
    return path.stem.startswith('T_')


def has_yaml_front_matter(lines: list[str]) -> bool:
    if not lines:
        return False
    if lines[0].strip() != '---':
        return False
    for line in lines[1:]:
        if line.strip() == '---':
            return True
    return False


def is_expand_generated_t_note(path: Path, lines: list[str] | None = None) -> bool:
    if not is_t_note(path):
        return False
    if lines is None:
        lines = read_lines(path)
    return not has_yaml_front_matter(lines)


def is_external_link_target(target: str) -> bool:
    return bool(re.match(r'^\w+://', target.strip()))


def link_target_has_directory(target: str) -> bool:
    return "/" in target or "\\" in target


def resolve_existing_note_link(
    target: str,
    base_dir: Path,
    root: Path,
    notes_by_name: dict[str, list[Path]] | None = None,
) -> Path | None:
    """Resolve an existing note link like Vim's link opener.

    Markdown links are normally relative to the current note's folder, but Yurii
    PKM also allows a bare filename to point to a unique note elsewhere under
    the PKM root.  This is important for notes moved into dated subfolders while
    keeping older bare links such as ``260529001336.md``.
    """
    target = target.strip()
    if not target or "\x00" in target or is_external_link_target(target):
        return None

    candidate = Path(target)
    if candidate.is_absolute():
        resolved = candidate.resolve()
        if resolved.exists() and is_markdown_file(resolved):
            return resolved
        return None

    base_dir = base_dir.resolve()
    root = root.resolve()

    direct = (base_dir / target).resolve()
    if direct.exists() and is_markdown_file(direct):
        return direct

    if link_target_has_directory(target):
        # Links copied from another note can be relative to the PKM root
        # instead of the destination note's directory (for example
        # ``./N_root.md`` or ``folder/N_child.md``).  Re-resolve those from
        # the root so generated reciprocal links are rebased correctly.
        root_relative = (root / target).resolve()
        if root_relative.exists() and is_markdown_file(root_relative):
            return root_relative
        return None

    matches: list[Path] = []
    seen: set[Path] = set()

    current = base_dir
    while True:
        resolved = (current / target).resolve()
        if resolved.exists() and is_markdown_file(resolved) and resolved not in seen:
            seen.add(resolved)
            matches.append(resolved)
        if current == root or current.parent == current:
            break
        try:
            current.relative_to(root)
        except ValueError:
            break
        current = current.parent

    if len(matches) == 1:
        return matches[0]
    if len(matches) > 1:
        return None

    global_candidates = (
        notes_by_name.get(target, [])
        if notes_by_name is not None
        else [
            path.resolve()
            for path in sorted(root.rglob("*.md"))
            if path.name == target and path.is_file() and ".undo" not in path.parts
        ]
    )
    for resolved in global_candidates:
        if resolved not in seen:
            seen.add(resolved)
            matches.append(resolved)

    return matches[0] if len(matches) == 1 else None

# ---------------------------------------------------------------------------
# Low-level helpers
# ---------------------------------------------------------------------------

def read_lines(path: Path) -> list[str]:
    if not is_markdown_file(path):
        return []
    return path.read_text(encoding="utf-8").splitlines()


def write_lines(path: Path, lines: list[str]) -> None:
    text = "\n".join(lines)
    if not text.endswith("\n"):
        text += "\n"
    path.write_text(text, encoding="utf-8")


def note_title(lines: list[str], path: Path) -> str:
    in_yaml = False
    yaml_done = False
    for line in lines[:40]:
        stripped = line.strip()
        if stripped == "---":
            if not in_yaml:
                in_yaml = True
            else:
                in_yaml = False
                yaml_done = True
            continue
        if in_yaml:
            m = TITLE_RE.match(line)
            if m:
                return m.group(1).strip() or path.stem
        if not in_yaml:
            m = H1_RE.match(line)
            if m:
                return m.group(1).strip()
    return path.stem


def note_filetype(lines: list[str], path: Path) -> str:
    in_yaml = False
    for line in lines[:40]:
        stripped = line.strip()
        if stripped == "---":
            in_yaml = not in_yaml
            continue
        if not in_yaml:
            continue
        m = FILETYPE_RE.match(line)
        if m:
            value = m.group(1).strip().upper()
            return value[:1] if value else ""

    stem = path.stem
    if "_" in stem:
        return stem.split("_", 1)[0].upper()[:1]
    return ""


def find_section(lines: list[str], name: str) -> tuple[int, int]:
    """Return (start_index, end_index) of *name* section.

    start_index points to the section-header line itself.
    end_index points to the next section header (or len(lines)).
    Returns (-1, -1) when not found.
    """
    target = name.lower()
    candidates: list[int] = []
    in_fence = False
    for i, line in enumerate(lines):
        stripped = line.strip()
        if stripped.startswith("```"):
            in_fence = not in_fence
        if not in_fence and is_section_header(stripped, target):
            candidates.append(i)
    if not candidates:
        return (-1, -1)
    start = candidates[-1]
    end = len(lines)
    in_fence = False
    for j in range(start + 1, len(lines)):
        stripped = lines[j].strip()
        if stripped.startswith("```"):
            in_fence = not in_fence
        if not in_fence and bare_section_name(stripped) in SECTION_NAMES:
            end = j
            break
    return (start, end)


def section_content(lines: list[str], name: str) -> list[str]:
    start, end = find_section(lines, name)
    if start < 0:
        return []
    return lines[start + 1: end]


def replace_section(lines: list[str], name: str, new_content: list[str]) -> list[str]:
    start, end = find_section(lines, name)
    if start < 0:
        lines = list(lines) + [canonical_section_title(name)]
        start = len(lines) - 1
        end = len(lines)
    return lines[: start + 1] + new_content + lines[end:]


def remove_section(lines: list[str], name: str) -> list[str]:
    start, end = find_section(lines, name)
    if start < 0:
        return list(lines)
    new_lines = lines[:start] + lines[end:]
    while len(new_lines) >= 2 and new_lines[-1] == "" and new_lines[-2] == "":
        new_lines.pop()
    return new_lines


def ensure_sections(lines: list[str]) -> list[str]:
    lines = list(lines)
    if find_section(lines, "up")[0] < 0:
        lines = lines + [canonical_section_title("up")]

    if find_section(lines, "down")[0] < 0:
        back_start, _ = find_section(lines, "backlink")
        if back_start >= 0:
            lines = lines[:back_start] + [canonical_section_title("down")] + lines[back_start:]
        else:
            lines = lines + [canonical_section_title("down")]

    if find_section(lines, "backlink")[0] < 0:
        lines = lines + ["", canonical_section_title("backlink")]

    return lines


def parse_links(lines: list[str]) -> list[tuple[str, str]]:
    """Return [(text, target), ...] from lines, skipping ___-separated content."""
    result = []
    for line in lines:
        if SEP_RE.match(line):
            break
        for text, target in LINK_RE.findall(line):
            result.append((text, target))
    return result


def outbound_links_from_down(lines: list[str]) -> list[tuple[str, str]]:
    """Collect markdown links from Child section (or legacy Branch)."""
    result: list[tuple[str, str]] = []
    down_start, down_end = find_section(lines, "down")
    if down_start < 0:
        down_start, down_end = find_section(lines, "branch")
    if down_start < 0:
        return result

    in_fence = False
    for line in lines[down_start + 1: down_end]:
        stripped = line.strip()

        if stripped.startswith("```"):
            in_fence = not in_fence
            continue
        if in_fence:
            continue

        if SEP_RE.match(stripped):
            break

        for text, target in LINK_RE.findall(line):
            result.append((text, target))

    return result


def outbound_links_for_backlink(lines: list[str]) -> list[tuple[str, str]]:
    """Collect markdown links from body text (exclude Parent/Child/BackLink sections)."""
    result: list[tuple[str, str]] = []
    in_yaml = False
    in_fence = False
    for i, line in enumerate(lines):
        stripped = line.strip()
        if i == 0 and stripped == "---":
            in_yaml = True
            continue
        if in_yaml:
            if stripped == "---":
                in_yaml = False
            continue

        if stripped.startswith("```"):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        if SEP_RE.match(stripped):
            break
        if (is_section_header(stripped, "up")
                or is_section_header(stripped, "down")
                or is_section_header(stripped, "branch")
                or is_section_header(stripped, "back")
                or is_section_header(stripped, "backlink")):
            break

        for text, target in LINK_RE.findall(line):
            result.append((text, target))
    return result


def outbound_links_from_index(lines: list[str]) -> list[tuple[str, str]]:
    """Collect structural links from index.md without requiring a Child section."""
    result: list[tuple[str, str]] = []
    seen: set[str] = set()
    for links in (outbound_links_for_backlink(lines), outbound_links_from_down(lines)):
        for text, target in links:
            if target in seen:
                continue
            seen.add(target)
            result.append((text, target))
    return result

def sort_back_links(
    link_lines: list[str],
    from_dir: Path,
    include_index: bool = True,
    category_targets: set[Path] | None = None,
) -> list[str]:
    """Sort BackLink links into Category/Note blocks."""
    note_links: list[tuple[datetime, str]] = []
    category_links: list[tuple[datetime, str]] = []
    index_line = "[Index](index.md)"
    category_targets = category_targets or set()

    def sort_datetime(target_path: Path) -> datetime:
        stem = target_path.stem
        if "_" in stem:
            _, ts = stem.split("_", 1)
            if re.fullmatch(r"\d{12}", ts):
                try:
                    return datetime.strptime(ts, "%y%m%d%H%M%S")
                except ValueError:
                    pass

        lines = read_lines(target_path)
        in_yaml = False
        for line in lines[:40]:
            stripped = line.strip()
            if stripped == "---":
                in_yaml = not in_yaml
                continue
            if not in_yaml:
                continue
            if stripped.lower().startswith("time:"):
                value = stripped.split(":", 1)[1].strip().strip('"\'')
                for fmt in ("%Y-%m-%d %H:%M:%S", "%Y-%m-%d"):
                    try:
                        return datetime.strptime(value, fmt)
                    except ValueError:
                        pass

        try:
            return datetime.fromtimestamp(target_path.stat().st_mtime)
        except OSError:
            return datetime.min

    for line in link_lines:
        m = re.search(r'\(([^)]+)\)', line)
        if not m:
            continue
        target = m.group(1).strip()
        fname = target.split('/')[-1]
        if fname.lower() == 'index.md':
            index_line = line
            continue

        target_path = (from_dir / target).resolve()
        dt = sort_datetime(target_path)
        if target_path in category_targets:
            category_links.append((dt, line))
        else:
            note_links.append((dt, line))

    category_links.sort(key=lambda x: x[0], reverse=True)
    note_links.sort(key=lambda x: x[0], reverse=True)

    result: list[str] = []
    if category_links:
        result.append("Category:")
        result.extend(line for _, line in category_links)
    if note_links:
        if result:
            result.append("")
            result.append("Note:")
        result.extend(line for _, line in note_links)
    if include_index:
        if result:
            result.append("")

        result.append(index_line)
    return result


def build_back(
    parent_paths: list[Path],
    note_path: Path,
    existing_lines: list[str],
    category_parents: set[Path] | None = None,
) -> list[str]:
    """Build Back section content from parent paths."""
    from_dir = note_path.parent
    include_index = note_path.name != 'index.md'

    existing_index = ''
    for line in existing_lines:
        m = re.search(r'\(([^)]+)\)', line)
        if m and m.group(1).strip().split('/')[-1] == 'index.md':
            existing_index = line
            break

    deduped_parents: list[Path] = []
    seen: set[Path] = set()
    for parent in parent_paths:
        rp = parent.resolve()
        if rp == note_path.resolve() or rp in seen:
            continue
        seen.add(rp)
        deduped_parents.append(rp)

    raw = [make_link_line(p, get_title(p), from_dir) for p in deduped_parents]
    result = sort_back_links(
        raw,
        from_dir,
        include_index=include_index,
        category_targets={p.resolve() for p in (category_parents or set())},
    )

    if include_index and existing_index and result and result[-1].lower().startswith('[index]'):
        result[-1] = existing_index

    return result


def make_link_line(target_path: Path, title: str, from_dir: Path) -> str:
    target_path = target_path.resolve()
    from_dir = from_dir.resolve()
    rel_str = ospath.relpath(target_path, from_dir).replace(ospath.sep, "/")
    text = title if title else target_path.stem
    return f"[{text}]({rel_str})"


def create_f_and_link(current_file: Path, root: Path) -> Path:
    """Legacy helper kept for compatibility.

    Creates a new F note and inserts its link just before the current file's Back section.
    """
    current_file = current_file.resolve()
    root = root.resolve()

    ts = datetime.now().strftime("%y%m%d%H%M%S")
    f_name = f"F_{ts}.md"
    f_path = root / f_name

    content = [
        "---",
        f"time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}",
        "title: ",
        "---",
        "",
        "# ",
        "",
        "",
        "",
        canonical_section_title("up"),
        canonical_section_title("down"),
        canonical_section_title("backlink"),
        "[index](index.md)",
    ]
    root.mkdir(parents=True, exist_ok=True)
    write_lines(f_path, content)

    lines = ensure_sections(read_lines(current_file))
    back_start, _ = find_section(lines, "back")
    insert_at = back_start if back_start >= 0 else len(lines)

    rel = f_path.relative_to(current_file.parent).as_posix()
    link_line = f"[{f_path.stem}]({rel})"
    new_lines = list(lines)
    if link_line not in new_lines:
        new_lines.insert(insert_at, link_line)
        write_lines(current_file, new_lines)

    return f_path


# ---------------------------------------------------------------------------
# Title cache
# ---------------------------------------------------------------------------

_title_cache: dict[Path, str] = {}
_filetype_cache: dict[Path, str] = {}

def get_title(path: Path) -> str:
    path = path.resolve()
    if not is_markdown_file(path):
        return ""
    if path in _title_cache:
        return _title_cache[path]
    if not path.exists():
        return ""
    lines = read_lines(path)
    t = note_title(lines, path)
    _title_cache[path] = t
    return t


def get_filetype(path: Path) -> str:
    path = path.resolve()
    if not is_markdown_file(path) or not path.exists():
        return ""
    if path in _filetype_cache:
        return _filetype_cache[path]
    lines = read_lines(path)
    t = note_filetype(lines, path)
    _filetype_cache[path] = t
    return t


# ---------------------------------------------------------------------------
# update_titles_in_file
#   - markdown リンクの表示テキストを最新タイトルに更新
#   - branch/back 内でファイルが存在しないリンクを削除
#   - ___ 以降は処理しない
# ---------------------------------------------------------------------------

def update_titles_in_file(path: Path) -> bool:
    """Rewrite markdown link text to note titles in one file. Return True if changed."""
    lines = read_lines(path)
    base = path.parent
    result: list[str] = []
    modified = False
    in_branch = False
    in_back = False
    after_sep = False
    in_fence = False

    for line in lines:
        stripped = line.strip()

        if stripped.startswith("```"):
            in_fence = not in_fence

        if not in_fence:
            if is_section_header(stripped, "down") or is_section_header(stripped, "branch"):
                in_branch, in_back, after_sep = True, False, False
                result.append(line)
                continue
            if is_section_header(stripped, "back"):
                in_branch, in_back, after_sep = False, True, False
                result.append(line)
                continue
            if SEP_RE.match(line):
                after_sep = True
                result.append(line)
                continue

        if after_sep or in_fence:
            result.append(line)
            continue

        m = re.match(r'^\s*(\[([^\]]+)\]\(([^)]+)\))\s*$', line)
        if not m:
            result.append(line)
            continue

        link_text = m.group(2)
        target_text = m.group(3)

        if link_text != Path(target_text).stem:
            # 手動で付けた表示名は保持（stem一致のみ自動更新対象）
            result.append(line)
            continue

        if '\x00' in target_text:
            result.append(line)
            continue

        target = (base / target_text).resolve()
        if not is_markdown_file(target):
            result.append(line)
            continue

        if not target.exists():
            if in_branch or in_back:
                # 存在しないファイルへのリンクは branch/back では削除
                modified = True
                continue
            result.append(line)
            continue

        title = get_title(target)
        text = title if title else Path(target_text).stem
        prefix_ws = re.match(r'^\s*', line).group(0)
        suffix_ws = re.search(r'\s*$', line).group(0)
        new_line = f"{prefix_ws}[{text}]({target_text}){suffix_ws}"
        if new_line != line:
            modified = True
            line = new_line
        result.append(line)

    if modified:
        write_lines(path, result)
    return modified



@dataclass(frozen=True)
class NotesIndex:
    paths: list[Path]
    by_name: dict[str, list[Path]]
    path_set: set[Path]


def build_notes_index(root: Path, extra_paths: Iterable[Path] = ()) -> NotesIndex:
    """Build the managed-note index once for a sync operation."""

    root = root.resolve()
    paths: list[Path] = [p.resolve() for p in iter_notes(root)]
    path_set = set(paths)
    for extra in extra_paths:
        resolved = extra.resolve()
        if resolved not in path_set and is_markdown_file(resolved) and resolved.is_file() and ".undo" not in resolved.parts:
            paths.append(resolved)
            path_set.add(resolved)

    by_name: dict[str, list[Path]] = {}
    for path in paths:
        by_name.setdefault(path.name, []).append(path)
    return NotesIndex(paths=paths, by_name=by_name, path_set=path_set)

# ---------------------------------------------------------------------------
# update_up_sections (full scan: Child -> Parent propagation)
# ---------------------------------------------------------------------------


def is_managed_note(path: Path, root: Path) -> bool:
    """Return True when *path* is a markdown note managed under *root*."""
    path = path.resolve()
    root = root.resolve()
    try:
        path.relative_to(root)
    except ValueError:
        return False
    return (
        is_markdown_file(path)
        and path.is_file()
        and ".undo" not in path.parts
    )


def is_root_note(path: Path, root: Path) -> bool:
    """Backward-compatible alias for managed-note checks."""
    return is_managed_note(path, root)


def iter_notes(root: Path) -> Iterable[Path]:
    """Yield all managed markdown notes under the active PKM root.

    Structural links can cross folders, so full/update-one sync must consider
    nested notes as first-class notes instead of only rewriting files directly
    below the root. ``.undo`` snapshots are excluded.
    """
    root = root.resolve()
    for path in sorted(root.rglob("*.md")):
        if is_managed_note(path, root):
            yield path


def up_targets(
    lines: list[str],
    note_path: Path,
    root: Path,
    notes_by_name: dict[str, list[Path]],
) -> set[Path]:
    targets: set[Path] = set()
    for _, target in parse_links(section_content(lines, "up")):
        resolved = resolve_existing_note_link(target, note_path.parent, root, notes_by_name)
        if resolved is not None:
            targets.add(resolved)
    return targets


def down_targets(
    lines: list[str],
    note_path: Path,
    root: Path,
    notes_by_name: dict[str, list[Path]],
) -> set[Path]:
    """Return resolved notes listed in a note's Child section."""

    targets: set[Path] = set()
    for _, target in outbound_links_from_down(lines):
        resolved = resolve_existing_note_link(target, note_path.parent, root, notes_by_name)
        if resolved is not None:
            targets.add(resolved.resolve())
    return targets


def links_just_before_up(lines: list[str]) -> set[str]:
    """Return link targets only from the line directly adjacent to Parent:."""
    up_start, _ = find_section(lines, "up")
    if up_start <= 0:
        return set()

    previous_line = lines[up_start - 1]
    return {target for _, target in LINK_RE.findall(previous_line)}


def build_multi_up(
    parent_paths: list[Path],
    note_path: Path,
    current_up_targets: set[Path] | None = None,
    prune_targets: set[Path] | None = None,
    exact: bool = False,
) -> list[str]:
    """Build Parent from Child-derived parents, pruning stale links when requested."""

    resolved_parents = {p.resolve() for p in parent_paths}
    if exact:
        parents = resolved_parents
    else:
        current_up_targets = {p.resolve() for p in (current_up_targets or set())}
        prune_targets = {p.resolve() for p in (prune_targets or set())}
        parents = resolved_parents | (current_up_targets - prune_targets)

    return [
        make_link_line(parent, get_title(parent), note_path.parent)
        for parent in sorted(parents)
    ]


def remove_down_links_to_target(
    lines: list[str],
    note_path: Path,
    target_path: Path,
    root: Path,
    notes_by_name: dict[str, list[Path]],
) -> tuple[list[str], bool]:
    """Remove links to *target_path* from the note's Child section.

    Parent and Child are reciprocal structural links.  When a user deletes a parent
    from the current note's Parent section, the old parent still has a Child link
    pointing back to the current note.  If that stale Child link is left in
    place, the next sync regenerates the deleted Parent link, making the link feel
    impossible to remove.
    """

    down_start, down_end = find_section(lines, "down")
    if down_start < 0:
        down_start, down_end = find_section(lines, "branch")
    if down_start < 0:
        return list(lines), False

    target_path = target_path.resolve()
    modified = False
    new_section: list[str] = []
    in_fence = False

    line_modified = False

    def replacement(match: re.Match[str]) -> str:
        nonlocal line_modified
        resolved = resolve_existing_note_link(
            match.group(2),
            note_path.parent,
            root,
            notes_by_name,
        )
        if resolved is not None and resolved.resolve() == target_path:
            line_modified = True
            return ""
        return match.group(0)

    for line in lines[down_start + 1: down_end]:
        stripped = line.strip()

        if stripped.startswith("```"):
            in_fence = not in_fence
            new_section.append(line)
            continue

        if in_fence or SEP_RE.match(stripped):
            new_section.append(line)
            continue

        line_modified = False
        new_line = LINK_RE.sub(replacement, line)
        if line_modified:
            modified = True
        if line_modified and not new_line.strip():
            continue
        new_section.append(new_line.rstrip() if line_modified else line)

    if not modified:
        return list(lines), False

    return lines[: down_start + 1] + new_section + lines[down_end:], True


def remove_reciprocal_down_links_for_missing_up(file_path: Path, root: Path, index: NotesIndex | None = None) -> int:
    """Prune stale reciprocal Child links after Parent links are manually removed."""

    file_path = file_path.resolve()
    root = root.resolve()
    index = index or build_notes_index(root)
    all_paths = index.paths
    notes_by_name = index.by_name

    if file_path not in index.path_set:
        return 0

    current_lines = read_lines(file_path)
    if find_section(current_lines, "up")[0] < 0:
        return 0
    current_up_targets = up_targets(current_lines, file_path, root, notes_by_name)
    changed = 0

    for parent in all_paths:
        parent = parent.resolve()
        if parent == file_path:
            continue
        if parent in current_up_targets:
            continue

        parent_lines = read_lines(parent)
        has_down_link = False
        for _, target in outbound_links_from_down(parent_lines):
            resolved = resolve_existing_note_link(target, parent.parent, root, notes_by_name)
            if resolved is not None and resolved.resolve() == file_path:
                has_down_link = True
                break
        if not has_down_link:
            continue

        new_lines, modified = remove_down_links_to_target(
            parent_lines,
            parent,
            file_path,
            root,
            notes_by_name,
        )
        if modified:
            write_lines(parent, new_lines)
            changed += 1

    return changed



def remove_reciprocal_up_links_for_missing_down(file_path: Path, root: Path, index: NotesIndex | None = None) -> int:
    """Prune stale reciprocal Parent links after Child links are manually removed."""

    file_path = file_path.resolve()
    root = root.resolve()
    index = index or build_notes_index(root)
    all_paths = index.paths
    notes_by_name = index.by_name

    if file_path not in index.path_set:
        return 0

    current_lines = read_lines(file_path)
    if file_path.name == "index.md":
        structural_links = outbound_links_from_index(current_lines)
        current_down_targets = {
            resolved.resolve()
            for _, target in structural_links
            if (resolved := resolve_existing_note_link(target, file_path.parent, root, notes_by_name)) is not None
        }
    else:
        if find_section(current_lines, "down")[0] < 0 and find_section(current_lines, "branch")[0] < 0:
            return 0
        current_down_targets = down_targets(current_lines, file_path, root, notes_by_name)
    changed = 0

    for child in all_paths:
        child = child.resolve()
        if child == file_path:
            continue
        if child in current_down_targets:
            continue

        child_lines = read_lines(child)
        has_up_link = False
        for _, target in parse_links(section_content(child_lines, "up")):
            resolved = resolve_existing_note_link(target, child.parent, root, notes_by_name)
            if resolved is not None and resolved.resolve() == file_path:
                has_up_link = True
                break
        if not has_up_link:
            continue

        new_lines, modified = remove_link_targets_from_section_lines(
            child_lines,
            "up",
            {file_path},
            child,
            root,
            notes_by_name,
        )
        if modified:
            write_lines(child, new_lines)
            changed += 1

    return changed


def dedupe_exact_link_lines(lines: list[str]) -> tuple[list[str], bool]:
    """Remove repeated identical Markdown link lines while preserving order."""

    seen: set[str] = set()
    result: list[str] = []
    changed = False
    for line in lines:
        stripped = line.strip()
        if LINK_RE.fullmatch(stripped):
            if stripped in seen:
                changed = True
                continue
            seen.add(stripped)
        result.append(line)
    return result, changed


def dedupe_section_link_targets(
    lines: list[str],
    name: str,
    note_path: Path,
    root: Path,
    notes_by_name: dict[str, list[Path]],
) -> tuple[list[str], bool]:
    """Collapse duplicate full-line links in one section by resolved target."""

    content = section_content(lines, name)
    if not content:
        return lines, False

    seen_targets: set[Path] = set()
    result: list[str] = []
    changed = False
    for line in content:
        stripped = line.strip()
        m = LINK_RE.fullmatch(stripped)
        if not m:
            result.append(line)
            continue
        resolved = resolve_existing_note_link(m.group(2), note_path.parent, root, notes_by_name)
        if resolved is None:
            result.append(line)
            continue
        resolved = resolved.resolve()
        if resolved in seen_targets:
            changed = True
            continue
        seen_targets.add(resolved)
        result.append(line)

    if not changed:
        return lines, False
    return replace_section(lines, name, result), True


def section_has_resolved_link(
    content: list[str],
    target_path: Path | None,
    from_dir: Path | None,
    root: Path | None,
    notes_by_name: dict[str, list[Path]] | None,
) -> bool:
    if target_path is None or from_dir is None or root is None or notes_by_name is None:
        return False
    wanted = target_path.resolve()
    for _, target in parse_links(content):
        resolved = resolve_existing_note_link(target, from_dir, root, notes_by_name)
        if resolved is not None and resolved.resolve() == wanted:
            return True
    return False


def add_link_to_section_lines(
    lines: list[str],
    name: str,
    link: str,
    target_path: Path | None = None,
    from_dir: Path | None = None,
    root: Path | None = None,
    notes_by_name: dict[str, list[Path]] | None = None,
) -> tuple[list[str], bool]:
    """Append *link* to a section if it is not already present.

    Existing duplicate link rows in the target section are also collapsed so a
    save-time sync cannot preserve or compound double-generated Child/Parent
    links.
    """

    if find_section(lines, name)[0] < 0:
        return list(lines), False
    content = section_content(lines, name)
    content, deduped = dedupe_exact_link_lines(content)
    if link in content or section_has_resolved_link(content, target_path, from_dir, root, notes_by_name):
        if deduped:
            return replace_section(lines, name, content), True
        return lines, False
    return replace_section(lines, name, content + [link]), True



def remove_link_targets_from_section_lines(
    lines: list[str],
    name: str,
    targets: set[Path],
    note_path: Path,
    root: Path,
    notes_by_name: dict[str, list[Path]],
) -> tuple[list[str], bool]:
    """Remove links whose resolved targets are in *targets* from a section."""

    start, end = find_section(lines, name)
    if start < 0:
        return list(lines), False

    targets = {target.resolve() for target in targets}
    modified = False
    new_content: list[str] = []
    in_fence = False

    for line in lines[start + 1: end]:
        stripped = line.strip()
        if stripped.startswith("```"):
            in_fence = not in_fence
            new_content.append(line)
            continue
        if in_fence or SEP_RE.match(stripped):
            new_content.append(line)
            continue

        line_modified = False

        def replacement(match: re.Match[str]) -> str:
            nonlocal line_modified
            resolved = resolve_existing_note_link(
                match.group(2),
                note_path.parent,
                root,
                notes_by_name,
            )
            if resolved is not None and resolved.resolve() in targets:
                line_modified = True
                return ""
            return match.group(0)

        new_line = LINK_RE.sub(replacement, line)
        if line_modified:
            modified = True
            if new_line.strip():
                new_content.append(new_line.rstrip())
        else:
            new_content.append(line)

    if not modified:
        return list(lines), False
    return lines[: start + 1] + new_content + lines[end:], True


def reparent_down_children(new_parent_path: Path, old_parent_path: Path, root: Path) -> int:
    """Make notes linked from new parent's Child section point to the new parent.

    This is used when a selected Child link is cut into a newly-created note:
    the selected linked notes must stop listing the old note as Parent and start
    listing the newly-created note instead.
    """

    new_parent_path = new_parent_path.resolve()
    old_parent_path = old_parent_path.resolve()
    root = root.resolve()

    all_paths = list(iter_notes(root))
    known_paths = {p.resolve() for p in all_paths}
    for path in sorted(root.rglob("*.md")):
        resolved = path.resolve()
        if path.is_file() and ".undo" not in path.parts and resolved not in known_paths:
            all_paths.append(resolved)
            known_paths.add(resolved)

    notes_by_name: dict[str, list[Path]] = {}
    for path in all_paths:
        notes_by_name.setdefault(path.name, []).append(path.resolve())

    if not new_parent_path.exists():
        return 0

    new_parent_lines = read_lines(new_parent_path)
    new_parent_title = note_title(new_parent_lines, new_parent_path)
    child_paths: list[Path] = []
    seen: set[Path] = set()
    for _, target in outbound_links_from_down(new_parent_lines):
        resolved = resolve_existing_note_link(target, new_parent_path.parent, root, notes_by_name)
        if resolved is None:
            continue
        resolved = resolved.resolve()
        if resolved == new_parent_path or resolved in seen:
            continue
        seen.add(resolved)
        child_paths.append(resolved)

    changed = 0
    for child_path in child_paths:
        child_lines = read_lines(child_path)
        new_lines, removed = remove_link_targets_from_section_lines(
            child_lines,
            "up",
            {old_parent_path},
            child_path,
            root,
            notes_by_name,
        )
        new_link = make_link_line(new_parent_path, new_parent_title, child_path.parent)
        new_lines, added = add_link_to_section_lines(
            new_lines, "up", new_link, new_parent_path, child_path.parent, root, notes_by_name
        )
        if removed or added:
            write_lines(child_path, new_lines)
            changed += 1

    return changed

def sync_reciprocal_links_for_file(file_path: Path, root: Path, index: NotesIndex | None = None) -> int:
    """Lightweight one-hop Parent/Child sync for one edited note.

    This intentionally avoids a full root rebuild: it reads the current note's
    Parent and Child sections, then touches only those linked counterpart notes.  It
    is used by save-time autosync; deletion is handled immediately in Vim by the
    realtime diff watcher before save.
    """

    file_path = file_path.resolve()
    root = root.resolve()
    if not file_path.exists() or not is_markdown_file(file_path):
        return 0

    index = index or build_notes_index(root, [file_path])
    notes_by_name = index.by_name

    lines = read_lines(file_path)
    current_title = note_title(lines, file_path)
    changed = 0

    structural_links = (
        outbound_links_from_index(lines)
        if file_path.name == "index.md"
        else outbound_links_from_down(lines)
    )
    for _, target in structural_links:
        target_path = resolve_existing_note_link(target, file_path.parent, root, notes_by_name)
        if target_path is None or target_path.resolve() == file_path:
            continue
        if target_path.name == "index.md":
            continue
        target_lines = read_lines(target_path)
        reciprocal = make_link_line(file_path, current_title, target_path.parent)
        new_lines, modified = add_link_to_section_lines(
            target_lines, "up", reciprocal, file_path, target_path.parent, root, notes_by_name
        )
        if modified:
            write_lines(target_path, new_lines)
            changed += 1

    return changed



def sync_parent_section_for_file(file_path: Path, root: Path, index: NotesIndex | None = None) -> int:
    """Rebuild one note's Parent section from other notes' Child links.

    Parent is derived data: a note lists B as Parent only when B's Child
    section links to the note.  Editing Parent itself must not create or remove
    Child links.
    """

    file_path = file_path.resolve()
    root = root.resolve()
    if not file_path.exists() or not is_markdown_file(file_path):
        return 0

    index = index or build_notes_index(root, [file_path])
    if file_path not in index.path_set:
        return 0

    lines = read_lines(file_path)
    if find_section(lines, "up")[0] < 0:
        return 0

    parent_paths: list[Path] = []
    seen: set[Path] = set()
    for possible_parent in index.paths:
        possible_parent = possible_parent.resolve()
        if possible_parent == file_path:
            continue
        parent_lines = read_lines(possible_parent)
        structural_links = (
            outbound_links_from_index(parent_lines)
            if possible_parent.name == "index.md"
            else outbound_links_from_down(parent_lines)
        )
        for _, target in structural_links:
            resolved = resolve_existing_note_link(target, possible_parent.parent, root, index.by_name)
            if resolved is not None and resolved.resolve() == file_path and possible_parent not in seen:
                seen.add(possible_parent)
                parent_paths.append(possible_parent)
                break

    new_up = build_multi_up(parent_paths, file_path, exact=True)
    new_lines = replace_section(lines, "up", new_up)
    if new_lines == lines:
        return 0
    write_lines(file_path, new_lines)
    return 1

def backlink_targets(
    lines: list[str],
    note_path: Path,
    root: Path,
    notes_by_name: dict[str, list[Path]],
) -> list[Path]:
    """Return resolved notes already listed in a BackLink section."""

    targets: list[Path] = []
    seen: set[Path] = set()
    for _, target in parse_links(section_content(lines, "backlink")):
        resolved = resolve_existing_note_link(target, note_path.parent, root, notes_by_name)
        if resolved is None:
            continue
        resolved = resolved.resolve()
        if resolved in seen:
            continue
        seen.add(resolved)
        targets.append(resolved)
    return targets


def sync_backlinks_for_file(file_path: Path, root: Path, index: NotesIndex | None = None) -> int:
    """Update BackLink sections for notes referenced from one note's body.

    This is the save-time counterpart to the full BackLink rebuild in
    ``update_up_sections``.  It adds the edited note to current body-link
    targets and removes it from stale BackLink sections when a body link was
    deleted.  When a referring note is also listed in the target's Parent
    section, Parent takes precedence and the duplicate BackLink is hidden.
    """

    file_path = file_path.resolve()
    root = root.resolve()
    if not file_path.exists() or not is_markdown_file(file_path):
        return 0

    index = index or build_notes_index(root, [file_path])
    all_paths = index.paths
    notes_by_name = index.by_name

    source_lines = read_lines(file_path)
    changed = 0
    seen_targets: set[Path] = set()
    desired_targets: set[Path] = set()

    for _, target in outbound_links_for_backlink(source_lines):
        target_path = resolve_existing_note_link(target, file_path.parent, root, notes_by_name)
        if target_path is None:
            continue
        target_path = target_path.resolve()
        if target_path == file_path or target_path in seen_targets:
            continue
        seen_targets.add(target_path)
        desired_targets.add(target_path)

        target_lines = read_lines(target_path)
        if find_section(target_lines, "backlink")[0] < 0:
            continue

        existing_backlink_targets = backlink_targets(
            target_lines,
            target_path,
            root,
            notes_by_name,
        )
        parent_targets = {p.resolve() for p in up_targets(
            target_lines, target_path, root, notes_by_name
        )}
        retained_targets = [
            p for p in existing_backlink_targets
            if p.resolve() not in parent_targets and p.resolve() != file_path
        ]
        if file_path not in parent_targets:
            retained_targets.append(file_path)

        new_back = build_back(
            retained_targets,
            target_path,
            section_content(target_lines, "backlink"),
            category_parents={file_path} if get_filetype(file_path) == "K" else set(),
        )
        new_lines = replace_section(target_lines, "backlink", new_back)
        if new_lines != target_lines:
            write_lines(target_path, new_lines)
            changed += 1

    for target_path in all_paths:
        target_path = target_path.resolve()
        if target_path == file_path:
            continue

        target_lines = read_lines(target_path)
        if find_section(target_lines, "backlink")[0] < 0:
            continue

        should_remove = target_path not in desired_targets
        if not should_remove:
            continue

        existing_backlink_targets = backlink_targets(
            target_lines,
            target_path,
            root,
            notes_by_name,
        )
        if file_path not in {p.resolve() for p in existing_backlink_targets}:
            continue

        new_backlink_targets = [
            p for p in existing_backlink_targets
            if p.resolve() != file_path
        ]
        parent_targets = {p.resolve() for p in up_targets(
            target_lines, target_path, root, notes_by_name
        )}
        new_backlink_targets = [
            p for p in new_backlink_targets if p.resolve() not in parent_targets
        ]
        new_back = build_back(
            new_backlink_targets,
            target_path,
            section_content(target_lines, "backlink"),
        )
        new_lines = replace_section(target_lines, "backlink", new_back)
        if new_lines != target_lines:
            write_lines(target_path, new_lines)
            changed += 1

    return changed

def update_up_sections(
    root: Path,
    prune_up_target: Path | None = None,
    exact_up: bool = False,
) -> int:
    """Scan all notes; rebuild Parent from Child and BackLink from body links."""

    root = root.resolve()
    prune_up_targets = {prune_up_target.resolve()} if prune_up_target else set()
    all_paths = list(iter_notes(root))
    notes_by_name: dict[str, list[Path]] = {}
    for path in all_paths:
        notes_by_name.setdefault(path.name, []).append(path.resolve())

    backlinks_children_of: dict[Path, list[Path]] = {}
    down_children_of: dict[Path, list[Path]] = {}
    lines_map: dict[Path, list[str]] = {}

    for p in all_paths:
        lines = read_lines(p)
        lines_map[p] = lines
        body_kids: list[Path] = []
        body_seen: set[Path] = set()
        for _, target in outbound_links_for_backlink(lines):
            resolved = resolve_existing_note_link(target, p.parent, root, notes_by_name)
            if resolved is None or resolved in body_seen:
                continue
            body_seen.add(resolved)
            body_kids.append(resolved)
        backlinks_children_of[p] = body_kids

        down_kids: list[Path] = []
        down_seen: set[Path] = set()
        structural_links = (
            outbound_links_from_index(lines)
            if p.name == "index.md"
            else outbound_links_from_down(lines)
        )
        for _, target in structural_links:
            resolved = resolve_existing_note_link(target, p.parent, root, notes_by_name)
            if resolved is None or resolved in down_seen:
                continue
            down_seen.add(resolved)
            down_kids.append(resolved)
        down_children_of[p] = down_kids

    backlinks_parents_of: dict[Path, list[Path]] = {p: [] for p in all_paths}
    for parent, kids in backlinks_children_of.items():
        for child in kids:
            if child in backlinks_parents_of:
                backlinks_parents_of[child].append(parent)

    down_parents_of: dict[Path, list[Path]] = {p: [] for p in all_paths}
    for parent, kids in down_children_of.items():
        for child in kids:
            if child in down_parents_of:
                down_parents_of[child].append(parent)

    changed = 0
    for p in all_paths:
        lines = lines_map[p]
        if is_expand_generated_t_note(p, lines):
            new_lines = lines
        else:
            new_lines = lines
            if find_section(new_lines, "up")[0] >= 0:
                parent_candidates = down_parents_of.get(p, [])
                current_up_targets = up_targets(new_lines, p, root, notes_by_name)
                new_up = build_multi_up(
                    parent_candidates,
                    p,
                    current_up_targets=current_up_targets,
                    prune_targets=prune_up_targets,
                    exact=True,
                )
                new_lines = replace_section(new_lines, "up", new_up)

            if find_section(new_lines, "backlink")[0] >= 0:
                backlinks_parents = sorted(set(backlinks_parents_of.get(p, [])))
                structural_parents = {parent.resolve() for parent in down_parents_of.get(p, [])}
                backlinks_parents = [
                    parent for parent in backlinks_parents
                    if parent.resolve() not in structural_parents
                ]
                existing_back = section_content(new_lines, "backlink")
                new_back = build_back(
                    backlinks_parents,
                    p,
                    existing_back,
                )
                new_lines = replace_section(new_lines, "backlink", new_back)

        if new_lines != lines:
            write_lines(p, new_lines)
            changed += 1
    return changed


# ---------------------------------------------------------------------------
# update_one: update titles + up for a single file (fast, for autosync)
# ---------------------------------------------------------------------------

def update_one(file_path: Path, root: Path) -> str:
    """Lightweight save-time sync for a single file."""
    file_path = file_path.resolve()
    root = root.resolve()

    changed_files: list[str] = []

    if is_managed_note(file_path, root) and update_titles_in_file(file_path):
        changed_files.append(file_path.name)

    index = build_notes_index(root, [file_path])

    parent_section_changed = sync_parent_section_for_file(file_path, root, index)
    if parent_section_changed:
        changed_files.append(f"parent:{parent_section_changed}")

    pruned_down_changed = remove_reciprocal_up_links_for_missing_down(file_path, root, index)
    pruned_changed = pruned_down_changed
    if pruned_changed:
        changed_files.append(f"pruned:{pruned_changed}")

    reciprocal_changed = sync_reciprocal_links_for_file(file_path, root, index)
    if reciprocal_changed:
        changed_files.append(f"reciprocal:{reciprocal_changed}")

    backlink_changed = sync_backlinks_for_file(file_path, root, index)
    if backlink_changed:
        changed_files.append(f"backlink:{backlink_changed}")

    if changed_files:
        return "yurii_PKM: updated " + ", ".join(changed_files)
    return "yurii_PKM: no changes"


# ---------------------------------------------------------------------------
# rename_prefix: ファイルのプレフィクスを変更し、全リンクを更新
# ---------------------------------------------------------------------------

def rename_prefix(old_path: Path, new_prefix: str, root: Path) -> str:
    """Rename old_path's prefix to new_prefix, update all Child/Back links in root.

    Returns a human-readable summary string.
    """
    old_path = old_path.resolve()
    root = root.resolve()

    if not old_path.exists():
        raise FileNotFoundError(f"File not found: {old_path}")
    if not is_markdown_file(old_path):
        raise ValueError(f"Not a markdown file: {old_path}")

    old_name = old_path.name          # e.g. "S_250101120000.md"
    old_stem = old_path.stem          # e.g. "S_250101120000"

    # プレフィクス部分（最初の '_' より前）と残り部分に分割
    if '_' in old_stem:
        _, rest = old_stem.split('_', 1)
    else:
        rest = old_stem

    new_stem = f"{new_prefix}_{rest}"
    new_name = f"{new_stem}.md"
    new_path = old_path.parent / new_name

    if new_path.exists():
        raise FileExistsError(f"Target already exists: {new_path}")

    # 1. ファイル自体をリネーム
    old_path.rename(new_path)

    # 2. リネームしたファイル自身のBackセクション内に旧名リンクが残っていれば更新
    #    (expand_s.py が生成するAノートの末尾などを想定)
    self_lines = read_lines(new_path)
    self_lines = _rewrite_link_target(self_lines, old_name, new_name)
    write_lines(new_path, self_lines)

    # 3. PKMルート配下の全.mdファイルのChild/Backリンクを更新
    changed: list[str] = []
    for p in iter_notes(root):
        if p.resolve() == new_path.resolve():
            continue
        lines = read_lines(p)
        new_lines = _rewrite_link_target(lines, old_name, new_name)
        if new_lines != lines:
            write_lines(p, new_lines)
            changed.append(p.name)

    summary_parts = [f"Renamed: {old_name} → {new_name}"]
    if changed:
        summary_parts.append(f"Updated links in: {', '.join(changed)}")
    else:
        summary_parts.append("No other files had links to update")
    return "\n".join(summary_parts)


def _rewrite_link_target(lines: list[str], old_name: str, new_name: str) -> list[str]:
    """Replace occurrences of old_name as a link target with new_name.

    Matches `](old_name)` patterns (exact filename, no path components).
    Also updates `[old_stem](...)` link text that equals the old stem.
    """
    old_stem = old_name[:-3] if old_name.endswith('.md') else old_name
    new_stem = new_name[:-3] if new_name.endswith('.md') else new_name

    # Matches [text](old_name) — the target filename must match exactly
    # (handles paths like `subdir/old_name` too by checking the basename)
    target_re = re.compile(
        r'(\[[^\]]*\]\()([^)]*?)(' + re.escape(old_name) + r')(\))',
    )
    # Also match bare old_stem as link text when target uses old_name
    text_re = re.compile(
        r'(\[)(' + re.escape(old_stem) + r')(\]\()([^)]*?)(' + re.escape(old_name) + r')(\))',
    )

    result = []
    for line in lines:
        # First pass: update link text if it equals old_stem
        new_line = text_re.sub(
            lambda m: m.group(1) + new_stem + m.group(3) + m.group(4) + new_name + m.group(6),
            line,
        )
        # Second pass: update any remaining target references
        new_line = target_re.sub(
            lambda m: m.group(1) + m.group(2) + new_name + m.group(4),
            new_line,
        )
        result.append(new_line)
    return result


def retitle_links(target_file: Path, root: Path, old_title: str, new_title: str) -> int:
    """Rename link text old_title -> new_title only for links targeting target_file."""
    target_resolved = target_file.resolve()
    root = root.resolve()
    all_paths = list(iter_notes(root))
    notes_by_name: dict[str, list[Path]] = {}
    for path in all_paths:
        notes_by_name.setdefault(path.name, []).append(path.resolve())
    changed_files = 0

    for p in all_paths:
        lines = read_lines(p)
        modified = False
        out: list[str] = []

        for line in lines:
            m = re.match(r'^(\s*)\[([^\]]+)\]\(([^)]+)\)(\s*)$', line)
            if not m:
                out.append(line)
                continue
            text = m.group(2)
            rel_target = m.group(3)
            if text != old_title:
                out.append(line)
                continue
            resolved = resolve_existing_note_link(rel_target, p.parent, root, notes_by_name)
            if resolved is None or resolved.resolve() != target_resolved:
                out.append(line)
                continue
            modified = True
            out.append(f"{m.group(1)}[{new_title}]({rel_target}){m.group(4)}")

        for section in ("up", "down", "back"):
            out, deduped = dedupe_section_link_targets(out, section, p, root, notes_by_name)
            modified = modified or deduped

        if modified:
            write_lines(p, out)
            changed_files += 1

    return changed_files


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print("usage:\n"
              "  yurii_pkm_sync.py update ROOT\n"
              "  yurii_pkm_sync.py update_one FILE ROOT\n"
              "  yurii_pkm_sync.py update_titles FILE\n"
              "  yurii_pkm_sync.py retitle_links FILE ROOT OLD_TITLE NEW_TITLE\n"
              "  yurii_pkm_sync.py rename_prefix FILE NEW_PREFIX ROOT",
              file=sys.stderr)
        return 2

    mode = argv[1]

    if mode == "update":
        root = Path(argv[2])
        if not root.exists():
            root.mkdir(parents=True, exist_ok=True)
        title_changed = 0
        for p in iter_notes(root):
            if update_titles_in_file(p):
                title_changed += 1
        structural_changed = update_up_sections(root)
        print(
            f"yurii_PKM: updated {title_changed} title file(s), "
            f"{structural_changed} structural file(s) under {root}"
        )
        return 0

    if mode == "update_one":
        if len(argv) < 4:
            print("usage: yurii_pkm_sync.py update_one FILE ROOT", file=sys.stderr)
            return 2
        file_path = Path(argv[2])
        root = Path(argv[3])
        print(update_one(file_path, root))
        return 0

    if mode == "reparent_down_children":
        if len(argv) < 5:
            print("usage: yurii_pkm_sync.py reparent_down_children NEW_PARENT OLD_PARENT ROOT", file=sys.stderr)
            return 2
        changed = reparent_down_children(Path(argv[2]), Path(argv[3]), Path(argv[4]))
        print(f"yurii_PKM: reparented {changed} child parent link(s)")
        return 0

    if mode == "update_titles":
        path = Path(argv[2])
        changed = update_titles_in_file(path)
        print(f"yurii_PKM: {'updated' if changed else 'no changes in'} {path.name}")
        return 0

    if mode == "retitle_links":
        if len(argv) < 6:
            print("usage: yurii_pkm_sync.py retitle_links FILE ROOT OLD_TITLE NEW_TITLE",
                  file=sys.stderr)
            return 2
        target_file = Path(argv[2])
        root = Path(argv[3])
        old_title = argv[4]
        new_title = argv[5]
        changed = retitle_links(target_file, root, old_title, new_title)
        print(f"yurii_PKM: retitled {changed} file(s)")
        return 0

    if mode == "nf":
        if len(argv) < 4:
            print("usage: yurii_pkm_sync.py nf FILE ROOT", file=sys.stderr)
            return 2
        file_path = Path(argv[2])
        root = Path(argv[3])
        new_f = create_f_and_link(file_path, root)
        print(str(new_f))
        return 0

    if mode == "rename_prefix":
        if len(argv) < 5:
            print("usage: yurii_pkm_sync.py rename_prefix FILE NEW_PREFIX ROOT",
                  file=sys.stderr)
            return 2
        old_file   = Path(argv[2])
        new_prefix = argv[3]
        root       = Path(argv[4])
        try:
            result = rename_prefix(old_file, new_prefix, root)
            print(result)
            # 新ファイルパスを最終行に出力（Vim 側がパースする）
            old_stem = old_file.stem
            rest = old_stem.split("_", 1)[1] if "_" in old_stem else old_stem
            new_path = old_file.parent / f"{new_prefix}_{rest}.md"
            print(f"NEW_PATH:{new_path}")
        except (FileNotFoundError, FileExistsError, ValueError) as e:
            print(f"Error: {e}", file=sys.stderr)
            return 1
        return 0

    print(f"unsupported mode: {mode}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
