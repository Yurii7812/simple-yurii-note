# legacy

現役では**ない**旧エンジン置き場。編集時は原則ここを読まない（トークン節約）。

- `simple_yurii_note_sync.py` … **v1 エンジン**（`g:simple_yurii_note_format ==# 'v1'`
  のときだけ使う）。既定は v2 で、実体は `../python/note_format_v2.py` の
  `simple_sync()`。ノート実体は v2 のみなので通常は読まれない。
  テスト: `../python/test_yurii_pkm_sync.py`。
  パスは `plugin/simple_yurii_note.vim` が `s:plugin_root . '/legacy/...'` で参照する。

消すのは仕様変更（v1 サポート廃止）になるので、本人の確認なしに削除しない。
