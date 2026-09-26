#!/usr/bin/env python3
"""
fsearch_tui_jp_inline.py
- 画面を切り替えずに検索語を編集できる全文検索 TUI
- 日本語を含む検索語を保持したまま編集し、Enter で確定検索
- 一覧とプレビューでヒット箇所をハイライト

使い方:
  python3 fsearch_tui_jp_inline.py <dir> [tmpfile] [initial_query]
"""

import sys
import os
import re
import curses
import unicodedata
import datetime
import locale
import time
from functools import lru_cache
from typing import List, Dict, Optional, Tuple

locale.setlocale(locale.LC_ALL, '')

TEXT_EXTENSIONS = {
    '.md', '.txt', '.rst', '.csv', '.tsv',
    '.yaml', '.yml', '.toml', '.ini', '.conf',
    '.py', '.sh', '.js', '.html', '.css', '.json',
    '.tex', '.org', '.wiki',
}

SKIP_DIRS = {
    '.git', '.hg', '.svn', '.idea', '.vscode', '__pycache__',
    'node_modules', '.mypy_cache', '.pytest_cache', '.venv', 'venv',
}
MAX_FILE_BYTES = 1_000_000
SORT_MODES = ['関連度', 'ファイル名', '日付']


def parse_date(s: str):
    for fmt in ('%Y-%m-%d', '%Y/%m/%d', '%Y-%m', '%Y/%m', '%Y'):
        try:
            return datetime.datetime.strptime(s, fmt).date()
        except ValueError:
            pass
    return None


def parse_file(fpath: str):
    try:
        if os.path.getsize(fpath) > MAX_FILE_BYTES:
            return None
        with open(fpath, 'r', encoding='utf-8', errors='ignore') as f:
            raw = f.read()
    except OSError:
        return None

    lines = raw.splitlines()
    title = ''
    date = None

    if lines and lines[0].strip() == '---':
        end = None
        for i, line in enumerate(lines[1:], 1):
            if line.strip() in ('---', '...'):
                end = i
                break
        if end:
            for line in lines[1:end]:
                m = re.match(r'^title\s*:\s*(.+)', line)
                if m:
                    title = m.group(1).strip().strip('"\'')
                m = re.match(r'^date\s*:\s*(.+)', line)
                if m:
                    date = parse_date(m.group(1).strip().strip('"\''))

    if not date:
        try:
            date = datetime.date.fromtimestamp(os.path.getmtime(fpath))
        except OSError:
            date = datetime.date.min

    return {
        'path': fpath,
        'content': raw.lower(),
        'title': title,
        'date': date,
        'lines': lines,
    }


def scan_dir(directory: str):
    files = []
    for root, dirs, fnames in os.walk(directory):
        dirs[:] = sorted(d for d in dirs if not d.startswith('.') and d not in SKIP_DIRS)
        for fname in sorted(fnames):
            if fname.startswith('.'):
                continue
            ext = os.path.splitext(fname)[1].lower()
            if ext not in TEXT_EXTENSIONS:
                continue
            fpath = os.path.join(root, fname)
            info = parse_file(fpath)
            if info:
                files.append(info)
    return files


def parse_query(query_str: str):
    result = {
        'and_terms': [],
        'or_groups': [],
        'not_terms': [],
        'title_terms': [],
        'file_terms': [],
        'date_from': None,
        'date_to': None,
    }
    tokens = query_str.strip().split()
    for tok in tokens:
        tl = tok.lower()
        if tl.startswith('from:'):
            d = parse_date(tok[5:])
            if d:
                result['date_from'] = d
        elif tl.startswith('to:'):
            d = parse_date(tok[3:])
            if d:
                result['date_to'] = d
        elif tl.startswith('title:'):
            val = tok[6:].lower()
            if '|' in val:
                result['or_groups'].append(('title', [x for x in val.split('|') if x]))
            elif val:
                result['title_terms'].append(val)
        elif tl.startswith('file:'):
            val = tok[5:].lower()
            if '|' in val:
                result['or_groups'].append(('file', [x for x in val.split('|') if x]))
            elif val:
                result['file_terms'].append(val)
        elif tl.startswith('-') and len(tl) > 1:
            result['not_terms'].append(tl[1:])
        elif '|' in tl:
            terms = [x for x in tl.split('|') if x]
            if terms:
                result['or_groups'].append(('content', terms))
        elif tl:
            result['and_terms'].append(tl)
    return result


