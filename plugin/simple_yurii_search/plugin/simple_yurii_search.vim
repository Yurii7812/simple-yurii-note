" plugin/simple_yurii_search.vim

if exists('g:loaded_simple_yurii_search')
  finish
endif
let g:loaded_simple_yurii_search = 1

" python スクリプトのパス（プラグインロード時に確定）
let s:pydir = expand('<sfile>:p:h:h') . '/python'
if !exists('g:simple_yurii_search_tui')
  let g:simple_yurii_search_tui = s:pydir . '/fsearch_tui.py'
endif
if !exists('g:simple_yurii_search_index')
  let g:simple_yurii_search_index = s:pydir . '/notes_index.py'
endif
if !exists('g:simple_yurii_search_notesearch')
  let g:simple_yurii_search_notesearch = s:pydir . '/note_search.py'
endif

command! -nargs=0 FSearch call simple_yurii_search#run()
command! -nargs=0 LinkPick call simple_yurii_search#pick_insert_link()

if !exists('g:simple_yurii_search_no_mappings')
  " gs = go search（rg 感覚の 2 打）。g 始まりなので他キーを遅延させない。
  " gs / <leader>fs … 全ノートを fzf で検索（タイトル＋本文）→ 開く。
  nnoremap <silent> gs        <Cmd>FSearch<CR>
  nnoremap <silent> <leader>fs <Cmd>FSearch<CR>
  " <Space> … 今のノートに表示中のリンクだけを fzf で一覧 → 開く。
  " （simple_yurii_note 側の旧ポップアップ定義をこのプラグインのほうで上書きする）
  nnoremap <silent> <Space>   <Cmd>call simple_yurii_search#search_local()<CR>
  " \L … タイトルだけで検索 → カーソル位置に [タイトル](相対.md) を挿入。
  nnoremap <silent> \L        <Cmd>LinkPick<CR>
endif
