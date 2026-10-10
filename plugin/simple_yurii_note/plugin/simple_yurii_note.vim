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
  " 1 万行の Index でもリンクをたたんで表示名だけ見せる（0 で無制限）。
  " 実測で 1 万行の描画は conceal 有無で差が出ないため既定を引き上げた。
  let g:simple_yurii_note_markdown_conceal_max_lines = 20000
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
    let g:simple_yurii_note_python = s:plugin_root . '/legacy/simple_yurii_note_sync.py'
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

" :!rm % / :silent !rm % など Vim の :! でノートを消してもゴミ箱へ回す（bash 限定）。
" 非対話 bash が $BASH_ENV を読む性質を使い、rm をラップする（shell/yurii-note-rm-guard.sh）。
if !exists('g:simple_yurii_note_rm_guard')
  let g:simple_yurii_note_rm_guard = 1
endif
if g:simple_yurii_note_rm_guard && !has('win32') && executable('bash')
  let s:rm_guard = s:plugin_root . '/shell/yurii-note-rm-guard.sh'
  if filereadable(s:rm_guard)
    if empty($BASH_ENV)
      let $BASH_ENV = s:rm_guard
    elseif $BASH_ENV !=# s:rm_guard
      let g:simple_yurii_note_rm_guard = 0
      echohl WarningMsg | echom 'simple_yurii_note: $BASH_ENV が既にあるため rm ゴミ箱ガードは無効' | echohl NONE
    endif
  endif
endif

augroup simple_yurii_note_shell_trash
  autocmd!
  " :!rm などでノートのファイルが消えていたら、バッファを閉じて同期する
  autocmd ShellCmdPost * call simple_yurii_note#after_shell_rm()
augroup END

" 挿入モードの <C-G> が timeoutlen 待ちにならないようにする。
" vim-surround は挿入モードに <C-G>s / <C-G>S / <C-S> を張るため、素の
" <C-G>u（undo 区切り）などが「s が続くかも」で待たされる。挿入モードの
" surround を使わないなら無効化してよい（ノーマル/ビジュアルの ys/cs/ds/S は残る）。
if !exists('g:surround_no_insert_mappings')
  let g:surround_no_insert_mappings = 1
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
command!          PasteLink  call simple_yurii_note#paste_clipboard_link_here()
command! -range=0 ToggleCheckbox call simple_yurii_note#toggle_checkbox(<line1>, <line2>, <range>)
command!          SortYomi   call simple_yurii_note#sort_yomi()
command! -range=0 -bang SortTime call simple_yurii_note#sort_time(<bang>0, <line1>, <line2>, <range>)
command!          SimpleIndex call simple_yurii_note#open_index()
command!          SimpleChooseIndexDir call simple_yurii_note#choose_index_root()
command!          SimpleGuide call simple_yurii_note#write_guide()
command!          SimpleChooseIndex call simple_yurii_note#choose_index_root()
" 紙のPKM（フォルゲゼッテル）: Index 作成/オープンと、スキャン画像の番号付け GUI
command!          SimplePaperIndex call simple_yurii_note#paper_index()
command!          SimpleScan call simple_yurii_note#paper_scan()

" 旧名エイリアス（yurii_PKM から移行した習慣用。中身は simple 側）
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
command!          SimpleWeb  call simple_yurii_note#open_web()
" ゴミ箱（ソフト削除）
command!          SimpleTrash      call simple_yurii_note#trash_current()
command!          SimpleTrashList  call simple_yurii_note#trash_list()
command!          SimpleTrashEmpty call simple_yurii_note#trash_empty()
" vault の gocryptfs パスワード変更（マウント中は不可。閉じてから実行）
command!          SimpleSetPassword call simple_yurii_note#set_password()
command!          SimpleYuriinoteSetPassword call simple_yurii_note#set_password()
" vault の暗号化を解除して平文に戻す（A/note + A/.crypt → A 直下）
command!          SimpleRemovePassword call simple_yurii_note#remove_password()
command!          SimpleYuriinoteRemovePassword call simple_yurii_note#remove_password()
" vault の手動ロック解除 / ロック（gocryptfs）
command!          SimpleMount call simple_yurii_note#mount_vault()
command!          SimpleLock  call simple_yurii_note#lock_vault()
" 終了時に vault 外へ残留させない（recent.json / viminfo を消す）
command!          SimpleExitCleanup call simple_yurii_note#exit_cleanup()
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

