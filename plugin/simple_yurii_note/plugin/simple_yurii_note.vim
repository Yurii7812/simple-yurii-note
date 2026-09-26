" =============================================================================
" plugin/simple_yurii_note.vim
" simple_yurii_note - Vimwiki 非依存 Markdown PKM プラグイン
" =============================================================================

if exists('g:loaded_simple_yurii_note')
  finish
endif
let g:loaded_simple_yurii_note = 1

" ---------------------------------------------------------------------------
" デフォルト設定
" ---------------------------------------------------------------------------

" このプラグインは nc/np/ca/bu/bc/mp/mm/tt/yn/gm/gp/pe 等、素の単発
" コマンド（a, n, c, b, m, t, y, g, p, …）と1文字目が被る2文字マッピングを
" 大量に持つ。Vimの既定 timeoutlen=1000ms のままだと、それらの素の1文字
" キーを押すたびに「2文字目が来るかどうか」を最大1秒待ってから確定する
" ため、素のVimと比べて a 等の反応が明らかに遅く感じる。
" 該当キーの体感を悪化させずに待ち時間だけ短縮する（0 で変更しない）。
" 300msだと nt 等（1文字目と2文字目の間隔が nc 等より空きがち）が
" タイムアウトで無反応になることがあったため 500ms に調整。
if !exists('g:simple_yurii_note_timeoutlen')
  let g:simple_yurii_note_timeoutlen = 500
endif
if g:simple_yurii_note_timeoutlen > 0
  let &timeoutlen = g:simple_yurii_note_timeoutlen
endif

if !exists('g:simple_yurii_note_root')
  let g:simple_yurii_note_root = ''
endif
if !exists('g:simple_yurii_note_default_child_prefix')
  let g:simple_yurii_note_default_child_prefix = 'C'
endif
if !exists('g:simple_yurii_note_default_quick_prefix')
  let g:simple_yurii_note_default_quick_prefix = 'F'
endif
if !exists('g:simple_yurii_note_default_atomic_prefix')
  let g:simple_yurii_note_default_atomic_prefix = 'C'
endif
if !exists('g:simple_yurii_note_history_max')
  let g:simple_yurii_note_history_max = 200
endif
if !exists('g:simple_yurii_note_history')
  let g:simple_yurii_note_history = []
endif
" autosync: 保存後に自動更新するか (1=有効, 0=無効)
if !exists('g:simple_yurii_note_autosync')
  let g:simple_yurii_note_autosync = 1
endif
if !exists('g:simple_yurii_note_auto_save_on_command')
  " Heavy: saving on every :command causes CmdlineLeave lag and accidental redraw/reload.
  let g:simple_yurii_note_auto_save_on_command = 0
endif
if !exists('g:simple_yurii_note_sync_before_link_navigation')
  " Link jumps must stay instant; save-time AutoSync keeps links consistent.
  let g:simple_yurii_note_sync_before_link_navigation = 0
endif
if !exists('g:simple_yurii_note_save_before_link_navigation')
  " Do not write/trigger BufWritePost just because Enter follows a link.
  let g:simple_yurii_note_save_before_link_navigation = 0
endif
if !exists('g:simple_yurii_note_global_bare_link_navigation')
  " Avoid recursive root scans on Enter for bare filenames by default.
  let g:simple_yurii_note_global_bare_link_navigation = 0
endif
if !exists('g:simple_yurii_note_realtime_link_sync')
  " Heavy: TextChanged scans and may write linked notes; keep save-time sync as default.
  let g:simple_yurii_note_realtime_link_sync = 0
endif
if !exists('g:simple_yurii_note_realtime_link_sync_delay')
  let g:simple_yurii_note_realtime_link_sync_delay = 800
endif
if !exists('g:simple_yurii_note_realtime_link_sync_max_lines')
  let g:simple_yurii_note_realtime_link_sync_max_lines = 2000
endif
if !exists('g:simple_yurii_note_realtime_backlink_sync')
  let g:simple_yurii_note_realtime_backlink_sync = 0
endif
if !exists('g:simple_yurii_note_markdown_conceal_links')
  " Keep link URLs hidden by default; large/long-link buffers are guarded below.
  let g:simple_yurii_note_markdown_conceal_links = 1
endif
if !exists('g:simple_yurii_note_markdown_conceal_max_lines')
  let g:simple_yurii_note_markdown_conceal_max_lines = 2000
