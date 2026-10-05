# 08 アプリ (Electron / ブラウザ)

ノートを閲覧・編集する。**既定は Electron デスクトップアプリ**。
vault のパスは固定でフォルダ選択は不要。ブラウザでも開ける（File System Access API）。

## 起動

- Vim から: `:SimpleWeb` または `\A`。
  - Electron（`web/node_modules/.bin/electron`）があればそれを起動。
    現在の PKM ルートを `PKM_ROOT` で渡す。
  - 無ければブラウザで `web/index.html` を開くフォールバック（ただし下記のとおり
    実質 Chrome 系のみ）。
- 直接: `cd web && npm run app`、または `web/bin/simple-yurii-note-app.sh [VAULT_DIR]`。
  - アプリメニュー用: `~/.local/share/applications/simple-yurii-note.desktop`
    （`~/.local/bin/simple-yurii-note-app` 経由）。
- `\w` は other.vim の `:wa`（保存）なので使わない。

## 見た目

- **ライトが既定**。ツールバー右の 🌙/☀ でダークと切替（`localStorage` に記憶）。
- Obsidian 風の装飾はしない。左に一覧、中央に編集、右にリンク。できる限りシンプル。

## 編集モデル（ノートを壊さない）

本文だけをライブプレビュー（CodeMirror 6、生 Markdown を保持）で編集する。
front matter はタイトル欄、`### Parent` は右パネルのリスト、`### BackLink` は読み取り専用。
保存時に `### Parent` / `### BackLink` の見出しを WYSIWYG に食わせないので壊れない。

## 保存と同期

- **自動保存**（既定。編集が止まって約 1.2 秒。タブ切替/非表示/移動時にも保存）。手動は `Ctrl+S`。
- 削除（`.trash` へ移動）の直前にも保留中の編集を書き出す（未保存分が消えないように）。
- **同期の正は Python** `note_format_v2.py` の `simple_sync()`。
  - Electron: main プロセスが保存後に `python3 note_format_v2.py update ROOT` を実行。
  - ブラウザ: `web/src/sync.js` の JS 移植を実行（サーバーも Python も呼べないため）。
- Vim が同じノートを開いている（`.swp` あり）ときは自動保存を止めて警告。
  `Ctrl+S` で強制保存は可能。

## 構成

| パス | 役割 |
| --- | --- |
| `web/electron/main.cjs` | Electron main。ウィンドウ + IPC + Python sync 呼び出し |
| `web/electron/preload.cjs` | `window.pkm` を公開（contextIsolation） |
| `web/electron/fsapi.cjs` | vault の fs 操作 + Python sync（electron 非依存・テスト可能） |
| `web/index.html` | 画面の骨組み。`bundle.js` を読む |
| `web/styles.css` | ライト/ダークのテーマ（CSS 変数） |
| `web/bundle.js` | esbuild で固めたレンダラ本体（コミット対象） |
| `web/src/app.js` | 状態管理と UI |
| `web/src/editor.js` | CodeMirror 6 + ライブプレビュー |
| `web/src/vault.js` | 読み書きの入口。Electron は `window.pkm`、ブラウザは FSA |
| `web/src/sync.js` | `simple_sync` の JS 移植（ブラウザ用。正は Python） |
| `web/test/fsapi_test.mjs` | fsapi + Python sync の単体テスト |
| `web/test/browser_smoke.mjs` | headless Chromium の E2E（JS sync == Python sync） |
| `web/test/sync_diff.mjs` | JS sync と Python sync の差分テスト |

## 開発

```bash
cd web
npm install
npm run build     # src/*.js -> bundle.js
npm test          # fsapi_test + browser_smoke
```

- `bundle.js` はコミットする。`node_modules/` はコミットしない。
- Electron の起動確認（ヘッドレス）:
  `xvfb-run -a node_modules/.bin/electron . --no-sandbox`（`PKM_ROOT` で vault 指定）。

## 既知の制約

- **ブラウザは実質 Chrome 系のみ**。この環境の **Brave は `file://` で
  `showDirectoryPicker` が undefined** で、ブラウザ経路は動かない（なので Electron 既定）。
  Firefox も FSA 非対応。`file://` では IndexedDB が応答しないことがあり、
  毎回フォルダ選択になる（`vault.js` でタイムアウトしてフォールバック）。
- ハブ (`\1`〜`\9`) は Vim の状態ファイルが vault 外にあり、アプリからは未対応。