" ---- SN* の統一別名（既存の名前と同じ動作。既存は残す） ----
" 入口だけのコマンド（:PlugInstall 等の prefix と同じ役割）。Tab で SN* の候補を出す用。
command! -nargs=0 SN echo 'SN* のコマンドは :SN<Tab> で候補を表示'
command! -nargs=0 Yurii echo 'Yurii* のコマンドは :Yurii<Tab> で候補を表示'
command! -nargs=? SNUpdateMD call simple_yurii_note#update_md(<q-args>)
command! -nargs=? SNUpdateAll call simple_yurii_note#update_all(<q-args>)
command!          SNCheckPrefix call simple_yurii_note#check_missing_prefix_in_current_dir()
command! -nargs=* SNNF call simple_yurii_note#new_quick(<q-args>)
command!          SNNA call simple_yurii_note#new_here_typed('A')
command! -nargs=? SNNP call simple_yurii_note#v2_new_parent(<q-args>)
command! -nargs=? SNNC call simple_yurii_note#v2_new_child(<q-args>)
command!          SNNH call simple_yurii_note#v2_new_here()
command! -nargs=? SNV2Migrate call simple_yurii_note#v2_migrate(<q-args>)
command! -nargs=* SNCA call simple_yurii_note#add_clipboard_to_branch()
command! -nargs=* SNCU call simple_yurii_note#add_clipboard_before_up()
command! -nargs=* SNTT call simple_yurii_note#add_clipboard_to_top()
command! -nargs=? SNNT call simple_yurii_note#rename_title(<q-args>)
command! -nargs=? SNRenameLinkText call simple_yurii_note#rename_link_text(<q-args>)
command! -range=0 SNRenameChildLinkTitles call simple_yurii_note#rename_down_links_to_yaml_title(<line1>, <line2>, <range>)
command! -range=0 SNRenameDownLinkTitles call simple_yurii_note#rename_down_links_to_yaml_title(<line1>, <line2>, <range>)
command! -nargs=? SNLT call simple_yurii_note#rename_link_text(<q-args>)
command! -nargs=* SNBC call simple_yurii_note#add_from_clipboard(<f-args>)
command!          SNYN call simple_yurii_note#yank_name()
command!          SNAT call simple_yurii_note#at_add()
command!          SNLinkify call simple_yurii_note#linkify_filename_under_cursor()
command!          SNLinkifySelection call simple_yurii_note#linkify_selection_new_note()
command!          SNPasteLink call simple_yurii_note#paste_clipboard_link_here()
command! -range=0 SNToggleCheckbox call simple_yurii_note#toggle_checkbox(<line1>, <line2>, <range>)
command!          SNSortYomi call simple_yurii_note#sort_yomi()
command! -range=0 -bang SNSortTime call simple_yurii_note#sort_time(<bang>0, <line1>, <line2>, <range>)
command!          SNIndex call simple_yurii_note#open_index()
command!          SNChooseIndexDir call simple_yurii_note#choose_index_root()
command!          SNChooseIndex call simple_yurii_note#choose_index_root()
command!          SNGuide call simple_yurii_note#write_guide()
command!          SNPaperIndex call simple_yurii_note#paper_index()
command!          SNScan call simple_yurii_note#paper_scan()
command! -nargs=? SNExpandLinks call simple_yurii_note#expand_s_under_cursor(<q-args>)
command! -nargs=? SNExpandToT call simple_yurii_note#expand_s_under_cursor(<q-args>)
command! -nargs=? SNSE call simple_yurii_note#expand_s_under_cursor(<q-args>)
command!          SNJumpLastLinkBeforeParent call simple_yurii_note#jump_last_link_before_up()
command!          SNJumpLastLinkBeforeUp call simple_yurii_note#jump_last_link_before_up()
command!          SNJumpParent call simple_yurii_note#jump_up()
command!          SNJumpUp call simple_yurii_note#jump_up()
command!          SNJumpChildTop call simple_yurii_note#jump_down_top()
command!          SNJumpDownTop call simple_yurii_note#jump_down_top()
command!          SNJumpChildBottom call simple_yurii_note#jump_down_bottom()
command!          SNJumpDownBottom call simple_yurii_note#jump_down_bottom()
command!          SNRP call simple_yurii_note#rename_prefix()
command!          SNOutlineEdit call simple_yurii_note#outline_edit()
command! -nargs=? SNGallery call simple_yurii_note#open_gallery(<q-args>)
command! -nargs=? SNGalleryFolder call simple_yurii_note#open_folder_gallery(<q-args>)
command!          SNWeb call simple_yurii_note#open_web()
command!          SNTrash call simple_yurii_note#trash_current()
command!          SNTrashList call simple_yurii_note#trash_list()
command!          SNTrashEmpty call simple_yurii_note#trash_empty()
command!          SNSetPassword call simple_yurii_note#set_password()
command!          SNRemovePassword call simple_yurii_note#remove_password()
command!          SNMount call simple_yurii_note#mount_vault()
command!          SNLock call simple_yurii_note#lock_vault()
command!          SNExitCleanup call simple_yurii_note#exit_cleanup()
command! -nargs=* SNTableNew call simple_yurii_note#table_new(<q-args>)
command!          SNTableAlign call simple_yurii_note#table_align_current()
command!          SNTableRowEdit call simple_yurii_note#table_row_edit()
command!          SNTableCsvEdit call simple_yurii_note#table_csv_edit()
command!          SNTableCsvApplySaved call simple_yurii_note#table_csv_editor_apply_saved()
command!          SNTableToCsv call simple_yurii_note#table_to_csv()
command!          SNCsvToTable call simple_yurii_note#csv_to_table()
command!          SNTableCsvNew call simple_yurii_note#csv_new()
command!          SNTableDelRow call simple_yurii_note#table_del_row()
command!          SNTableDelCol call simple_yurii_note#table_del_col()
command!          SNTableAddRow call simple_yurii_note#table_add_row()
command!          SNTableAddCol call simple_yurii_note#table_add_col()