endif
if !exists('g:simple_yurii_note_markdown_conceal_max_line_length')
  let g:simple_yurii_note_markdown_conceal_max_line_length = 1000
endif
" リンク色は .vimrc 側で設定する想定

" Python スクリプトのパス
let s:plugin_root = fnamemodify(expand('<sfile>:p'), ':h:h')

" ノート形式。既定 'v2' = --- 境界 + 型付きセクション（詳細は repo の NOTE_FORMAT.md）。
" 旧 Parent:/Child:/BackLink: 形式に固定したい場合のみ 'v1' を明示する。
" v1 のノートは v2 sync で初回に自動変換される（Parent/Child リンク -> 関連:、Index -> グループ:）。
if !exists('g:simple_yurii_note_format')
  let g:simple_yurii_note_format = 'v2'
endif
if !exists('g:simple_yurii_note_python')
  if g:simple_yurii_note_format ==# 'v1'
    let g:simple_yurii_note_python = s:plugin_root . '/python/simple_yurii_note_sync.py'
  else
    let g:simple_yurii_note_python = s:plugin_root . '/python/note_format_v2.py'
  endif
endif
if !exists('g:simple_yurii_note_expand_s_python')
  let g:simple_yurii_note_expand_s_python = s:plugin_root . '/python/expand_s.py'
endif
if !exists('g:simple_yurii_note_expand_v2_python')
  let g:simple_yurii_note_expand_v2_python = s:plugin_root . '/python/expand_v2.py'
endif
if !exists('g:simple_yurii_note_gallery_python')
  let g:simple_yurii_note_gallery_python = s:plugin_root . '/python/gallery.py'
endif
if !exists('g:simple_yurii_note_gallery_port')
  let g:simple_yurii_note_gallery_port = 8765
endif

" ---------------------------------------------------------------------------
" コマンド定義
" ---------------------------------------------------------------------------

command! -nargs=? UpdateMD   call simple_yurii_note#update_md(<q-args>)
command! -nargs=? UpdateAll  call simple_yurii_note#update_all(<q-args>)
command! -nargs=? UpdateALL  call simple_yurii_note#update_all(<q-args>)
command!          CheckPrefix call simple_yurii_note#check_missing_prefix_in_current_dir()
command! -nargs=* NF         call simple_yurii_note#new_quick(<q-args>)
command!          NA         call simple_yurii_note#new_here_typed('A')
command! -nargs=? NP         call simple_yurii_note#v2_new_parent(<q-args>)
command! -nargs=? NC         call simple_yurii_note#v2_new_child(<q-args>)
command!          NH         call simple_yurii_note#v2_new_here()
command! -nargs=? V2Migrate  call simple_yurii_note#v2_migrate(<q-args>)
command! -nargs=* CA         call simple_yurii_note#add_clipboard_to_branch()
command! -nargs=* CU         call simple_yurii_note#add_clipboard_before_up()
command! -nargs=* TT         call simple_yurii_note#add_clipboard_to_top()
command! -nargs=? NT         call simple_yurii_note#rename_title(<q-args>)
command! -nargs=? RenameLinkText call simple_yurii_note#rename_link_text(<q-args>)
command! -range=0 RenameChildLinkTitles call simple_yurii_note#rename_down_links_to_yaml_title(<line1>, <line2>, <range>)
command! -range=0 RenameDownLinkTitles call simple_yurii_note#rename_down_links_to_yaml_title(<line1>, <line2>, <range>)
command! -nargs=? LT         call simple_yurii_note#rename_link_text(<q-args>)
command! -nargs=* BC         call simple_yurii_note#add_from_clipboard(<f-args>)
command!          YN         call simple_yurii_note#yank_name()
command!          AT         call simple_yurii_note#at_add()
command!          Linkify    call simple_yurii_note#linkify_filename_under_cursor()
command!          LinkifySelection call simple_yurii_note#linkify_selection_new_note()
command!          LinkFixedToggle call simple_yurii_note#toggle_fixed_link_text_under_cursor()
command!          PasteLink  call simple_yurii_note#paste_clipboard_link_here()
command! -range=0 ToggleCheckbox call simple_yurii_note#toggle_checkbox(<line1>, <line2>, <range>)
command!          SortYomi   call simple_yurii_note#sort_yomi()
command! -range=0 -bang SortTime call simple_yurii_note#sort_time(<bang>0, <line1>, <line2>, <range>)
command!          SimpleIndex call simple_yurii_note#open_index()
command!          SimpleChooseIndexDir call simple_yurii_note#choose_index_root()
command!          SimpleGuide call simple_yurii_note#write_guide()
command!          SimpleChooseIndex call simple_yurii_note#choose_index_root()
command! -nargs=? ExpandLinks call simple_yurii_note#expand_s_under_cursor(<q-args>)
command!          JumpLastLinkBeforeParent call simple_yurii_note#jump_last_link_before_up()
command!          JumpParent call simple_yurii_note#jump_up()
command!          JumpChildTop call simple_yurii_note#jump_down_top()
command!          JumpChildBottom call simple_yurii_note#jump_down_bottom()
command!          JumpLastLinkBeforeUp call simple_yurii_note#jump_last_link_before_up()
command!          JumpUp     call simple_yurii_note#jump_up()
command!          JumpDownTop call simple_yurii_note#jump_down_top()
command!          JumpDownBottom call simple_yurii_note#jump_down_bottom()