def has_real_query(q: dict) -> bool:
    return any([
        q['and_terms'], q['or_groups'], q['not_terms'], q['title_terms'], q['file_terms'],
        q['date_from'], q['date_to'],
    ])


def matches(info: dict, q: dict) -> bool:
    content = info['content']
    title = info['title'].lower()
    fname = os.path.basename(info['path']).lower()
    date = info['date']

    for term in q['and_terms']:
        if term not in content:
            return False
    for term in q['not_terms']:
        if term in content:
            return False
    for term in q['title_terms']:
        if term not in title:
            return False
    for term in q['file_terms']:
        if term not in fname:
            return False
    for field, terms in q['or_groups']:
        if field == 'content':
            if not any(t in content for t in terms):
                return False
        elif field == 'title':
            if not any(t in title for t in terms):
                return False
        elif field == 'file':
            if not any(t in fname for t in terms):
                return False
    if q['date_from'] and date < q['date_from']:
        return False
    if q['date_to'] and date > q['date_to']:
        return False
    return True


def score(info: dict, q: dict) -> int:
    content = info['content']
    title = info['title'].lower()
    fname = os.path.basename(info['path']).lower()
    s = 0

    for term in q['and_terms']:
        if term in content:
            s += 3
        if term in title:
            s += 8
        if term in fname:
            s += 5
    for term in q['title_terms']:
        if term in title:
            s += 12
    for term in q['file_terms']:
        if term in fname:
            s += 10
    for field, terms in q['or_groups']:
        for term in terms:
            if field == 'content' and term in content:
                s += 2
            elif field == 'title' and term in title:
                s += 8
            elif field == 'file' and term in fname:
                s += 6

    if s == 0 and has_real_query(q):
        s = 1
    return s


def hit_lines(info: dict, q: dict):
    all_terms = positive_terms(q, include_title=False, include_file=False)
    if not all_terms:
        return []
    hits = []
    for i, line in enumerate(info['lines'], 1):
        ll = line.lower()
        for term in all_terms:
            if term in ll:
                hits.append((i, line))
                break
    return hits


@lru_cache(maxsize=4096)
def char_width(ch: str) -> int:
    return 2 if unicodedata.east_asian_width(ch) in ('W', 'F') else 1


@lru_cache(maxsize=16384)
def str_width(s: str) -> int:
    return sum(char_width(ch) for ch in s)


def is_narrow_text(s: str) -> bool:
    return all(char_width(ch) == 1 for ch in s)


def clip_str(s: str, max_width: int) -> str:
    if max_width <= 0:
        return ''
    w = 0
    result = ''
    for ch in s:
        cw = char_width(ch)
        if w + cw > max_width:
            break
        result += ch
        w += cw
    return result


def pad_to_width(s: str, width: int) -> str:
    clipped = clip_str(s, width)
    pad = max(0, width - str_width(clipped))
    return clipped + (' ' * pad)


def positive_terms(q: dict, include_title: bool = True, include_file: bool = True) -> List[str]:
    terms: List[str] = []
    terms.extend(q['and_terms'])
    if include_title:
        terms.extend(q['title_terms'])
    if include_file:
        terms.extend(q['file_terms'])
    for field, group in q['or_groups']:
        if field == 'content':
            terms.extend(group)
        elif field == 'title' and include_title:
            terms.extend(group)
        elif field == 'file' and include_file:
            terms.extend(group)
    uniq = []
    seen = set()
    for t in sorted((t for t in terms if t), key=len, reverse=True):
        if t not in seen:
            uniq.append(t)
            seen.add(t)
    return uniq


def match_spans(text: str, terms: List[str]) -> List[Tuple[int, int]]:
    if not text or not terms:
        return []
    low = text.lower()
    spans: List[Tuple[int, int]] = []
    for term in terms:
        if not term:
            continue
        start = 0
        while True:
            idx = low.find(term, start)
            if idx == -1:
                break
            spans.append((idx, idx + len(term)))
            start = idx + max(1, len(term))
    if not spans:
        return []
    spans.sort()
    merged = [list(spans[0])]
    for s, e in spans[1:]:
        last = merged[-1]
        if s <= last[1]:
            if e > last[1]:
                last[1] = e
        else:
            merged.append([s, e])
    return [(s, e) for s, e in merged]