" 別ファイル（plugin/*.vim）で定義された既存コマンドへの別名
command!          SNRename Rename
command! -range   SNSetImageSize <line1>,<line2>SetImageSize
command!          SNAutocwindow Autocwindow
command!          SNFSearch FSearch
command!          SNLinkPick LinkPick
command! -nargs=+ SNFileContentSearch FileContentSearch <args>
command!          SNCopyStack CopyStack

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
" 注意: 以前は Shift-Tab 保険で `\<Esc>[Z` を nnoremap していたが、これを張ると
" 素の Esc が「[Z が続くかも」と timeoutlen（既定500ms）待つため、Esc がワンテンポ
" 遅れていた。端末互換は s:setup_backtab() の `set <S-Tab>=\e[Z`（termcap）で足りる。
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
" \h … ハブ画面（リンク一覧の編集可能な Markdown）を開く。1-9/0 でそのまま移動できる。
nnoremap <silent> \h       <Cmd>call simple_yurii_note#hub_open()<CR>
nnoremap <silent> \H       <Cmd>call simple_yurii_note#hub_set()<CR>
nnoremap <silent> \0       <Cmd>call simple_yurii_note#hub_list()<CR>
" ゴミ箱（ソフト削除）: \tr=一覧（⏎=開く / ^r=復元 / ^e=空） / \tD=今のノートをゴミ箱へ / \tE=空にする
"   （\td は \tdr/\tdc（表の行・列削除）と待ちが被るので \tD にする）
nnoremap <silent> \tr       <Cmd>call simple_yurii_note#trash_list()<CR>
nnoremap <silent> \tD       <Cmd>call simple_yurii_note#trash_current()<CR>
nnoremap <silent> \tE       <Cmd>call simple_yurii_note#trash_empty()<CR>
" \i … index.md を開く（2打）。\s は \se（展開）の前置きと被って待たされるので使わない。
nnoremap <silent> \i       <Cmd>call simple_yurii_note#open_index()<CR>
" \f … 紙PKM Index を開く（無ければ作成。更新は \ua）
" \F … スキャン画像にフォルゲゼッテルIDを付けて vault 直下へ移動（番号付け GUI）
nnoremap <silent> \f       <Cmd>call simple_yurii_note#paper_index()<CR>
nnoremap <silent> \F       <Cmd>call simple_yurii_note#paper_scan()<CR>
" \S … リンク行を表示名のよみ順（五十音 → ローマ字は末尾）に安定ソート。
"   ビジュアル=選択範囲 / ノーマル=バッファ全体（主に index.md）。
"   よみはリンク先ノートの front matter `yomi:`（\zy で登録）、無ければ pykakasi。
nnoremap <silent> \S <Cmd>call simple_yurii_note#sort_yomi()<CR>
xnoremap <silent> \S :<C-u>call simple_yurii_note#sort_selection()<CR>
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
  " ノートを開いた時は即時に（1回だけ）。挿入モードを抜けた時（Esc）は
  " 重い再計算（大きいノートで約45ms）を同期でやると Esc がもっさりするので、
  " TextChanged と同じ debounce に回す。ラベルは少し遅れて更新されるが、
  " 数字ジャンプ等は s:hint_positions を直接見るので機能は遅れない。
  autocmd BufEnter,BufWinEnter *.md call simple_yurii_note#refresh_link_hints()
  autocmd TextChanged,InsertLeave *.md call s:schedule_refresh_link_hints()
  " ラベルはドキュメント順で固定なのでスクロールでの振り直しは不要。