command! -nargs=? ExpandToT  call simple_yurii_note#expand_s_under_cursor(<q-args>)
command! -nargs=? SE         call simple_yurii_note#expand_s_under_cursor(<q-args>)
command!          RP         call simple_yurii_note#rename_prefix()
command!          OutlineEdit call simple_yurii_note#outline_edit()
command! -nargs=? Gallery    call simple_yurii_note#open_gallery(<q-args>)
command! -nargs=? SimpleGallery call simple_yurii_note#open_gallery(<q-args>)
command! -nargs=? GalleryFolder call simple_yurii_note#open_folder_gallery(<q-args>)
command! -nargs=? SimpleGalleryFolder call simple_yurii_note#open_folder_gallery(<q-args>)
" テーブル操作コマンド
command! -nargs=* TN         call simple_yurii_note#table_new(<q-args>)
command! -nargs=* NewTable   call simple_yurii_note#table_new(<q-args>)
command!          TA         call simple_yurii_note#table_align_current()
command!          TRE        call simple_yurii_note#table_row_edit()
command!          TCSV       call simple_yurii_note#table_csv_edit()
command!          TableCsvEdit call simple_yurii_note#table_csv_edit()
command!          TableCsvApplySaved call simple_yurii_note#table_csv_editor_apply_saved()
command!          TCE        call simple_yurii_note#table_to_csv()
command!          TableToCsv call simple_yurii_note#table_to_csv()
command!          CsvToTable call simple_yurii_note#csv_to_table()
command!          TableCsvNew call simple_yurii_note#csv_new()
command!          TCN        call simple_yurii_note#csv_new()
command!          TDR        call simple_yurii_note#table_del_row()
command!          TDC        call simple_yurii_note#table_del_col()
command!          TAR        call simple_yurii_note#table_add_row()
command!          TAC        call simple_yurii_note#table_add_col()
command! -nargs=* SimpleTable call simple_yurii_note#table_new(<q-args>)

nnoremap <silent> \tn  :NewTable<CR>
nnoremap <silent> \ta  :TA<CR>
nnoremap <silent> \te  :TRE<CR>
nnoremap <silent> \tc  :TableToCsv<CR>
nnoremap <silent> \tt  :CsvToTable<CR>
nnoremap <silent> \tnc :TableCsvNew<CR>
nnoremap <silent> \tar :TAR<CR>
nnoremap <silent> \tac :TAC<CR>
nnoremap <silent> \tdr :TDR<CR>
nnoremap <silent> \tdc :TDC<CR>
nnoremap <silent> \ua  :UpdateAll<CR>

nnoremap <silent> \se  <Cmd>call <SID>expand_s_and_open()<CR>
nnoremap <nowait> <silent> mp  <Cmd>call simple_yurii_note#rename_prefix()<CR>

" ---------------------------------------------------------------------------
" キーマッピング
" ---------------------------------------------------------------------------

