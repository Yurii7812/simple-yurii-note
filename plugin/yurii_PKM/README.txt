# yurii_PKM 操作リファレンス

## キーマッピング一覧

### ナビゲーション

| キー | 動作 |
|------|------|
| `Tab` | 次のリンクへカーソル移動 |
| `Shift-Tab` | 前のリンクへカーソル移動 |
| `Enter` | カーソル下のリンク先ノートを開く（現在ファイルを履歴に積む） |
| `BS` (BackSpace) | 履歴を1つ戻る（前のノートへ） |
| `bu` | `Parent:` 見出しより前にある最後尾のリンクへカーソル移動（無い場合は `Parent:` 内の最初のリンクへ移動） |
| `,,` | Parent リンクが1つだけならリンク先へ直接移動、複数ある場合は `Parent:` 見出しへカーソル移動 |
| `,.` | `Child:` セクションの先頭行へカーソル移動 |
| `,/` | `Child:` セクションの最後尾行へカーソル移動 |

### ノート作成

| キー | コマンド | 動作 |
|------|----------|------|
| `nc` | `:NC` | 子ノート作成（プレフィクス `C` 固定）。タイトルを入力して Child に追加し、新ノートを開く |
| `nq` | `:NQ` | クイック子ノート作成。プレフィクス・タイトル・挿入モードを順に入力する |
| `cu` | `:CA` | クリップボードのリンクを `Parent:` セクションへ追加する |
| `ca` | `:CU` | クリップボードのリンクを現在ノートの `Child:` に追加し、リンク先ノートの `Parent:` に現在ノートを追加する |
| `tt` | `:TT` | クリップボードのファイル名/リンクを本文先頭（H1直下）に追加する |


#### `nq` の入力フロー

```
1. prefix (a-z):    → 1文字即時確定（大文字に変換される）
2. title:           → タイトル文字列を入力（Enter で確定）
3. mode:            → O=Orphan / B=Back / H=Cursor直下 / Enter=ChildLast

```

| モード | 動作 |
|--------|------|
| `H`（Cursor直下） | 親ノートのカーソル行直下にリンクを挿入し、作成ノートの `Parent:` に親リンクを入れる |
| `O` Orphan | 親ノートに一切リンクを追加しない独立ノートとして作成 |
| `B` Back | 新ノートの Child に親へのリンクを入れる（逆リンク方式） |
| `Enter` | 親ノートの `Child:` 末尾にリンクを挿入 |


### タイトル変更

| キー | コマンド | 動作 |
|------|----------|------|
| `zt` | | タイトルを空欄から新規入力して変更（YAML front matter と H1 を同時更新） |
| `zT` | `:NT` | 現在のタイトルを表示した状態で編集開始 |

`zt` / `zT` でタイトル変更した場合、同じノートへのリンクのうち表示テキストが旧タイトルと一致するものだけ新タイトルへ更新される（例: `[A](x.md)` は更新、`[aaa](x.md)` は維持）。

### リンク操作

| キー | コマンド | 動作 |
|------|----------|------|
| `bc` | `:BC` | クリップボードのファイル名を Child 末尾にリンクとして追加 |
| `at` | `:AT` | クリップボードのファイルの Child に現在ファイルへのリンクを追加し、現在ファイルの Parent にクリップボードのファイルを追加 |
| `yn` | `:YN` | 現在ファイルのファイル名（拡張子付き）をクリップボードにヤンク |
| `zl` | | カーソル下の Markdown リンクの表示名（`[]` の中身）を空欄から新規入力して変更 |
| `zL` | `:LT` / `:RenameLinkText` | カーソル下の Markdown リンクの現在の表示名を残して編集開始 |
| `\l` | `:Linkify` | カーソル下のファイル名テキストを Markdown リンク形式に変換 |
| Visual `\l` | `:LinkifySelection` | 選択文字列をタイトルにした `<timestamp>.md`（YAML `filetype: N`）を作成し、その新規ノートへのリンクに置換 |


| `\p` | `:PasteLink` | クリップボードのファイル名/リンクをカーソル行の直下に挿入 |
| Visual `\p` |  | クリップボードにファイル名/リンクがある場合のみ、選択文字列をそのターゲットへリンク化（無い場合は何もしない） |
| `mx` | `:ToggleCheckbox` | カーソル行のチェックボックス `[ ]` / `[x]` をトグル |
| Visual `mx` | `:'<,'>ToggleCheckbox` | 選択範囲の各行にあるチェックボックス `[ ]` / `[x]` をトグル |
| `p` | | 行単位ヤンクでも改行なしでカーソル直下に貼り付け（Vim標準の `p` を上書き） |
| `\gi` | `:Gallery` / `:YuriiGallery` / `:GalleryFolder` | 画像リンクを含むMarkdownでは現在Markdown内の画像リンクを開き、画像リンクが無い場所ではIndexフォルダ以下の全画像を開く |

### ノート変換・管理