augroup END

" 連続する TextChanged をまとめて、最後の 1 回だけヒントを更新する。
function! s:schedule_refresh_link_hints() abort
  if exists('b:simple_yurii_note_hint_timer')
    call timer_stop(b:simple_yurii_note_hint_timer)
  endif
  if has('timers')
    let b:simple_yurii_note_hint_timer =
          \ timer_start(get(g:, 'simple_yurii_note_link_hints_delay', 120),
          \ {-> simple_yurii_note#refresh_link_hints()})
  else
    call simple_yurii_note#refresh_link_hints()
  endif
endfunction
" 標準のジャンプリスト戻りでも、E37 を出さず保存してから移動する
nnoremap <silent> <C-O>    <Cmd>call simple_yurii_note#save_before_normal_jump("\<C-O>")<CR>
" \bu（旧 bu）: 「b」は素の後退移動と1文字目が被り、素の b が timeoutlen 待ちに
"   なるため \ 側へ移した（素のキーを即時にする）
nnoremap <nowait> <silent> \bu <Cmd>call simple_yurii_note#jump_last_link_before_up()<CR>
" \k / \j / \J（旧 ,, / ,. / ,/）: 1文字目が素の「,」（f/t リピート）と被り
" timeoutlen 待ちになるため \ 側へ移した。k=上 / j=下 の連想。
nnoremap <nowait> <silent> \k  <Cmd>call simple_yurii_note#jump_up()<CR>
nnoremap <nowait> <silent> \j  <Cmd>call simple_yurii_note#jump_down_top()<CR>
nnoremap <nowait> <silent> \J  <Cmd>call simple_yurii_note#jump_down_bottom()<CR>

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
" zk（ビジュアル）… 選択範囲を中身にしたグループノートを作る（選択はグループへのリンクに置換）。
xnoremap <nowait> <silent> zk  :<C-u>call simple_yurii_note#v2_new_group_visual()<CR>
" za: ca（クリップボードのノートを child に追加）と同じだが、関係ピッカーを
" 出さず既定の「ノート」関係で固定する
nnoremap <nowait> <silent> za  <Cmd>call simple_yurii_note#add_clipboard_before_up_note()<CR>
" zA: za と同じだが、追加前に「表示名」を入力する（既定は za が使う表示名。
"     空 Enter / Esc で中止）。Vim 標準の折りたたみ zA は上書きされる。
nnoremap <nowait> <silent> zA  <Cmd>call simple_yurii_note#add_clipboard_before_up_note_named()<CR>
" \e（旧 pe）: 現ノートを起点に親/子/文中/関連を辿って 1 つの md へ展開（v2 専用、.trash/T_<timestamp>.md）。
" シンプル（深さ1つ）/ 詳細（親・子・文中・関連を別々の深さ、前回設定を再利用可）を選ぶ。
" 「p」は素の貼り付けと1文字目が被り、素の p が timeoutlen 待ちになるため \ 側へ移した。
nnoremap <nowait> <silent> \e  <Cmd>call simple_yurii_note#v2_expand()<CR>
" cu: クリップボードのリンクを Parent: セクションへ追加
nnoremap <nowait> <silent> cu  <Cmd>call simple_yurii_note#add_clipboard_to_branch()<CR>
" ca: クリップボードのリンクを Child: に追加し、リンク先の Parent: に現在ノートを追加
nnoremap <nowait> <silent> ca  <Cmd>call simple_yurii_note#add_clipboard_before_up()<CR>
" \ca: ca と同じ向きだが括弧が逆。今開いているノート側が (ラベル)、相手側に生のラベルを書く
nnoremap <nowait> <silent> \ca  <Cmd>call simple_yurii_note#add_clipboard_before_up_reverse()<CR>
nnoremap <nowait> <silent> tt  <Cmd>call simple_yurii_note#add_clipboard_to_top()<CR>
" zt: タイトル変更（空欄から開始）
nnoremap <nowait> <silent> zt  <Cmd>call simple_yurii_note#rename_title_with_default('')<CR>
" zp: 今開いてるノート（のリンク）を、相手（カーソル下のリンク or クリップボード）の
"     ### Parent に追加 ＝ 今のノートが相手の子になる（相手側の子リストに今のノート）
"     対になる操作: za は「今のノートの子」= 今のノートにリンクを足す（Parent の直前）
nnoremap <nowait> <silent> zp  <Cmd>call simple_yurii_note#add_clipboard_as_child_with_parent()<CR>
" zT: 現在タイトルを残して編集
nnoremap <nowait> <silent> zT  <Cmd>call simple_yurii_note#rename_title('')<CR>
" zl: リンク表示名変更（空欄から開始）
nnoremap <nowait> <silent> zl  <Cmd>call simple_yurii_note#rename_link_text_with_default('')<CR>
" zL: 現在のリンク表示名を残して編集
nnoremap <nowait> <silent> zL  <Cmd>call simple_yurii_note#rename_link_text('')<CR>
" zy: 今開いているノートのタイトルのよみを
"     空欄から変更する（zt と同じ流儀。Esc で中止）。
"     よみは \S / :SortYomi の表示名ソートで使う。
nnoremap <nowait> <silent> zy  <Cmd>call simple_yurii_note#rename_yomi_with_default('')<CR>
" zY: 現在のよみ（未登録なら pykakasi 推測）を残して編集（zT と同じ流儀。
"     全部消して Enter でよみを削除）。
nnoremap <nowait> <silent> zY  <Cmd>call simple_yurii_note#rename_yomi('')<CR>
" zd: Child: のリンク表示名をリンク先 YAML title に更新
nnoremap <nowait> <silent> zd  <Cmd>RenameChildLinkTitles<CR>
vnoremap <nowait> <silent> zd  :<C-u>'<,'>RenameChildLinkTitles<CR>
" ta: クリップボードのファイルのChildに現在ファイルへのリンクを追加
" （旧 at。素の a と1文字目が被り timeoutlen 待ちが発生していたため改名。
"   t は本来「次の1文字を待つ」動作なので、この待ちは違和感が出にくい）
nnoremap <nowait> <silent> ta  <Cmd>call simple_yurii_note#at_add()<CR>
" \at: ta と同じ向きだが括弧が逆。今開いているノート側が (ラベル)、相手側に生のラベルを書く
nnoremap <nowait> <silent> \at  <Cmd>call simple_yurii_note#at_add_reverse()<CR>
" \bc（旧 bc）: クリップボードのファイル名をChildに追加。
" 「b」は素の後退移動と1文字目が被り、素の b が timeoutlen 待ちになるため \ 側へ移した。
nnoremap <nowait> <silent> \bc <Cmd>call simple_yurii_note#add_from_clipboard()<CR>
" yn: 現在のファイル名をヤンク
nnoremap <nowait> <silent> yn  <Cmd>call simple_yurii_note#yank_name()<CR>

" \v / \V: システムクリップボード（PCの直近のコピー / Vimでヤンクしたもの）を貼り付け。
"   p / P は Vim 標準のまま（" レジスタ）。PC の内容は \v で貼る。
nnoremap <silent> \v <Cmd>call simple_yurii_note#paste_clipboard('p', v:count)<CR>
nnoremap <silent> \V <Cmd>call simple_yurii_note#paste_clipboard('P', v:count)<CR>
" gp: 以前の独自貼り付け（改行末尾を落として行下に追加）
nnoremap <silent> gp <Cmd>call simple_yurii_note#paste_charwise()<CR>
" .: 標準の「直前の変更を繰り返す」動作を明示的に使用する
nnoremap <silent> . .
nnoremap <silent> \l        <Cmd>call simple_yurii_note#linkify_filename_under_cursor()<CR>
xnoremap <silent> \l        :<C-u>call simple_yurii_note#linkify_selection_new_note()<CR>
nnoremap <nowait> <silent> mx  <Cmd>ToggleCheckbox<CR>
xnoremap <nowait> <silent> mx  :<C-u>'<,'>ToggleCheckbox<CR>
nnoremap <silent> \p        <Cmd>call simple_yurii_note#paste_clipboard_link_here()<CR>
xnoremap <silent> \p        :<C-u>call simple_yurii_note#linkify_selection_from_clipboard()<CR>
" \P … カーソル下の .md リンク先の Parent に、今のノートを確認なしで足す。
" （\p とは別キー。\p の確認プロンプトは廃止したので、必要なときはこれ）
nnoremap <nowait> <silent> \P <Cmd>call simple_yurii_note#add_current_as_parent_here()<CR>
nnoremap <silent> \oe       <Cmd>OutlineEdit<CR>
" zo … カーソル下の .md リンク先ノートの見出し（アウトライン）を選び、
" リンク先に #スラッグ（GitHub 互換）を付ける。先頭の「（見出しなし）」で解除。
nnoremap <nowait> <silent> zo <Cmd>call simple_yurii_note#link_to_outline()<CR>
nnoremap <silent> \gi       <Cmd>call simple_yurii_note#open_gallery_smart()<CR>
" アプリ (Electron / ブラウザ) を開く。vault はアプリ側 (既定 ~/files/yurii-note)。
" 既定では使われていない \A。(\w は other.vim の :wa なので使わない)
nnoremap <silent> \A        <Cmd>call simple_yurii_note#open_web()<CR>

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
"     :TCE                 テーブルを同じページで CSV 行に変換（逆は :CsvToTable）
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
"   ノーマルモードではカーソル行でも中身を隠す（concealcursor=n）。
"   挿入モード（とビジュアル/選択）ではカーソル行を展開し、中身が見える。
"   隠れた範囲の上にはカーソルを表示できないため、←/→ は隠れた範囲を
"   まとめて飛び越える（simple_yurii_note#move_visible）。
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

  let l:max_lines = get(g:, 'simple_yurii_note_markdown_conceal_max_lines', 20000)
  let l:too_large_for_conceal = (l:max_lines > 0 && line('$') > l:max_lines)
        \ || max(map(getline(1, min([line('$'), 200])), 'strlen(v:val)'))
        \    > get(g:, 'simple_yurii_note_markdown_conceal_max_line_length', 1000)

  if get(g:, 'simple_yurii_note_markdown_conceal_links', 0) && !l:too_large_for_conceal
    setlocal conceallevel=2
    " ノーマルモードではカーソル行も含めて中身を隠す（表示名だけ見せる）。
    " 挿入モードは concealcursor に i が無いのでカーソル行が展開され、中身が
    " 見える。隠れた範囲の上では素の ←/→ が止まって見えるため、
    " move_visible で隠れた範囲をまとめて飛び越える。
    setlocal concealcursor=n
    nnoremap <buffer><silent> <Right> <Cmd>call simple_yurii_note#move_visible(1)<CR>
    nnoremap <buffer><silent> <Left>  <Cmd>call simple_yurii_note#move_visible(0)<CR>
    " conceal + linebreak の組み合わせで、隠した URL 部分を基準に不自然な折返しが
    " 発生しやすいため、markdown では行折返しを通常の wrap に戻す。
    setlocal nolinebreak
  else
    setlocal conceallevel=0
    setlocal concealcursor=
    silent! nunmap <buffer> <Left>
    silent! nunmap <buffer> <Right>
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

  " リンク全体は region で保持し、見える本文だけを水色にする。
  " containedin=... が要る: 日本語の直後の `_` は Vim の markdown 斜体
  " （markdownItalic は `\w\@<!_\S\@=` で、非 ASCII の前では開始してしまう）に
  " 飲み込まれ、閉じ `_` が無いと行をまたいで本文全体が斜体扱いになる。その中は
  " トップレベルの構文が効かず、リンクの conceal が丸ごと無効になっていた。
  " リンクは斜体/太字の中でもリンクとして見せる（この環境の日本語名は
  " `_00001` を含むため実質必須）。
  syntax region yuriiLinkRegion start=/\[\ze[^\] \n][^\]\n]*\](\([^)\n]\{1,300}\))/ end=/\](\([^)\n]\{1,300}\))/ keepend oneline contains=yuriiLinkText,yuriiConcealOpen,yuriiConcealClose containedin=markdownItalic,markdownBold,markdownBoldItalic
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
" AutoSave: 「保存が要る瞬間」に vault の .md / .csv を自動書き込み
"   g:simple_yurii_note_autosave        (既定 1。0 で無効)
"   g:simple_yurii_note_autosave_delay  (既定 1500ms。最後の変更からこの時間で保存)
"   - 対象は vault 配下の .md / .csv（同期が走るのは .md だけ）
"   - 無操作デバウンス（挿入・置換中も含む）+ Esc で即保存 +
"     バッファ/ウィンドウを離れるとき即保存
"   - 外部アプリで開く前（gm / \A）・ゴミ箱へ移す前（\tD）・同期の前も
"     呼び出し側が simple_yurii_note#save_current_note() で書き出す
"   - ターミナルを×で閉じる（SIGHUP）は Vim 側でフックできないため、
"     挿入中でも短めのデバウンスで書き、未保存の窓を小さくしている
" ---------------------------------------------------------------------------

