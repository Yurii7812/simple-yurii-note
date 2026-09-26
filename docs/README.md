# simple-yurii-pkm — 私の PKM システム概要

このフォルダは、私（yurii）の PKM（Personal Knowledge Management）システムの
ドキュメント置き場。**他のAI・未来の自分が引き継げるように**、構成と規則をここに集める。

- 実体（プラグイン）: `~/.vim-simple-yurii-note/simple-yurii-note`（GitHub: `Yurii7812/simple-yurii-note`）
- ノート実体: `~/files/yurii-note`（52 ノート、`.md` 1ファイル=1ノート）
- 専用 Vim 環境: `vim -u ~/.vimrc-simple-yurii-note`

## まず読む順

1. [01-概要](01-概要.md) … 何のシステムか、環境、全体マップ
2. [02-ノート形式](02-ノート形式.md) … ノートの書き方（`### Parent` / `### BackLink` / 本文リンク）
3. [03-同期の規則](03-同期の規則.md) … Parent/BackLink がどう決まるか
4. [04-キー操作](04-キー操作.md) … よく使うキー / コマンド
5. [05-データとリポジトリ](05-データとリポジトリ.md) … 保存場所・Git・push ルール
6. [06-引き継ぎ](06-引き継ぎ.md) … 新しいAI向けチェックリスト・落とし穴

## 30秒サマリ

- **1ファイル=1Markdown ノート**。関係は Markdown リンクで表す。
- ノート下部に `### Parent` と `### BackLink` の2セクション。**`### Child` は無い**。
- **本文にリンクを書くと「子」**になる。
- **`### Parent` は手書き管理**（書いたまま。勝手に増減しない）。
- **`### BackLink` = 本文でこのノートを参照している相手（incoming）− Parent**。
- 同期エンジンは `note_format_v2.py`。保存時に自動同期。
- 専用 Vim 環境 `~/.vimrc-simple-yurii-note` で運用。
