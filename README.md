# Yurii_PKM

Vim/Neovim 上で Markdown ベースのノートを管理するための PKM（Personal Knowledge Management）プラグインです。  
ノート作成・リンク移動・タイトル同期・表編集までを 1 つのワークフローで扱えます。

---
Vim 上で Markdown ノートを運用するための PKM（Personal Knowledge Management）プラグインです。

## インストール

### vim-plug

`~/.vimrc`（または `init.vim`）に以下を書いてください。

```vim
Plug 'Yurii7812/Yurii_PKM'
```

その後、Vim/Neovim で以下を実行します。

```vim
:PlugInstall
```

---

## 必須設定（最小）

ノートを保存するルートディレクトリを指定します。

```vim
let g:yurii_pkm_root = expand('~/memo')
```

---

## 使い方（最短）

1. `:YuriiIndex` で `index.md` を開く。
2. `nf` / `mm` / `nk` で新規ノートを作成する。
3. `<Tab>` / `<S-Tab>` でリンク移動、`<Enter>` でリンクを開く。
4. `zt` でタイトル編集、`bc` / `ta` でリンク操作を行う。

### 現在のファイルをブラウザで開く

Normal モードで `gm` を押すと、現在のファイルを開きます。Linux では `xdg-open`、WSL では Windows 側の既定ブラウザを使用します。WSL で `wslview` があればそれを優先し、無い場合は Windows 標準の `cmd.exe` に `file://` URI を渡します。

---

## 推奨設定

```vim
" fcitx: Insert を抜けると英語入力、戻ると直前が日本語なら日本語入力へ復元（既定: 1）
let g:yurii_fcitx_auto_switch = 1
" 必要なら fcitx コマンドを明示
let g:yurii_fcitx_remote_cmd = 'fcitx5-remote'

" 保存時 AutoSync（既定: 1）
let g:yurii_pkm_autosync = 1

" Parent/Child リンクのリアルタイム双方向同期（既定: 1）
let g:yurii_pkm_realtime_link_sync = 1
" TextChanged 後に同期を走らせるまでの待ち時間 ms（既定: 800）
let g:yurii_pkm_realtime_link_sync_delay = 800
" 大きいノートでは TextChanged 直後の同期をスキップ（保存時 AutoSync は有効）
let g:yurii_pkm_realtime_link_sync_max_lines = 2000
" 本文リンクから BackLink をリアルタイム同期する重い処理（既定: 0 / 保存時に同期）
let g:yurii_pkm_realtime_backlink_sync = 0

" 長い PDF リンクなどで conceal が重い場合の自動抑止しきい値
let g:yurii_pkm_markdown_conceal_max_lines = 2000
let g:yurii_pkm_markdown_conceal_max_line_length = 1000

" コマンド実行前に自動保存（既定: 1）
let g:yurii_pkm_auto_save_on_command = 1

" 履歴件数（既定: 200）
let g:yurii_pkm_history_max = 200

" 新規ノートの既定プレフィクス
let g:yurii_pkm_default_child_prefix = 'C'
let g:yurii_pkm_default_quick_prefix = 'F'
let g:yurii_pkm_default_atomic_prefix = 'C'
```

---

### fcitx の入力モード自動切り替え

`vimrc_yurii_PKM` では、fcitx の日本語入力中に Insert モードから Normal モードへ戻ると自動で英語入力へ切り替えます。<br>
そのとき日本語入力だった場合だけ、次に Insert モードへ入ると日本語入力へ戻します。
Normal モードへ戻ったときの英語入力化は、状態取得に失敗しても必ず実行します。

- `fcitx5-remote` があれば優先して使います。
- `fcitx5-remote` が無い場合は `fcitx-remote` を使います。
- 無効化する場合は `let g:yurii_fcitx_auto_switch = 0` を設定してください。
- コマンドを固定したい場合は `let g:yurii_fcitx_remote_cmd = 'fcitx5-remote'` のように設定してください。
- 動作確認用に `:YuriiFcitxOff`、`:YuriiFcitxOn`、`:YuriiFcitxStatus` を使えます。`:YuriiFcitxStatus` が `2` を返す状態が「次回 Insert で日本語入力へ戻す」対象です。

---


## 基本的な仕組み（設計の考え方）

このアプリ（`yurii_PKM`）は、**1ファイル=1ノートの Markdown** を前提に、
ノート間の関係をリンクとセクション構造で管理します。

