# 08 Web アプリ (ブラウザで閲覧・編集)

Obsidian 風に、ブラウザからノートを閲覧・編集する。**サーバーは立てない。**
`web/index.html` をブラウザで開き、vault フォルダを選ぶと、File System Access API
で直接読み書きする。

## 対応ブラウザ

- **Brave / Chrome（Chromium 系）** が必要。`file://` でも `showDirectoryPicker()` が
  使えることを確認済み（`isSecureContext === true`）。
- **Firefox は非対応**（File System Access API が無い。OPFS のみ）。

## 起動

- Vim から: `:SimpleWeb` または `\w`（`brave-browser --app=file://…/web/index.html`）。
- 直接: `web/index.html` をダブルクリック / ブラウザにドラッグ。
- 初回は「開く」→ `~/files/yurii-note` を選択。次回は権限の再許可を求められることがある。

## できること

- 一覧（検索で絞り込み）/ タブ / リンククリックで移動
- ライブプレビュー編集（**CodeMirror 6**、Obsidian と同じ方式。生 Markdown を保持）
- タイトル編集、親 (Parent) / 子 (本文リンク) / 被リンク (BackLink) パネル
- 新規ノート / 新規グループ作成、削除
- 画像インライン表示、リンク入力補完
- グラフビュー (d3-force)
- 保存 (Ctrl+S) 時に **JS 版 sync が走り**、全ノートの Parent/BackLink/表示名を
  Python と同じ規則で更新する。

## 編集モデル（ノートを壊さないための分離）

本文だけをライブプレビューで編集する。front matter はタイトル欄、`### Parent` は
関係パネルのリスト、`### BackLink` は読み取り専用（自動生成）。セクション見出しを
WYSIWYG に食わせないので、`### Parent` / `### BackLink` が壊れない。

保存時の流れ:
1. タイトル + 本文 + Parent リストからノートの生テキストを組み立てる。
2. 全ノートに対して `web/src/sync.js` の `runSync()` を実行。
3. 変更のあったノートと `.pkm_title_state_v2.json` を書き戻す。

## 同期は二重実装（最重要）

- 正: `plugin/simple_yurii_note/python/note_format_v2.py` の `simple_sync()`。
- 移植: `web/src/sync.js` の `runSync()`。**挙動を変えたら必ず差分テストを回す。**

```bash
cd web
# Python と JS の出力が全ファイル一致するか
cp -r ~/files/yurii-note /tmp/A ; cp -r ~/files/yurii-note /tmp/B
python3 ../python/note_format_v2.py update /tmp/A
node test/sync_diff.mjs /tmp/B
diff -r /tmp/A /tmp/B        # 空なら一致
```

差分テストで確認済みのケース: タイトル変更の追従 / グループ→Parent / BackLink /
消えたファイルの行リンク掃除 / 文中リンクの文字残し / index の追加・削除 /
`.pkm_title_state_v2.json` が無い状態。

## ビルドと E2E テスト

```bash
cd web
npm install          # 初回のみ
npm run build        # src/*.js -> bundle.js (esbuild, IIFE)
npm test             # headless Chromium で実走。JS sync == Python sync と UI を検証
```

- `bundle.js` は**コミットする**（実行時に Node 不要にするため）。`node_modules/` は除外。
- E2E は `showDirectoryPicker` をインメモリ FS モックに差し替え、`file://` で実際に動かす。
- `file://` では **IndexedDB が応答しない**ことがある。`vault.js` は IDB を
  タイムアウト付きで扱い、使えなければ毎回フォルダ選択にフォールバックする。

## 既知の制約

- ハブ (`\1`〜`\9`) は Vim の状態ファイルが vault 外 (`~/.vim/simple_yurii_note`) に
  あるため、ブラウザからは触れない（ブラウザ側では未実装）。
- Vim と同時に同じノートを開くと競合しうる。保存時 `.swp` があれば警告する。
- 非 UTF-8 の `.md` は文字化けしうる（Python 側は `UnicodeDecodeError` で落ちる）。

## ファイル構成

| パス | 役割 |
| --- | --- |
| `web/index.html` | 画面の骨組み。`bundle.js` を読む |
| `web/styles.css` | ダークテーマ + ライブプレビューの見た目 |
| `web/bundle.js` | esbuild で固めた本体（コミット対象） |
| `web/src/sync.js` | **simple_sync の JS 移植**（正は Python） |
| `web/src/vault.js` | File System Access API の読み書き・権限・IDB |
| `web/src/editor.js` | CodeMirror 6 + ライブプレビュー |
| `web/src/graph.js` | d3-force のグラフ |
| `web/src/app.js` | 全体の状態管理と UI |
| `web/test/sync_diff.mjs` | Python との差分テスト |
| `web/test/browser_smoke.mjs` | headless Chromium の E2E |