" リンクナビゲーション
nnoremap <silent> <Tab>    <Cmd>call simple_yurii_note#jump_link(1)<CR>
nnoremap <silent> <S-Tab>  <Cmd>call simple_yurii_note#jump_link(0)<CR>
" 端末によっては Shift-Tab が <Esc>[Z として届くことがあるので保険を入れる
silent! execute "nnoremap <silent> \<Esc>[Z <Cmd>call simple_yurii_note#jump_link(0)<CR>"
nnoremap <silent> <CR>     <Cmd>call simple_yurii_note#open_link_under_cursor()<CR>
nnoremap <silent> <BS>     <Cmd>call simple_yurii_note#go_back()<CR>
" 履歴を前へ（⌫ の対）。戻りが可逆になるので、戻るのを躊躇しなくなる。
nnoremap <silent> <S-BS>   <Cmd>call simple_yurii_note#go_forward()<CR>
nnoremap <silent> \.       <Cmd>call simple_yurii_note#go_forward()<CR>
" 直前ノートとの1キー往復（A⇄B）。読むもの・選ぶものゼロの最速移動。
nnoremap <silent> _        <Cmd>call simple_yurii_note#toggle_alternate()<CR>
" ハブ … \1〜\9 で直行、\H で今のノートを登録、\H0 で一覧
for s:h in range(1, 9)
  execute printf('nnoremap <silent> \%d <Cmd>call simple_yurii_note#hub_jump(%d)<CR>', s:h, s:h)
endfor
unlet s:h
nnoremap <silent> \H       <Cmd>call simple_yurii_note#hub_set()<CR>
nnoremap <silent> \0       <Cmd>call simple_yurii_note#hub_list()<CR>
" <Space> / gs … ノートナビゲータ。状態は「打つ / 打たない」の1つだけ。
"   ⏎ で打つのをやめる、i で打ちに戻る。/ はクエリを消して打つ。
"   打たない状態のキーはローカルでもグローバルでも完全に同じ。
"   スコープ（ローカル=今のノートのリンク / グローバル=全ノート）は ⇥ で切替。
"   上のバー: 「検索 …▏」= 打てる / 「◎ ノート名」「全ノート」= 打たない。
"
"   打たない（コマンド）
"     ラベル(1-0/英字)= ローカルは潜る / 検索結果は移動だけ（⏎ 開く・l 潜る）
"     jk 選択 / gG 端 / ⏎ 開く / ⌫ h 戻る
"     ␣ アンカーを開く / f b プレビュー / c p 子親に追加 / y ヤンク / m M マーク
"     a アンカー移動 / i 打つ / / 消して打つ / ⇥ スコープ / ⎋ 取消
"
"   打つ（入力）
"     打つ=絞る（ラベルが無いので数字もクエリに入る）/ ⌫ 消す(空なら戻る)
"     ↑↓ 選択 / → 潜る / ← 戻る / ⏎ 入力終了 / ⎋ 消して終了 / ⇥ スコープ
"     + - * = も記号としてそのまま打てる（子親追加・マーク・ヤンクは ⏎ で
"     入力を終えたコマンド状態か、英字キー c/p/m/y で行う）
" <S-Space> … ポップアップを出さずカーソルだけ次の関係リンクへ（従来動作）。
nnoremap <silent> <Space>   <Cmd>call simple_yurii_note#relation_link_popup()<CR>
nnoremap <silent> <S-Space> <Cmd>call simple_yurii_note#jump_relation_link(1)<CR>
" 数字 1-9,0 … 本文 → Parent/Child の順で通し番号にした N 番目のリンクへ移動
"（0 は10番目）。該当リンクが無い所ではそのままカウント/行頭移動として働く
"（v:count 付きの 0 や、該当リンクが無いときの生の 0 は素通しされる）。
" 11番目以降は「文字+数字」の2打、1→0順（n1, n2, …, n9, n0, c1, …）。
" 頭文字はこのプラグインが既に2打コマンドの頭文字として使っている
" n/t/c/b/m/p/y のみを使うので、他の生キー（a, i, o 等）とは干渉しない。
" リンクの手前にラベルが仮想テキストで表示されるので、数えずに押す
" キーが分かる（g:simple_yurii_note_link_hints=0 で表示だけ無効化）。
for s:n in range(1, 9)
  execute printf('nnoremap <silent> %d <Cmd>call simple_yurii_note#digit_key(%d, "%d")<CR>', s:n, s:n, s:n)
endfor
nnoremap <silent> 0 <Cmd>call simple_yurii_note#digit_key(10, "0")<CR>
unlet s:n
augroup simple_yurii_note_link_hints
  autocmd!
  autocmd BufEnter,BufWinEnter,TextChanged,InsertLeave *.md call simple_yurii_note#refresh_link_hints()
