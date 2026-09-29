# simple_yurii_note app

ノートを閲覧・編集するシンプルなアプリ。

- **既定: Electron デスクトップアプリ**。vault は `~/files/yurii-note`（`PKM_ROOT` で変更）、
  フォルダ選択は不要。保存時に Python の sync（`../python/note_format_v2.py`）を呼ぶ。
- **ブラウザ版**（Brave/Chrome）: `index.html` を直接開く。File System Access API で
  vault を選び、JS 移植の sync を使う。
- ライトが既定。🌙/☀ でダーク切替。CodeMirror 6 のライブプレビュー、自動保存。

## 起動

```bash
npm install        # 初回
npm run app        # Electron
# または index.html を Brave/Chrome で開く
```

Vim からは `:SimpleWeb` / `\w`。詳細は `../docs/08-web.md`。

## 開発

```bash
npm run build      # src/*.js -> bundle.js
npm test           # fsapi (Node+Python) と browser_smoke (headless Chromium)
```

`bundle.js` はコミットする。`node_modules/` はコミットしない。
