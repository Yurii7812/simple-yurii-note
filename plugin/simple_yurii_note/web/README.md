# simple_yurii_note web

ブラウザから `~/files/yurii-note` を直接読み書きする Obsidian 風アプリ。
サーバーは使わない（File System Access API）。詳細は `../docs/08-web.md`。

## 使い方

1. **Brave / Chrome** で `index.html` を開く（Vim からは `:SimpleWeb` / `\w`）。
2. 「vault を開く」→ `~/files/yurii-note` を選ぶ。
3. 一覧からノートを開いて編集。Ctrl+S で保存（JS 版 sync が走る）。

## 開発

```bash
npm install      # 初回
npm run build    # src/*.js -> bundle.js
npm test         # headless Chromium で E2E（JS sync == Python sync）
```

`bundle.js` はコミットする。`node_modules/` はコミットしない。
`src/sync.js` は `../python/note_format_v2.py` の `simple_sync()` の移植。
**挙動を変えたら `npm test` と `test/sync_diff.mjs`（README 参照）を必ず回す。**