augroup END
" 標準のジャンプリスト戻りでも、E37 を出さず保存してから移動する
nnoremap <silent> <C-O>    <Cmd>call simple_yurii_note#save_before_normal_jump("\<C-O>")<CR>
nnoremap <nowait> <silent> bu  <Cmd>call simple_yurii_note#jump_last_link_before_up()<CR>
nnoremap <nowait> <silent> ,,  <Cmd>call simple_yurii_note#jump_up()<CR>
nnoremap <nowait> <silent> ,.  <Cmd>call simple_yurii_note#jump_down_top()<CR>
nnoremap <nowait> <silent> ,/  <Cmd>call simple_yurii_note#jump_down_bottom()<CR>

" ノート作成（リレーションは書かず、位置だけを選ぶ）
"   zn … ノート作成。作成後に位置キー1つで、素のリンク 1 行を現ノート側に置く:
"        h=カーソル直下（本文 → 相手には バックリンク:）/ Enter=Child末尾 /
"        o=リンク無し(孤立) / p=Parent末尾。関係（ノート: 等）はあとから手で書く。
"   zk … グループノート作成（attribute: グループ）。位置キーは zn と同じ。
"   zh … カーソル直下にリンク（zn の h と同じ。本文リンク扱い）
" 頭文字は n ではなく z を使う（z は素のVimでも単独では何も起きない接頭辞
" なので、検索リピートの n/N とバッティングしない）。<nowait> は付けない
" — 付けると zk/zn 等より z が即座に確定してしまい、それらに繋がらなくなる。
" timeoutlen 経過後だけ発火する。
nnoremap <nowait> <silent> zh  <Cmd>call simple_yurii_note#v2_new_here()<CR>
nnoremap <nowait> <silent> zn  <Cmd>call simple_yurii_note#v2_new_plain()<CR>
nnoremap <nowait> <silent> zk  <Cmd>call simple_yurii_note#v2_new_group()<CR>
" za: ca（クリップボードのノートを child に追加）と同じだが、関係ピッカーを
" 出さず既定の「ノート」関係で固定する
nnoremap <nowait> <silent> za  <Cmd>call simple_yurii_note#add_clipboard_before_up_note()<CR>
" pe: 現ノートを起点に親/子/文中を辿って 1 つの md へ展開（v2 専用、_tmp/T_<timestamp>.md）。
" シンプル（深さ1つ）/ 詳細（親・子・文中を別々の深さ、前回設定を再利用可）を選ぶ
nnoremap <nowait> <silent> pe  <Cmd>call simple_yurii_note#v2_expand()<CR>
" cu: クリップボードのリンクを Parent: セクションへ追加
nnoremap <nowait> <silent> cu  <Cmd>call simple_yurii_note#add_clipboard_to_branch()<CR>
" ca: クリップボードのリンクを Child: に追加し、リンク先の Parent: に現在ノートを追加
nnoremap <nowait> <silent> ca  <Cmd>call simple_yurii_note#add_clipboard_before_up()<CR>
" \ca: ca と同じ向きだが括弧が逆。今開いているノート側が (ラベル)、相手側に生のラベルを書く
nnoremap <nowait> <silent> \ca  <Cmd>call simple_yurii_note#add_clipboard_before_up_reverse()<CR>
nnoremap <nowait> <silent> tt  <Cmd>call simple_yurii_note#add_clipboard_to_top()<CR>
" zt: 今のノートを相手の ### Parent に追加（カーソル下のリンク or クリップボード）
nnoremap <nowait> <silent> zt  <Cmd>call simple_yurii_note#add_to_parent()<CR>
" zT: 現在タイトルを残して編集
nnoremap <nowait> <silent> zT  <Cmd>call simple_yurii_note#rename_title('')<CR>
" zl: リンク表示名変更（空欄から開始）
nnoremap <nowait> <silent> zl  <Cmd>call simple_yurii_note#rename_link_text_with_default('')<CR>
" zL: 現在のリンク表示名を残して編集
nnoremap <nowait> <silent> zL  <Cmd>call simple_yurii_note#rename_link_text('')<CR>
" zd: Child: のリンク表示名をリンク先 YAML title に更新
nnoremap <nowait> <silent> zd  <Cmd>RenameChildLinkTitles<CR>
vnoremap <nowait> <silent> zd  :<C-u>'<,'>RenameChildLinkTitles<CR>
" ta: クリップボードのファイルのChildに現在ファイルへのリンクを追加
" （旧 at。素の a と1文字目が被り timeoutlen 待ちが発生していたため改名。
"   t は本来「次の1文字を待つ」動作なので、この待ちは違和感が出にくい）
nnoremap <nowait> <silent> ta  <Cmd>call simple_yurii_note#at_add()<CR>
" \at: ta と同じ向きだが括弧が逆。今開いているノート側が (ラベル)、相手側に生のラベルを書く
nnoremap <nowait> <silent> \at  <Cmd>call simple_yurii_note#at_add_reverse()<CR>
" bc: クリップボードのファイル名をChildに追加
nnoremap <nowait> <silent> bc  <Cmd>call simple_yurii_note#add_from_clipboard()<CR>
" yn: 現在のファイル名をヤンク
nnoremap <nowait> <silent> yn  <Cmd>call simple_yurii_note#yank_name()<CR>