if !exists('g:simple_yurii_note_autosave')
  let g:simple_yurii_note_autosave = 1
endif
if !exists('g:simple_yurii_note_autosave_delay')
  let g:simple_yurii_note_autosave_delay = 1500
endif

function! s:schedule_autosave() abort
  if !g:simple_yurii_note_autosave || !has('timers') | return | endif
  if exists('s:autosave_timer') && s:autosave_timer > 0
    call timer_stop(s:autosave_timer)
  endif
  let s:autosave_timer = timer_start(g:simple_yurii_note_autosave_delay,
        \ {-> s:autosave_now()})
endfunction

function! s:autosave_now(...) abort
  let s:autosave_timer = 0
  if !g:simple_yurii_note_autosave
    return
  endif
  " 操作待ち（d の途中）・コマンドライン中・ビジュアル/セレクト選択中はもう一度
  " 待つ。選択中に書くと（保存に続く同期や再読込で）選択が解除されてしまう。
  " 挿入・置換中でも「書くだけ」は安全なので保存する（未保存の窓を小さくするため）。
  let l:mode = mode(1)
  if index(['o', 'c', 'v', 'V', "\<C-v>", 's', 'S', "\<C-s>"], l:mode) >= 0
    call s:schedule_autosave()
    return
  endif
  call s:autosave_write()