def style_mask(text: str, terms: List[str], base_attr: int, hl_attr: int) -> List[int]:
    attrs = [base_attr] * len(text)
    for s, e in match_spans(text, terms):
        for i in range(max(0, s), min(len(text), e)):
            attrs[i] = hl_attr
    return attrs


def safe_add(row: int, col: int, text: str, width: int, add_func, attr: int = curses.A_NORMAL):
    if width <= 0:
        return
    s = pad_to_width(text, width)
    if is_narrow_text(s):
        try:
            add_func(row, col, s[:width], attr)
        except curses.error:
            pass
        return
    x = col
    for ch in s:
        cw = char_width(ch)
        if x + cw > col + width:
            break
        try:
            add_func(row, x, ch, attr)
        except curses.error:
            pass
        x += cw


def safe_add_highlight(row: int, col: int, text: str, width: int, add_func, base_attr: int, hl_attr: int, terms: List[str]):
    if width <= 0:
        return
    if not terms:
        safe_add(row, col, text, width, add_func, base_attr)
        return

    s = pad_to_width(text, width)
    attrs = style_mask(s, terms, base_attr, hl_attr)

    # Fast path for common ASCII/narrow strings: draw contiguous runs that share
    # the same attribute instead of crossing Python/curses per character.
    if is_narrow_text(s):
        run_start = 0
        while run_start < min(len(s), width):
            attr = attrs[run_start]
            run_end = run_start + 1
            while run_end < min(len(s), width) and attrs[run_end] == attr:
                run_end += 1
            try:
                add_func(row, col + run_start, s[run_start:run_end], attr)
            except curses.error:
                pass
            run_start = run_end
        return

    x = col
    for i, ch in enumerate(s):
        cw = char_width(ch)
        if x + cw > col + width:
            break
        try:
            add_func(row, x, ch, attrs[i])
        except curses.error:
            pass
        x += cw


def visible_window_for_cursor(text: str, cursor_pos: int, width: int) -> Tuple[str, int, int]:
    if width <= 0:
        return '', 0, 0
    cursor_pos = max(0, min(len(text), cursor_pos))
    if str_width(text) <= width:
        return text, 0, str_width(text[:cursor_pos])

    start = 0
    while start < cursor_pos and str_width(text[start:cursor_pos]) > max(1, width - 2):
        start += 1

    end = start
    used = 0
    while end < len(text):
        cw = char_width(text[end])
        if used + cw > width:
            break
        used += cw
        end += 1

    visible = text[start:end]
    cursor_x = str_width(text[start:cursor_pos])
    return visible, start, cursor_x



def read_key(stdscr):
    """Read a key and coalesce raw escape sequences for cursor keys.

    Some Vim terminal/TERM combinations leak arrow-key bytes as ``ESC [ A``
    instead of a curses KEY_* value.  If those bytes are handled one-by-one,
    the printable tail (for example ``[A``) can be inserted into the query.
    """
    try:
        key = stdscr.get_wch()
    except KeyboardInterrupt:
        raise
    except curses.error:
        return None

    if key != '\x1b':
        return key

    seq = ''
    stdscr.nodelay(True)
    deadline = time.monotonic() + 0.05
    try:
        while time.monotonic() < deadline and len(seq) < 8:
            try:
                nxt = stdscr.get_wch()
            except curses.error:
                time.sleep(0.005)
                continue
            if isinstance(nxt, str):
                seq += nxt
                if seq in ('[A', 'OA'):
                    return curses.KEY_UP
                if seq in ('[B', 'OB'):
                    return curses.KEY_DOWN
                if seq in ('[C', 'OC'):
                    return curses.KEY_RIGHT
                if seq in ('[D', 'OD'):
                    return curses.KEY_LEFT
                if seq in ('[H', 'OH', '[1~'):
                    return curses.KEY_HOME
                if seq in ('[F', 'OF', '[4~'):
                    return curses.KEY_END
                if seq in ('[3~',):
                    return curses.KEY_DC
                if seq in ('[5~',):
                    return curses.KEY_PPAGE
                if seq in ('[6~',):
                    return curses.KEY_NPAGE
            else:
                return nxt
    finally:
        stdscr.nodelay(False)

    return '\x1b'