" p: システムクリップボードを通常の Vim 動作で貼り付け
nnoremap <silent> p  "+p
" gp: 以前の独自貼り付け（改行末尾を落として行下に追加）
nnoremap <silent> gp <Cmd>call simple_yurii_note#paste_charwise()<CR>
" .: 標準の「直前の変更を繰り返す」動作を明示的に使用する
nnoremap <silent> . .
nnoremap <silent> \l        <Cmd>call simple_yurii_note#linkify_filename_under_cursor()<CR>
xnoremap <silent> \l        :<C-u>call simple_yurii_note#linkify_selection_new_note()<CR>
nnoremap <nowait> <silent> mx  <Cmd>ToggleCheckbox<CR>
xnoremap <nowait> <silent> mx  :<C-u>'<,'>ToggleCheckbox<CR>
nnoremap <silent> \L        <Cmd>call simple_yurii_note#toggle_fixed_link_text_under_cursor()<CR>
nnoremap <silent> \p        <Cmd>call simple_yurii_note#paste_clipboard_link_here()<CR>
xnoremap <silent> \p        :<C-u>call simple_yurii_note#linkify_selection_from_clipboard()<CR>
nnoremap <silent> \oe       <Cmd>OutlineEdit<CR>
nnoremap <silent> \gi       <Cmd>call simple_yurii_note#open_gallery_smart()<CR>

" ---------------------------------------------------------------------------
" Shift-Tab / BackTab の端末互換
" ---------------------------------------------------------------------------

function! s:setup_backtab() abort
  if has('gui_running')
    return
  endif
  " 多くの端末は Shift-Tab を ESC [ Z で送る
  silent! execute "set <S-Tab>=\<Esc>[Z"
endfunction

call s:setup_backtab()
" ---------------------------------------------------------------------------
" expand_s_and_open: \se で展開して T ファイルを警告なしで開く
" ---------------------------------------------------------------------------

function! s:expand_s_and_open() abort
  let l:file = expand('%:p')
  let l:root = fnamemodify(l:file, ':h')
  let l:py   = g:simple_yurii_note_expand_s_python
  let l:cmd  = printf('python3 %s expand_s %s %s 1',
        \ shellescape(l:py),
        \ shellescape(l:file),
        \ shellescape(l:root))
  let l:result = system(l:cmd)
  if v:shell_error
    echohl ErrorMsg | echo 'expand_s failed: ' . l:result | echohl None
    return
  endif
  let l:t_path = substitute(l:result, '\n\+$', '', '')
  " BS で戻れるよう元ファイルを履歴に積む（go_back が期待する辞書形式）
  call add(g:simple_yurii_note_history, {'file': l:file, 'pos': getpos('.')})
  if len(g:simple_yurii_note_history) > g:simple_yurii_note_history_max
    call remove(g:simple_yurii_note_history, 0)
  endif
  " T ファイルを開く
  execute 'keepjumps edit ' . fnameescape(l:t_path)
endfunction




" ---------------------------------------------------------------------------
" Markdown table helpers (vimwiki-like)
"   Insert mode <Tab>/<S-Tab>/<CR> はテーブル内のみ挙動変更
"   コマンド一覧:
"     :TN [{cols} {rows}]  新規テーブル挿入
"     :TA                  整形（列幅を揃える）
"     :TRE                 行を別バッファで編集
"     :TCE                 CSV バッファで編集
"     :TDR / :TDC          行・列を削除
"     :TAR / :TAC          行・列を追加
" ---------------------------------------------------------------------------