- ノート実体: `*.md` ファイル
- メタ情報: YAML front matter（`title`, `time`, `filetype` など）
- 関係性: Markdown リンク `[表示名](target.md)`
- 同期: Parent/Child は編集直後に相手側へ反映し、保存時 AutoSync は軽量な単一ファイル同期、`:UpdateMD` は全体整合

### セクションモデル

標準ノートは概ね次の領域で扱います。

- `Parent:`（親方向）
  - このノートが「どこから来たか / どの親にぶら下がるか」を示すリンク群
- `Child:`（子・関連方向）
  - このノートから派生した子ノートや関連ノートへのリンク群
- `BackLink:`（被リンク方向）
  - 他ノートからこのノートへ向けられた逆リンク（バックリンク）

`Parent / Child / Back` を分けることで、
「親へ戻る」「子へ進む」「どこから参照されているかを確認する」を明確に使い分けできます。

## Parent と BackLink（Back）の仕様

### Parent の仕様

- 役割: **親ノートへの導線**。
- `Parent:` は **複数リンクを保持可能**（複数の親文脈を許可）。
- 主な追加方法:
  - ノート作成コマンド（`nc`, `nq` のモード）で自動挿入
  - `cu` / `:CA` でクリップボードのリンクを Parent: に追加
  - `ca` / `:CU` でクリップボードのリンクを現在ノートの Child: に追加し、リンク先ノートの Parent: に現在ノートを追加
  - `ta` / `:AT` でクリップボード先ノートの Child: に現在ノートを追加し、現在ノートの Parent: にクリップボード先ノートを追加
- 使い方:
  - 現在ノートの文脈上の「上位」へ戻るための導線として運用
  - `bu`（`JumpLastLinkBeforeParent`）で Parent: 近傍のリンクへ素早く移動
  - `,,`（`:JumpParent`）で、Parent リンクが1つだけならリンク先へ直接移動し、複数ある場合は `Parent:` 見出しへ移動
  - 親文脈を増やしたい場合は、Parent: にリンクを追加できる
  - Child: からの親子関係が複数ある場合、同期後も Parent: に複数リンクとして反映
  - PKM ルート配下のサブフォルダをまたぐ Child/Parent 関係も、相手ノート基準の相対パス付きリンクとして反映
  - Child: からリンクを削除した場合も、同期後に相手ノートの Parent: から対応リンクが消える
  - Parent: からリンクを削除した場合も、保存時同期後に相手ノートの Child: から対応リンクが消える
  - 未保存の Child: 編集がある状態でリンク移動や履歴戻りをした場合も、移動前に保存と同期を行って Parent: に即反映する

### BackLink（Back）の仕様

- 役割: **このノートを参照しているノートの一覧（逆リンク）**。
- 生成タイミング:
  - `.md` 保存時 AutoSync（`g:yurii_pkm_autosync=1`）
  - もしくは `:UpdateMD` / `:UpdateAll` の一括更新
- 表示ルール:
  - Back セクションに、他ノートからのリンクに応じて逆リンクを自動反映
  - 同じノートが `Parent:` にもある場合は Parent を優先し、重複するリンクを BackLink には表示しない
  - PKM ルート配下のサブフォルダにあるノート同士でも、相対パス付きリンクとして BackLink を生成
  - サブフォルダ内の本文リンクがファイル名だけでも、PKM ルート配下で一意に見つかる `.md` なら BackLink に反映
  - K系ノートでは `category:` 見出し、N系ノートでは `note:`（または見出しなし運用）を使う設計
- 手動編集との共存:
  - リンク表示名の自動更新は「表示名=ファイル stem」のリンクのみ更新対象
  - 手動で意味付けした表示名は原則維持

### Parent と BackLink の違い（重要）

- **Parent**: このノートから見た「親方向」の明示リンク（能動的に置く）
- **BackLink**: 他ノートからの参照を集約した「被リンク一覧」（受動的に集まる）

この2つを分離しているため、
- Parent は構造ナビゲーション（階層・文脈）
- Back は発見ナビゲーション（参照関係の把握）

として機能します。

## 機能一覧（整理版）

### 1) ノート作成

- `nf` : クイックノート作成（タイトルなし）
- `mm` : プレフィクスなしの新規ノート作成（YAML `filetype: N`）。親ノート側のリンクは `Child:` に作成
- `nk` : プレフィクスなしの新規ノート作成（YAML `filetype: K`）。`title:` 入力後にモード選択を行い、タイトルを空のまま Enter するとファイル名（タイムスタンプ）がタイトルになる
- `na` / `:NA` : 現在位置に A ノート作成
- `:NF` : 引数付きクイック作成
- ビジュアルモードでも `nf` / `mm` / `nk` に対応

