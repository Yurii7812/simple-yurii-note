import curses

import fsearch_tui


class FakeScreen:
    def __init__(self, keys):
        self.keys = list(keys)
        self.nodelay_values = []

    def get_wch(self):
        if not self.keys:
            raise curses.error
        key = self.keys.pop(0)
        if isinstance(key, BaseException):
            raise key
        return key

    def nodelay(self, value):
        self.nodelay_values.append(value)


def test_read_key_maps_raw_arrow_escape_sequence():
    screen = FakeScreen(['\x1b', '[', 'A'])

    assert fsearch_tui.read_key(screen) == curses.KEY_UP
    assert screen.nodelay_values == [True, False]


def test_safe_add_highlight_uses_bulk_draw_for_unhighlighted_ascii():
    calls = []

    def add_func(row, col, text, attr):
        calls.append((row, col, text, attr))

    fsearch_tui.safe_add_highlight(1, 2, 'abc', 5, add_func, 10, 20, [])

    assert calls == [(1, 2, 'abc  ', 10)]