endfunction

" 対象（vault 配下の .md / .csv）で modified なら書き出す。
" 書いたら 1、対象外・変更なしなら 0。
function! s:autosave_write() abort
  if !&modified || &buftype !=# '' || &readonly
    return 0
  endif
  let l:file = expand('%:p')
  if !simple_yurii_note#is_autosave_target(l:file)
    return 0
  endif
  if exists('s:autosave_timer') && s:autosave_timer > 0
    call timer_stop(s:autosave_timer)
    let s:autosave_timer = 0
  endif
  silent! update
  return 1
endfunction

" Esc（挿入モードを抜けた時）は無操作デバウンスを待たず即保存する。
" 保存回数は増えず、保存のタイミングが前倒しになるだけ。
function! s:autosave_on_insert_leave() abort
  if !g:simple_yurii_note_autosave
    return
  endif
  " InsertLeave の最中は mode() がまだ 'i' のことがあるため、モード判定はしない
  call s:autosave_write()
endfunction

" バッファ/ウィンドウを離れるとき・フォーカスを失ったときは、デバウンスを
" 待たずに今すぐ保存する。リンク間の移動（:buffer 等で既に開いているノートへ
" 移る場合）は 'autowriteall' が効かないため、ここで書き残しを防ぐ。
function! s:autosave_before_leave() abort
  if !g:simple_yurii_note_autosave
    return
  endif
  call s:autosave_write()
