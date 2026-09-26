" plugin/yurii_search.vim

if exists('g:loaded_yurii_search')
  finish
endif
let g:loaded_yurii_search = 1

" python スクリプトのパス（プラグインロード時に確定）
let s:pydir = expand('<sfile>:p:h:h') . '/python'
if !exists('g:yurii_search_tui')
  let g:yurii_search_tui = s:pydir . '/fsearch_tui.py'
endif
if !exists('g:yurii_search_index')
  let g:yurii_search_index = s:pydir . '/notes_index.py'
endif

command! -nargs=0 FSearch call yurii_search#run()

if !exists('g:yurii_search_no_mappings')
  " gs = go search（rg 感覚の 2 打）。g 始まりなので他キーを遅延させない。
  nnoremap <silent> gs        <Cmd>FSearch<CR>
  nnoremap <silent> <leader>fs <Cmd>FSearch<CR>
endif