### 2) リンク移動・履歴

- `<Tab>` : 次のリンクへ移動（本文・関係すべて）
- `<S-Tab>` : 前のリンクへ移動
- `<Space>` / `gs` : ノートナビゲータ。状態は**「打つ」か「打たない」かの1つだけ**。`⏎` で打つのをやめ、`i` で打ちに戻る
  - **打たない状態のキーは、ローカルでもグローバルでも完全に同じ。** スコープ（ローカル＝今のノートのリンク / グローバル＝全ノート）は**候補が何か**の違いでしかない。`⇥` で切り替え
  - 上のバーで今どっちか分かる … `検索 …▏`（カーソル有り）＝打てる / `◎ ノート名`・`全ノート`（カーソル無し）＝打たない

  **打たない（コマンド）**
    - **ラベルキー**（`1`〜`0` のあと英字）… 1タップでその行へ
      - **ローカル**では**そのまま潜る**（相手が既に分かっているので。潜ってもアンカー行 `◎` とプレビューに出続け `⌫` で即戻れる＝非破壊）
      - **検索結果（グローバル）では移動だけ**。7番を見たいのに `↓` を7回は野暮なので1打で飛び、プレビューで中身を見てから `⏎` 開く / `l` 潜る を選ぶ
    - `j`/`k` 選択 ・ `g`/`G` 先頭/末尾 ・ `f`/`b` プレビュー送り
    - `⏎` 選択を開いて閉じる（潜った直後はアンカーが選択済みなので `5` `⏎` で「5番へ潜って着地」）
    - `⌫` / `h` / `←` 戻る ・ `␣` アンカー自体を開く
    - `c`/`p` アンカーの子/親に追加 ・ `y` ヤンク ・ `m` マーク ・ `M` 全解除 ・ `a` アンカー移動
    - `i` 打つ（クエリは残る）・ `/` クエリを消して打つ ・ `⇥` スコープ切替 ・ `⎋` 取消

  **打つ（入力）**
    - 打つ … タイトル＋本文の AND 絞り込み（**ラベルが無い状態なので数字もそのままクエリに入る**）・ `⌫` 1字消す（空なら戻る）
    - `↑`/`↓` 選択 ・ `→` 潜る ・ `←` 戻る
    - `⏎` 入力終了 → コマンドへ ・ `⎋` クエリを消して終了 ・ `⇥` スコープ切替
    - 入力中は記号もそのまま打てる（`-` を含む）。子/親に追加・マーク・ヤンクは、`⏎` で入力を終えたコマンド状態か、英字キー `c`/`p`/`m`/`y` で行う

  - ローカルは `── 文中 ──` / `── こっちにとって ──` / `── そっちにとって ──` の3区切り（`¶` `→` `←`）、1行目は常にアンカー `◎`
  - 検索中はプレビューで**ヒット語が反転表示**され、**最初のヒット行まで自動でスクロール**する（なぜその結果が出たのか一目で分かる）
  - グローバルの並びは**最近訪問した順**に固定。パンくず（`起点 › … › 現在`）が最上段。`⎋` は何ホップ潜っても全部取り消して元のノート・カーソル位置へ