endfunction

augroup simple_yurii_note_autosave
  autocmd!
  autocmd TextChanged,TextChangedI *.md,*.csv call s:schedule_autosave()
  autocmd InsertLeave *.md,*.csv call s:autosave_on_insert_leave()
  autocmd BufLeave,WinLeave *.md,*.csv call s:autosave_before_leave()
  autocmd FocusLost *.md,*.csv call s:autosave_before_leave()
augroup END

" ---------------------------------------------------------------------------
" Swap なし + ロックファイル（2026-10-04）
"   vault のノートは swap を作らない（Obsidian 的に .swp の残骸と E325 を無くす。
"   クラッシュ時に失うのは最大で自動保存の間隔ぶんだけ）。
"   アプリとの衝突検知は state dir の PID 入りロックで行う。
" ---------------------------------------------------------------------------

autocmd BufReadPre,BufNewFile *.md if simple_yurii_note#is_vault_path(expand('<afile>:p')) | setlocal noswapfile | endif
" ハブも swap を作らない（vault 外なので上記が効かず、残骸 .swp から E325 と読専化が出る）。
execute 'autocmd BufReadPre,BufNewFile ' . escape(printf('%s/hubs/*.md', simple_yurii_note#state_dir()), '\\ ') . ' setlocal noswapfile noundofile'

augroup simple_yurii_note_lock
  autocmd!
  autocmd BufReadPost,BufNewFile,BufEnter *.md call simple_yurii_note#lock_add(expand('<afile>:p'))
  autocmd BufUnload,BufDelete,VimLeavePre *.md call simple_yurii_note#lock_remove(expand('<afile>:p'))
augroup END

" vault の暗号（gocryptfs箱）
"   ・起動時にロック中ならパスワードを聞いてマウント
"   ・終了時に自動でロック（閉じるとロック）
"   ・:SimpleSetPassword = パスワード変更
" ---------------------------------------------------------------------------
augroup simple_yurii_note_vault
  autocmd!
  autocmd VimEnter  * call simple_yurii_note#maybe_mount_interactive()
  autocmd VimLeave  * call simple_yurii_note#quit_unmount()
  " viminfo は VimLeavePre の後に書かれる。ロック中なら書き先を無効化する
  autocmd VimLeavePre * call simple_yurii_note#before_write_viminfo()
  autocmd BufWritePre * call simple_yurii_note#guard_vault_write(expand('<afile>:p'))
augroup END

autocmd VimEnter * call simple_yurii_note#cleanup_stale_locks()

" 旧 state_dir の状態を vault 内 .state/ へ1回だけ移行（root.txt は残す）
augroup simple_yurii_note_migrate_state
  autocmd!
  autocmd VimEnter * call simple_yurii_note#migrate_state_into_vault()
augroup END

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

" 起動直後の VimEnter 処理（Index を開く・ロック掃除など）の後に、画面を一度描き直す。
" 描き直さないと、Index の下側が空白のまま残る（\r で直る症状）。
augroup simple_yurii_note_startup_redraw
  autocmd!
  autocmd VimEnter * ++once call timer_start(300, {-> execute('redraw!')})
augroup END

augroup simple_yurii_note_startup_prefix_check
  autocmd!
augroup END

" ---------------------------------------------------------------------------
" Wayland クリップボード橋渡し（Vim → PC 方向）
" ---------------------------------------------------------------------------
" Vim（vim.gtk3）の +/* レジスタは XWayland 側のクリップボードを見るため、
" 大きなヤンクを XWayland のブリッジに通すと KWin / Klipper ごと固まることがある。
" そこで X11 側は使わず（other.vim で clipboard= に固定）、`yy` / `x` / `ciw` などの
" 無名レジスタと `"+y` / `"*y` を wl-copy（Wayland ネイティブ）へ流す。
" これで Vim でヤンクした内容を `\v` でも PC 側アプリでも貼れる。
if !has('nvim')
  function! s:wayland_clipboard_yank() abort
    let l:reg = get(v:event, 'regname', '')
    if l:reg !=# '' && l:reg !=# '+' && l:reg !=# '*'
      return
    endif
    let l:lines = get(v:event, 'regcontents', [])
    if empty(l:lines)
      return
    endif
    call simple_yurii_note#clipboard_copy(join(l:lines, "\n"))
  endfunction

  augroup simple_yurii_note_wayland_clipboard
    autocmd!
    autocmd TextYankPost * call s:wayland_clipboard_yank()
  augroup END
endif

" ---------------------------------------------------------------------------
" CopyStack コマンド
" ---------------------------------------------------------------------------
nnoremap <silent> \sc <Cmd>CopyStack<CR>
command! CopyStack call simple_yurii_note#stack_copy_toggle()

" 終了時に recent.json / viminfo を消す（vault 内に寄せたものを残留させない）
augroup simple_yurii_note_exit_cleanup
  autocmd!
  autocmd VimLeave * call simple_yurii_note#exit_cleanup()
augroup END

" ---------------------------------------------------------------------------