augroup simple_yurii_note_table
  autocmd!
  autocmd FileType markdown,vimwiki call s:setup_table_keys()
  autocmd BufRead,BufNewFile *.md   call s:setup_table_keys()
augroup END

function! s:setup_table_keys() abort
  if &l:filetype !=# 'markdown' && &l:filetype !=# 'vimwiki'
    return
  endif
  inoremap <buffer><silent> <Tab>   <Cmd>call simple_yurii_note#table_tab_action()<CR>
  inoremap <buffer><silent> <S-Tab> <Cmd>call simple_yurii_note#table_stab_action()<CR>
  inoremap <buffer><silent> <CR>    <Cmd>call simple_yurii_note#table_cr_action()<CR>
  " <leader>t + 1文字: テーブル操作
  "   ta  整形          te  行編集       tc  CSV編集
  "   tdr 行削除        tdc 列削除
  "   tar 行追加        tac 列追加
  nnoremap <buffer><silent> <leader>ta  <Cmd>TA<CR>
  nnoremap <buffer><silent> <leader>te  <Cmd>TRE<CR>
  nnoremap <buffer><silent> <leader>tc  <Cmd>TCSV<CR>
  nnoremap <buffer><silent> <leader>tdr <Cmd>TDR<CR>
  nnoremap <buffer><silent> <leader>tdc <Cmd>TDC<CR>
  nnoremap <buffer><silent> <leader>tar <Cmd>TAR<CR>
  nnoremap <buffer><silent> <leader>tac <Cmd>TAC<CR>
endfunction

" ---------------------------------------------------------------------------
" Markdown リンクの concealment
"   [テキスト](url)  →  テキスト  のみ表示
"   concealcursor=n で、カーソルがある行だけ展開表示
" ---------------------------------------------------------------------------

augroup simple_yurii_note_conceal
  autocmd!
  autocmd FileType markdown,vimwiki call s:setup_conceal()
  autocmd BufRead,BufNewFile *.md   call s:setup_conceal()
augroup END

function! s:setup_conceal() abort
  if &l:filetype !=# 'markdown' && &l:filetype !=# 'vimwiki'
    return
  endif

  let l:too_large_for_conceal = line('$') > get(g:, 'simple_yurii_note_markdown_conceal_max_lines', 2000)
        \ || max(map(getline(1, min([line('$'), 200])), 'strlen(v:val)')) > get(g:, 'simple_yurii_note_markdown_conceal_max_line_length', 1000)

  if get(g:, 'simple_yurii_note_markdown_conceal_links', 0) && !l:too_large_for_conceal
    setlocal conceallevel=2
    setlocal concealcursor=n
    " conceal + linebreak の組み合わせで、隠した URL 部分を基準に不自然な折返しが
    " 発生しやすいため、markdown では行折返しを通常の wrap に戻す。
    setlocal nolinebreak
  else
    setlocal conceallevel=0
    setlocal concealcursor=
    setlocal linebreak
  endif

  " 再実行時の重複定義を防ぐ
  silent! syntax clear yuriiLinkRegion
  silent! syntax clear yuriiLinkText
  silent! syntax clear yuriiConcealOpen
  silent! syntax clear yuriiConcealClose
  silent! syntax clear yuriiEmptyBracket
  silent! syntax clear yuriiCheckboxBracket
  silent! syntax clear yuriiCheckedBracket

  " リンク全体は region で保持し、見える本文だけを水色にする
  syntax region yuriiLinkRegion start=/\[\ze[^\] \n][^\]\n]*\](\([^)\n]\{1,300}\))/ end=/\](\([^)\n]\{1,300}\))/ keepend oneline contains=yuriiLinkText,yuriiConcealOpen,yuriiConcealClose
  syntax match yuriiLinkText /\%(\[\)\@<=[^\] \n][^\]\n]*\ze\](\([^)\n]\{1,300}\))/ contained
  let l:link_color_gui = get(g:, 'simple_yurii_note_link_color_gui', '#66CCFF')
  let l:link_color_cterm = get(g:, 'simple_yurii_note_link_color_cterm', '81')
  execute 'highlight yuriiLinkText term=underline cterm=underline gui=underline ctermfg=' . l:link_color_cterm . ' guifg=' . l:link_color_gui

  " [ と ](xxx) を隠して、リンク本文だけ見せる
  syntax match yuriiConcealOpen /\[/ contained conceal
  syntax match yuriiConcealClose /\](\([^)\n]\{1,300}\))/ contained conceal
  syntax match yuriiEmptyBracket /\[\]/ containedin=ALL
  syntax match yuriiCheckboxBracket /\[ \]/ containedin=ALL
  syntax match yuriiCheckedBracket /\[[xX]\]/ containedin=ALL
  highlight default link yuriiEmptyBracket Normal
  highlight default link yuriiCheckboxBracket Normal
  highlight default link yuriiCheckedBracket Normal

  " エラー強調を無効化（[] の直後にリンクがある場合などの赤表示を防ぐ）
  highlight default link markdownError Normal
  highlight default link htmlError Normal
  highlight! link markdownError Normal
  highlight! link htmlError Normal