| キー | コマンド | 動作 |
|------|----------|------|
| `\se` | `:ExpandLinks`（旧 `:SE` / `:ExpandToT`） | カーソルが開いているSノートをAノートに展開（`expand_s.py` を呼び出す、元ファイルへリンクは追加しない） |

| `mp` | `:RP` | 現在ファイルの YAML `filetype` を変更 |

#### `mp` の入力フロー

```
filetype [N] →    → 新しい filetype を1文字入力（a-z、大文字に変換）
```

変更後は現在ファイルの front matter (`filetype:`) が更新される。

### インデックス・並び替え

| キー | コマンド | 動作 |
|------|----------|------|
| | `:YuriiIndex` | `index.md` を開く |
| | `:JumpLastLinkBeforeParent` | `Parent:` 見出しより前にある最後尾のリンクへカーソル移動（無い場合は `Parent:` 内の最初のリンクへ移動） |
| | `:JumpParent` | Parent リンクが1つだけならリンク先へ直接移動、複数ある場合は `Parent:` 見出しへカーソル移動 |
| | `:JumpChildTop` | `Child:` セクションの先頭行へカーソル移動 |
| | `:JumpChildBottom` | `Child:` セクションの最後尾行へカーソル移動 |
| | `:SortYomi` | Child セクションを読み仮名順にソート（`sort_yomi.py` 経由） |
| | `:SortTime` | 範囲選択がある場合は選択範囲のリンク行を、未選択時は Child セクションのリンク行を時刻で昇順ソート |
| | `:SortTime!` | `:SortTime` と同じ対象を時刻の降順（新しい順）でソート |

---

## コマンド一覧

上記キーマッピングに対応するコマンドに加え、以下が利用できる。

| コマンド | 動作 |
|----------|------|
| `:UpdateMD [path]` | PKMルート（省略時は `g:yurii_pkm_root`）の全ノートのリンクタイトルを一括更新 |
| `:UpdateAll [path]` | `:UpdateMD` と同じ |
| `:Gallery [path]` | 指定または現在のMarkdownファイルから画像リンクを抽出してブラウザギャラリーを開く |
| `:YuriiGallery [path]` | `:Gallery` と同じ |
| `:GalleryFolder [path-or-dir]` | 指定フォルダ、または引数なしではIndexフォルダ以下にあるすべての画像ファイルをサブフォルダ込みでブラウザギャラリーで開く |
| `:YuriiGalleryFolder [path-or-dir]` | `:GalleryFolder` と同じ |


---

## 画像ギャラリー

Markdownファイルを1つの分類として扱い、そのファイル内に書いた画像リンクをブラウザで見やすく表示できる。

```markdown
# 猫

![cat1](./images/cat1.jpg)
![cat2](./images/cat2.jpg)
```

画像の直前にある、空行で区切られた同じブロック内のURLや説明文もキャプションとして表示される。画像リンクだけが連続している場合は説明文なしとして扱い、画像リンク行の後に書いた説明文/URLは、その次に現れる画像リンクの説明文になる。

```markdown
https://wear.jp/nakamuramizuki0702/25500739/
<img src="20260602154720.avif" width="50%">

〜を示す図。
https://www.instagram.com/p/DIOTlVhvVVu/?img_index=2
<img src="20260602154826.jpg" width="50%">
```

VimでこのMarkdownファイル内のどこかに画像リンクがある状態で `\gi`、または `:Gallery` を実行すると、ローカルサーバーが自動起動し、ブラウザにサムネイルグリッドが表示される。
Windows版Vimでも既定ブラウザをWindowsのファイル関連付け経由で開き、ローカルサーバーはVimのジョブ終了後も表示に必要な間は独立して動作する。`C:\Users\...\image.jpg` のようなドライブレター付き画像パスにも対応する。
現在のMarkdownに画像リンクが無い状態で `\gi` を実行した場合は、最初に開くIndexがあるフォルダ（`g:yurii_pkm_root`。未設定時は現在ファイルから上位に探した `index.md` のフォルダ）以下にあるすべての画像ファイルをサブフォルダ込みで表示する。ブラウザ上部の「Indexフォルダ以下のすべての画像」ボタン、または引数なしの `:GalleryFolder` でも同じIndex配下の画像ギャラリーを開ける。`:GalleryFolder [path-or-dir]` のように明示した場合は、そのフォルダ/ファイルの親フォルダ以下をサブフォルダ込みで表示する。
サムネイルをクリックすると拡大表示になり、左右矢印キー（`←` / `→`）で前後の画像へ移動できる。`Esc` で一覧へ戻る。

ギャラリー上部では、ファイル名または作成時刻で昇順/降順に並び替えできる。「ファイル名・説明文・URLを検索」欄へ入力すると、ファイル名・フルパス・説明文・URL・リンクラベルを対象に、その場で画像を絞り込める。サムネイル左上のチェックボックスで複数画像を選択し、「選択ファイル名をコピー」を押すと、パスなしのファイル名だけが改行区切りでクリップボードに入る。

分類は「Markdownファイルごと」に行う想定。たとえば `K_cats.md` に猫画像、`K_dogs.md` に犬画像のリンクを書けば、それぞれ別のギャラリーになる。