def run_tui(stdscr, directory: str, all_files: List[dict], initial_query: str = ''):
    curses.set_escdelay(25)
    curses.use_default_colors()
    stdscr.keypad(True)
    try:
        curses.curs_set(0)
    except curses.error:
        pass
    curses.init_pair(1, curses.COLOR_BLACK, curses.COLOR_CYAN)   # selected row
    curses.init_pair(2, curses.COLOR_YELLOW, -1)                  # hits
    curses.init_pair(3, curses.COLOR_CYAN, -1)                    # line numbers
    curses.init_pair(4, curses.COLOR_GREEN, -1)                   # headers
    curses.init_pair(5, curses.COLOR_WHITE, curses.COLOR_BLUE)    # help
    curses.init_pair(6, curses.COLOR_BLACK, curses.COLOR_YELLOW)  # query edit

    query_str = initial_query
    edit_buf = query_str
    edit_cursor = len(edit_buf)
    editing = False

    sort_idx = 0
    sort_asc = [False, True, False]
    cursor = 0
    list_offset = 0
    results: List[Tuple[dict, int]] = []
    preview_cache: Dict[Tuple[str, str], List[Tuple[int, str]]] = {}
    last_q = parse_query(query_str)
    last_terms_content = positive_terms(last_q, include_title=False, include_file=False)
    last_terms_meta = positive_terms(last_q, include_title=True, include_file=True)

    def do_search(reset_scroll: bool = True):
        nonlocal results, cursor, list_offset, last_q, last_terms_content, last_terms_meta
        q = parse_query(query_str)
        last_q = q
        last_terms_content = positive_terms(q, include_title=False, include_file=False)
        last_terms_meta = positive_terms(q, include_title=True, include_file=True)

        if not has_real_query(q):
            results = []
            if reset_scroll:
                cursor = 0
                list_offset = 0
            return

        matched: List[Tuple[dict, int]] = []
        for info in all_files:
            if matches(info, q):
                sc = score(info, q) if sort_idx == 0 else 0
                matched.append((info, sc))

        if sort_idx == 0:
            matched.sort(key=lambda x: x[1], reverse=not sort_asc[0])
        elif sort_idx == 1:
            matched.sort(key=lambda x: os.path.basename(x[0]['path']).lower(), reverse=not sort_asc[1])
        else:
            matched.sort(key=lambda x: x[0]['date'], reverse=not sort_asc[2])

        results = matched
        if reset_scroll:
            cursor = 0
            list_offset = 0
        else:
            if results:
                cursor = min(cursor, len(results) - 1)
                list_offset = min(list_offset, cursor)
            else:
                cursor = 0
                list_offset = 0

    do_search()

    while True:
        stdscr.erase()
        h, w = stdscr.getmaxyx()

        HEADER_ROW = 0
        META_ROW = 1
        LIST_TOP = 3
        PREVIEW_H = min(10, max(4, h // 4))
        LIST_H = max(3, h - LIST_TOP - PREVIEW_H - 2)
        PREVIEW_TOP = LIST_TOP + LIST_H + 1

        def add_func(r, c, t, a):
            if 0 <= r < h and 0 <= c < w:
                stdscr.addstr(r, c, t, a)

        query_label = ' Query: '
        query_prefix_w = str_width(query_label)
        query_box_w = max(10, w - query_prefix_w - 1)
        query_attr = curses.color_pair(6) if editing else curses.color_pair(5)
        safe_add(HEADER_ROW, 0, query_label, query_prefix_w, add_func, curses.color_pair(4) | curses.A_BOLD)

        current_for_draw = edit_buf if editing else query_str
        visible_query, win_start, cursor_x = visible_window_for_cursor(current_for_draw, edit_cursor if editing else len(current_for_draw), query_box_w)
        safe_add(HEADER_ROW, query_prefix_w, visible_query or ' ', query_box_w, add_func, query_attr)

        if editing:
            hint = ' Enter:確定  Esc:キャンセル  ←→:移動  BS/Del:削除 '
        else:
            hint = ' / or i:編集  s:ソート  S:昇降順  Enter:開く  q:終了 '
        safe_add(META_ROW, 0, hint, w - 1, add_func, curses.color_pair(5))

        sort_labels = []
        for i, name in enumerate(SORT_MODES):
            asc_mark = '↑' if sort_asc[i] else '↓'
            sort_labels.append(f'[{name}{asc_mark}]' if i == sort_idx else f' {name}{asc_mark} ')
        safe_add(2, 0, ' '.join(sort_labels), w - 1, add_func, curses.color_pair(4))

        # list header
        path_w = max(16, int(w * 0.44))
        title_w = max(10, int(w * 0.24))
        date_w = 12
        score_w = 5
        total_w = path_w + title_w + date_w + score_w + 4
        if total_w > w - 1:
            overflow = total_w - (w - 1)
            path_w = max(12, path_w - overflow)
        x = 0
        safe_add(LIST_TOP - 1, x, 'FILE', path_w, add_func, curses.color_pair(4) | curses.A_BOLD); x += path_w + 1
        safe_add(LIST_TOP - 1, x, 'TITLE', title_w, add_func, curses.color_pair(4) | curses.A_BOLD); x += title_w + 1
        safe_add(LIST_TOP - 1, x, 'DATE', date_w, add_func, curses.color_pair(4) | curses.A_BOLD); x += date_w + 1
        safe_add(LIST_TOP - 1, x, 'SC', score_w, add_func, curses.color_pair(4) | curses.A_BOLD)

        visible_rows = max(1, LIST_H - 1)
        for i in range(visible_rows):
            idx = list_offset + i
            if idx >= len(results):
                break
            info, sc = results[idx]
            rel = os.path.relpath(info['path'], directory)
            titl = info['title'] or ''
            date = str(info['date']) if info['date'] != datetime.date.min else ''
            row_attr = curses.color_pair(1) if idx == cursor else curses.A_NORMAL
            hl_attr = row_attr | curses.color_pair(2) | curses.A_BOLD
            x = 0
            safe_add_highlight(LIST_TOP + i, x, rel, path_w, add_func, row_attr, hl_attr, last_terms_meta); x += path_w + 1
            safe_add_highlight(LIST_TOP + i, x, titl, title_w, add_func, row_attr, hl_attr, last_terms_meta); x += title_w + 1
            safe_add_highlight(LIST_TOP + i, x, date, date_w, add_func, row_attr, hl_attr, last_terms_meta); x += date_w + 1
            safe_add(LIST_TOP + i, x, str(sc), score_w, add_func, row_attr)

        safe_add(PREVIEW_TOP - 1, 0, f' {len(results)} files ', w - 1, add_func, curses.color_pair(4))

        if results and 0 <= cursor < len(results):
            info = results[cursor][0]
            cache_key = (info['path'], query_str)
            if cache_key not in preview_cache:
                preview_cache[cache_key] = hit_lines(info, last_q)
            hits = preview_cache[cache_key]
            rel = os.path.relpath(info['path'], directory)
            safe_add(PREVIEW_TOP, 0, f' ヒット: {rel} ', w - 1, add_func, curses.color_pair(4) | curses.A_BOLD)
            for pi, (lno, line) in enumerate(hits[:max(0, PREVIEW_H - 1)]):
                row = PREVIEW_TOP + 1 + pi
                if row >= h:
                    break
                lno_str = f'{lno:>4}: '
                safe_add(row, 0, lno_str, len(lno_str), add_func, curses.color_pair(3))
                safe_add_highlight(row, len(lno_str), line, max(1, w - len(lno_str) - 1), add_func,
                                   curses.A_NORMAL, curses.color_pair(2) | curses.A_BOLD, last_terms_content)

        if editing:
            try:
                curses.curs_set(1)
            except curses.error:
                pass
            cursor_col = query_prefix_w + min(query_box_w - 1, cursor_x)
            stdscr.move(HEADER_ROW, max(query_prefix_w, min(w - 1, cursor_col)))
        else:
            try:
                curses.curs_set(0)
            except curses.error:
                pass

        stdscr.refresh()

        try:
            key = read_key(stdscr)
        except KeyboardInterrupt:
            return None
        if key is None:
            continue

        if editing:
            if key in ('\n', '\r'):
                query_str = edit_buf
                do_search()
                editing = False
            elif key in (27, '\x1b'):
                edit_buf = query_str
                edit_cursor = len(edit_buf)
                editing = False
            elif key in (curses.KEY_LEFT,):
                if edit_cursor > 0:
                    edit_cursor -= 1
            elif key in (curses.KEY_RIGHT,):
                if edit_cursor < len(edit_buf):
                    edit_cursor += 1
            elif key in (curses.KEY_HOME,):
                edit_cursor = 0
            elif key in (curses.KEY_END,):
                edit_cursor = len(edit_buf)
            elif key in (curses.KEY_BACKSPACE, '\x7f', 8):
                if edit_cursor > 0:
                    edit_buf = edit_buf[:edit_cursor - 1] + edit_buf[edit_cursor:]
                    edit_cursor -= 1
            elif key in (curses.KEY_DC,):
                if edit_cursor < len(edit_buf):
                    edit_buf = edit_buf[:edit_cursor] + edit_buf[edit_cursor + 1:]
            elif key == '\x01':  # Ctrl-A
                edit_cursor = 0
            elif key == '\x05':  # Ctrl-E
                edit_cursor = len(edit_buf)
            elif key == '\x15':  # Ctrl-U
                edit_buf = ''
                edit_cursor = 0
            elif isinstance(key, str) and key.isprintable():
                edit_buf = edit_buf[:edit_cursor] + key + edit_buf[edit_cursor:]
                edit_cursor += len(key)
            continue

        if key in ('q', 'Q'):
            return None
        elif key in ('/', 'i', 'I'):
            editing = True
            edit_buf = query_str
            edit_cursor = len(edit_buf)
        elif key == 'c':
            query_str = ''
            edit_buf = ''
            edit_cursor = 0
            do_search()
        elif key == 's':
            sort_idx = (sort_idx + 1) % len(SORT_MODES)
            do_search(reset_scroll=False)
        elif key == 'S':
            sort_asc[sort_idx] = not sort_asc[sort_idx]
            do_search(reset_scroll=False)
        elif key in (curses.KEY_UP, 'k'):
            if cursor > 0:
                cursor -= 1
                if cursor < list_offset:
                    list_offset = cursor
        elif key in (curses.KEY_DOWN, 'j'):
            if cursor < len(results) - 1:
                cursor += 1
                if cursor >= list_offset + visible_rows:
                    list_offset = cursor - visible_rows + 1
        elif key in (curses.KEY_NPAGE,):
            if results:
                cursor = min(len(results) - 1, cursor + max(1, visible_rows - 1))
                list_offset = min(cursor, max(0, len(results) - visible_rows))
        elif key in (curses.KEY_PPAGE,):
            if results:
                cursor = max(0, cursor - max(1, visible_rows - 1))
                list_offset = min(list_offset, cursor)
        elif key in ('\n', '\r'):
            if results:
                return results[cursor][0]['path']
        elif key == curses.KEY_RESIZE:
            pass


def main():
    if len(sys.argv) < 2:
        print(f'Usage: {sys.argv[0]} <dir> [tmpfile] [initial_query]', file=sys.stderr)
        sys.exit(1)

    directory = sys.argv[1]
    tmpfile = sys.argv[2] if len(sys.argv) >= 3 else None
    initial_query = sys.argv[3] if len(sys.argv) >= 4 else ''

    if not os.path.isdir(directory):
        print(f'Error: {directory} is not a directory', file=sys.stderr)
        sys.exit(1)

    print('ファイルを読み込み中...', end='', flush=True)
    all_files = scan_dir(directory)
    print(f'\r{len(all_files)} ファイル読み込み完了      ')

    selected = curses.wrapper(run_tui, directory, all_files, initial_query)

    if selected:
        if tmpfile:
            with open(tmpfile, 'w', encoding='utf-8') as f:
                f.write(selected)
        else:
            print(selected)


if __name__ == '__main__':
    main()