endfunction

" ---------------------------------------------------------------------------
" Persistent undo: ファイルをまたいでも・再起動後も undo 履歴を保持
" ---------------------------------------------------------------------------

if !exists('g:simple_yurii_note_persistent_undo')
  let g:simple_yurii_note_persistent_undo = 1
endif

if g:simple_yurii_note_persistent_undo
  set undofile
  set undolevels=10000
  set undoreload=100000
endif

" ---------------------------------------------------------------------------
" AutoSync: BufWritePost で update_one を起動
" ---------------------------------------------------------------------------

augroup simple_yurii_note_autosync
  autocmd!
  autocmd BufWritePost *.md call s:on_write_post()
  if get(g:, 'simple_yurii_note_realtime_link_sync', 0)
    autocmd BufReadPost,BufEnter *.md call simple_yurii_note#realtime_sync_snapshot()
    autocmd TextChanged,TextChangedI *.md call simple_yurii_note#realtime_sync_on_text_changed()
  endif
  autocmd FileChangedShell *.md let v:fcs_choice = 'reload'
augroup END

function! s:on_write_post() abort
  if !g:simple_yurii_note_autosync | return | endif
  call simple_yurii_note#autosync_on_save()
endfunction

function! s:normalize_cmdline(cmdline) abort
  let l:cmd = trim(a:cmdline)
  while 1
    let l:new = substitute(l:cmd,
          \ '^\c\%(silent!?\|verbose\|keepalt\|keeppatterns\|keepjumps\|lockmarks\|confirm\|noswapfile\)\s\+', '', '')
    if l:new ==# l:cmd
      break
    endif
    let l:cmd = trim(l:new)
  endwhile
  return l:cmd
endfunction

function! s:auto_save_before_command() abort
  if !get(g:, 'simple_yurii_note_auto_save_on_command', 1)
    return
  endif
  if getcmdtype() !=# ':'
    return
  endif
  if &buftype !=# '' || !&modifiable || !&modified || empty(expand('%:p'))
    return
  endif

  let l:cmd = s:normalize_cmdline(getcmdline())
  if empty(l:cmd)
    return
  endif

  " 保存せずに抜けたい系のコマンドは除外
  if l:cmd =~# '^\c\%(q\%[uit]\|qa\%[ll]\|cq\%[uit]\|cquit\|bd\%[elete]\|bw\%[ipeout]\|bunload\|bdel\|bwipe\)\>.*!\?$'
    return
  endif

  silent! update
endfunction

augroup simple_yurii_note_auto_save_on_command
  autocmd!
  autocmd CmdlineLeave : call s:auto_save_before_command()
augroup END

augroup simple_yurii_note_startup_root_init
  autocmd!
  autocmd VimEnter * ++once call simple_yurii_note#startup_restore_root()
augroup END

" 起動時に操作ガイドを最新のテンプレートへ更新（プラグイン更新に追従）。
augroup simple_yurii_note_guide_refresh
  autocmd!
  autocmd VimEnter * ++once call simple_yurii_note#refresh_guide()
augroup END

augroup simple_yurii_note_startup_prefix_check
  autocmd!
augroup END

" ---------------------------------------------------------------------------
" CopyStack コマンド
" ---------------------------------------------------------------------------
nnoremap <silent> \sc <Cmd>CopyStack<CR>
command! CopyStack call simple_yurii_note#stack_copy_toggle()