対応する画像リンク:

- Markdown画像: `![説明](relative/or/absolute/path.jpg)`
- 通常のMarkdownリンク（画像拡張子の場合）: `[説明](relative/or/absolute/path.jpg)`
- Wikiリンク形式（画像拡張子の場合）: `![[relative/or/absolute/path.jpg]]` / `[[relative/or/absolute/path.jpg]]`
- HTML画像: `<img src="relative/or/absolute/path.jpg">`（引用符なしの `src=path.jpg` も対応）
- 対応拡張子: `.jpg`, `.jpeg`, `.png`, `.gif`, `.webp`, `.avif`, `.bmp`, `.svg`

---

## AutoSync（自動同期）

`.md` ファイルを保存すると、バックグラウンドで `update_one` が自動実行される。

- Back セクションへの逆リンク追加、リンクタイトル更新などが自動的に行われる
- Back セクションは、Kのfiletypeがある場合のみ `category:` を表示し、Nのfiletypeは見出しなしで表示される
- リンク表示名の自動更新は `[xxx](xxx.md)` のように表示名がターゲットstemと一致するもののみ（手動表示名は維持）

- `job_start` が使えれば非同期、なければ同期フォールバック
- 無効化する場合: `let g:yurii_pkm_autosync = 0`

---

## 設定変数

| 変数 | デフォルト | 説明 |
|------|-----------|------|
| `g:yurii_pkm_root` | `''` | PKM ルートディレクトリ（未設定なら保存済み値→選択） |
| `g:yurii_pkm_autosync` | `1` | 保存時に自動同期するか |
| `g:yurii_pkm_realtime_link_sync` | `0` | 入力中に Parent/Child の相互リンクを同期するか（重い場合があるため既定OFF） |
| `g:yurii_pkm_auto_save_on_command` | `0` | `:` コマンド実行時に自動保存するか（コマンドごとの遅延を避けるため既定OFF） |
| `g:yurii_pkm_sync_before_link_navigation` | `0` | `<CR>` / `<BS>` のリンク移動直前に同期まで実行するか（移動を軽くするため既定OFF） |
| `g:yurii_pkm_save_before_link_navigation` | `0` | `<CR>` / `<BS>` のリンク移動直前に保存するか（Enter移動を軽くするため既定OFF。未保存バッファは hidden で保持） |
| `g:yurii_pkm_global_bare_link_navigation` | `0` | ファイル名だけのリンクをEnter移動時にPKMルート全体から一意検索するか（再帰検索を避けるため既定OFF） |
| `g:yurii_pkm_markdown_conceal_links` | `1` | Markdownリンクを本文だけ表示する conceal を有効にするか（大きい/長い行のファイルでは自動抑制） |
| `g:yurii_pkm_history_max` | `200` | 履歴の最大件数 |
| `g:yurii_pkm_persistent_undo` | `1` | Persistent undo を有効にするか |
| `g:yurii_pkm_link_color_gui` | `#66CCFF` | リンクテキストの色（GUI） |
| `g:yurii_pkm_link_color_cterm` | `81` | リンクテキストの色（端末） |
| `g:yurii_pkm_python` | `{plugin}/python/yurii_pkm_sync.py` | sync スクリプトのパス |
| `g:yurii_pkm_expand_s_python` | `{plugin}/python/expand_s.py` | S→A 展開スクリプトのパス |
| `g:yurii_pkm_gallery_python` | `{plugin}/python/gallery.py` | 画像ギャラリー用ローカルサーバースクリプトのパス |
| `g:yurii_pkm_gallery_port` | `8765` | 画像ギャラリー用ローカルサーバーのポート |
| `g:yurii_pkm_open_index_on_startup` | `1` | Vim起動時に `YuriiIndex` を自動で開くか |
| `g:yurii_redraw_after_silent_shell` | `1` | silent 化した `:!` コマンド後、端末復帰を待って `redrawstatus` と強制 `redraw!` を実行し、`:!rm %` などの後に画面が黒く残るのを防ぐか |
| `g:yurii_force_redraw_after_shell` | `0` | `g:yurii_redraw_after_silent_shell` が `0` の場合に、従来互換の `:!` コマンド後 `redraw` を行うか |

---

## ノートテンプレート

新規作成されるノートの構造:

```markdown
---
time: 2025-01-01 12:00:00
title: ノートタイトル
---

# ノートタイトル



Parent:
Child:
BackLink:
[親ノートタイトル](親ノート.md)
[index](index.md)
```

---

## リンク形式

PKM 内のリンクはすべて以下の形式を使用する:

```
[YAML内のtitle](ファイル名.md)
```

AutoSync / UpdateAll により、リンク先タイトルが変更された場合はリンク表示テキストが自動更新される。

追加の任意設定:

| 変数 | 既定値 | 説明 |
|------|--------|------|
| `g:yurii_pkm_vimrc` | 未設定 | `<leader>ev` / `<leader>sv` で開く vimrc。固定パスを使いたい場合だけ指定 |