- `<S-Space>` : ポップアップを出さず、カーソルだけ次の parent/child リンクへ（端で折り返す）
- `n` / `N` : 素のVimの検索リピート（前方/後方）。ノート作成系の2文字コマンド（`zk`/`zn`等）は頭文字を`z`にしてあるため`n`とは衝突しない
- `_` : **直前のノートと1キーで往復**（A⇄B）。読むもの・選ぶものゼロの最速移動
- `<S-BS>` / `\.` : 履歴を**前へ進む**（`<BS>` の対。戻りが可逆になる）
- `\1`〜`\9` : **ハブへ直行**。`\H` で今のノートをハブに登録（番号を1打）、`\0` で一覧。登録は再起動後も残る
- `1`〜`9` / `\`+文字+数字（`\a1`〜） : 本文 → `Parent`/`Child` の順で通し番号にしたリンクを**そのまま開く**（移動して `<Enter>` まで含む）。**リンクの手前にラベルが仮想テキストで表示される**ので、数えずにどのキーを押せばいいか分かる。1〜9番目は数字1打、10番目以降は `\a1`〜`\a9`、`\b1`…（既存の `\ca` 等と同じ `\` リーダー、3打）。生の `a` `i` `o` などは一切奪わない ── 10番目以降のラベルも `\` から始まるので、素のキー入力の速さには影響しない。該当リンクが無い数字キーはそのままカウント（`5j` 等）として素通しされる。表示は `g:yurii_pkm_link_hints = 0` で無効化できる（移動・オープン自体は無効化されず、番号は数えて押す必要がある）
- `<Enter>` : カーソル下リンクを開く
- `<BS>` : 履歴を戻る（戻った直後はカーソルがリンク上に寄る）
- `bu` : `Parent:` 近傍のリンクへ移動
- `,,` / `:JumpParent` : Parent リンクが1つだけならリンク先へ直接移動、複数ある場合は `Parent:` 見出しへ移動
- `,.` / `:JumpChildTop` : `Child:` セクションの先頭行へ移動
- `,/` / `:JumpChildBottom` : Parent リンクが複数ある場合は一番上の Parent リンクへ移動し、それ以外は `Child:` セクションの最後尾行へ移動

### 3) タイトル変更

- `zt` : 空入力からタイトル編集
- `zT` / `:NT` : 現在タイトルを残して編集
- タイトル変更時は、同一ターゲットへのリンクのうち「旧タイトルと一致する表示テキスト」だけ新タイトルへ更新（例: `[A](x.md)` は更新、`[aaa](x.md)` は維持）

### 4) リンク操作

- `bc` / `:BC` : クリップボードのファイルを Child: に追加
- `ca` / `:CU` : クリップボードのリンクを現在ノートの Child: に追加し、リンク先ノートの Parent: に現在ノートを追加
- `ta` / `:AT` : クリップボード側ノートの Child: に現在ノートを追加し、現在ノートの Parent: にクリップボード側ノートを追加
- `yn` / `:YN` : 現在ファイル名をヤンク
- `\l` / `:Linkify` : ファイル名テキストを Markdown リンク化。表示名は拡張子を除いたもの、リンク先は拡張子付きのファイル名（`.md` は代わりにタイトルを使う）


- `\p` / `:PasteLink` : クリップボードのリンクを挿入
- Visual `\p` : クリップボードにファイル名/リンクがある場合のみ、選択文字列をそのターゲットへリンク化（無い場合は何もしない）
- `p` : `"+p` へマップ（システムクリップボード貼り付け）
- `gp` : 旧挙動の貼り付け
- `.` : Vim 標準の直前の変更を繰り返す動作

### 5) 同期・一括更新

- `:UpdateMD [path]` : リンクタイトル等の一括更新
- `:UpdateAll [path]` / `:UpdateALL [path]` : 同等コマンド
- 自動同期で表示名を上書きするのは `[xxx](xxx.md)` のように表示名がターゲットstemと一致するリンクのみ（手動表示名は維持）
- Back セクションは、該当リンクがあるときだけ `category:`（K系）/`note:`（N系）見出しを自動表示

- Parent/Child リンクは `g:yurii_pkm_realtime_link_sync=1` 時に追加・削除直後に相手ノートへ反映
- `.md` 保存時に AutoSync（`g:yurii_pkm_autosync=1` 時）は編集中ファイルのタイトルと直接リンク先だけを軽量同期

### 6) 変換・リネーム

- `\se` / `:ExpandLinks`（旧 `:SE` / `:ExpandToT`）: S ノートを展開して関連ファイルを開く（元ファイルへリンクは追加しない）
- `mp` / `:RP` : YAML の `filetype` を変更

### 7) インデックス・ユーティリティ

- `:YuriiIndex` : `index.md` を開く
- `:YuriiChooseIndexDir` : index ルート選択
- `:SortYomi` : Child の読み順ソート
- `:CheckPrefix` : プレフィクスチェック
- `:OutlineEdit` / `\oe` : アウトライン編集（別バッファで見出し編集、`←/→` で `#` 数変更、`q` / `:write` / `ZZ` / `:OutlineApply` で反映）


### 8) Markdown テーブル編集

- 作成: `:TN`, `:NewTable`, `:YuriiTable`
- 整形: `:TA`
- 行編集: `:TRE`
- CSV編集: `:TCSV`, `:TableCsvEdit`, `:TableCsvApplySaved`
- 変換: `:TableToCsv` (`:TCE`), `:CsvToTable`
- 新規CSVテーブル: `:TableCsvNew`, `:TCN`
- 行列操作: `:TAR`, `:TAC`, `:TDR`, `:TDC`
- ノーマルモード補助:
  - `\tn`, `\ta`, `\te`, `\tc`, `\tt`, `\tnc`, `\tar`, `\tac`, `\tdr`, `\tdc`
- テーブル内挿入モード補助:
  - `<Tab>` / `<S-Tab>` / `<CR>` がテーブル操作として動作

---

## 主要コマンド一覧（早見表）

| 種別 | コマンド |
|---|---|
| 作成 | `:NF`, `:NA`, `:CA` |
| 更新 | `:UpdateMD`, `:UpdateAll`, `:UpdateALL` |
| 編集 | `:NT`, `:RP`, `:OutlineEdit` |
| 移動 | `:YuriiIndex`, `:YuriiChooseIndexDir` |
| 変換 | `:ExpandLinks`（旧 `:SE` / `:ExpandToT`）, `:SortYomi`, `:Linkify`, `:LinkifySelection`, `:PasteLink` |

| テーブル | `:TN`, `:TA`, `:TRE`, `:TCSV`, `:TableToCsv`, `:CsvToTable`, `:TAR`, `:TAC`, `:TDR`, `:TDC` |

---

## 既定値つき設定変数

| 変数 | 既定値 | 内容 |
|---|---:|---|
| `g:yurii_pkm_root` | `''` | PKM ルートディレクトリ |
| `g:yurii_pkm_default_child_prefix` | `'C'` | 子ノート既定プレフィクス |
| `g:yurii_pkm_default_quick_prefix` | `'F'` | クイック作成既定プレフィクス |
| `g:yurii_pkm_default_atomic_prefix` | `'C'` | Atomic 作成既定プレフィクス |
| `g:yurii_pkm_history_max` | `200` | 履歴最大件数 |
| `g:yurii_pkm_autosync` | `1` | 保存時 AutoSync 有効/無効 |
| `g:yurii_pkm_auto_save_on_command` | `0` | コマンド前自動保存 |
| `g:yurii_pkm_sync_before_link_navigation` | `0` | `<CR>` / `<BS>` のリンク移動直前に同期まで実行するか（既定OFFで移動優先） |
| `g:yurii_pkm_save_before_link_navigation` | `0` | `<CR>` / `<BS>` のリンク移動直前に保存するか（既定OFFでEnter移動優先） |
| `g:yurii_pkm_global_bare_link_navigation` | `0` | ファイル名だけのリンクをEnter移動時にPKMルート全体から一意検索するか |
| `g:yurii_pkm_space_fullscreen` | `1` | `<Space>` を画面いっぱいの2ペインにする（`0` で従来の中央小窓） |
| `g:yurii_pkm_space_list_width` | `0` | `<Space>` 一覧の幅（`0` = 自動、34〜50） |
| `g:yurii_pkm_space_labels` | `'1234567890asdfwertzxcvbnmuiop'` | `<Space>` の行ジャンプに使うラベルキー列 |
| `g:yurii_pkm_space_preview_lines` | `400` | `<Space>` プレビューで読み込む行数 |
| `g:yurii_pkm_recent_max` | `500` | 最近訪問を覚えるノート数 |
| `g:yurii_search_legacy` | `0` | `gs` を旧ポップアップに戻す |
| `g:yurii_pkm_link_hints` | `1` | `1`〜`9`/文字+数字リンクジャンプのラベル仮想テキスト表示（`0` で非表示。移動機能自体は残る） |
| `g:yurii_pkm_timeoutlen` | `500` | `&timeoutlen`（ms）をこの値に短縮。`zk`/`ca`等の2文字マッピングと素の`z`/`c`等の単発コマンドが1文字目を共有するため、既定の1000msだと素のキーの反応が遅く感じる。短すぎると`zt`等が2文字目の入力前にタイムアウトして無反応になるので、体感と両立する値として500に調整。`0`で変更しない |
| `g:yurii_pkm_python` | `{plugin}/python/yurii_pkm_sync.py` | 同期スクリプト |
| `g:yurii_pkm_expand_s_python` | `{plugin}/python/expand_s.py` | S展開スクリプト |

---


## トラブルシューティング（マージ競合エラー）

README に以下のような文字列が見える場合は、Git のマージ競合が未解決です。

- `<<<<<<<`
- `=======`
- `>>>>>>>`

このリポジトリの `README.md` は競合解消済みの状態が正です。  
競合マーカーが残っている場合は、競合行を削除して 1 つの内容に統合してからコミットしてください。

---

## 参考

- 詳細な操作リファレンス: `plugin/yurii_PKM/README.txt`
