" スクリプトのロードガード（重複読み込み防止）
if exists('g:loaded_quickfix_advanced')
  finish
endif
let g:loaded_quickfix_advanced = 1

" グローバル変数の初期化
if !exists('g:quickfix_advanced_mode')
  let g:quickfix_advanced_mode = 1 " デフォルトはON (1)
endif

" 関数定義: マッピングを設定
function! s:SetQuickfixMappings()
  nnoremap <buffer> <silent> j j:cnext<CR><C-w>p
  nnoremap <buffer> <silent> k k:cprevious<CR><C-w>p
  nnoremap <buffer> <silent> <CR> <CR><C-w>p
endfunction

" 関数定義: マッピングを解除
function! s:RemoveQuickfixMappings()
  silent! nunmap <buffer> j
  silent! nunmap <buffer> k
  silent! nunmap <buffer> <CR>
endfunction

" トグル関数
function! s:ToggleQuickfixAdvancedMode()
  if g:quickfix_advanced_mode
    let g:quickfix_advanced_mode = 0
    echo "Quickfix Advanced Mode: OFF"
    " 現在のQuickfixバッファがあればマッピングを解除
    if &filetype == 'qf'
      call s:RemoveQuickfixMappings()
    endif
  else
    let g:quickfix_advanced_mode = 1
    echo "Quickfix Advanced Mode: ON"
    " 現在のQuickfixバッファがあればマッピングを設定
    if &filetype == 'qf'
      call s:SetQuickfixMappings()
    endif
  endif
endfunction

" ユーザー定義コマンド
command! Autocwindow call s:ToggleQuickfixAdvancedMode()

" 自動コマンド: Quickfixバッファでモードに応じてマッピングを設定
augroup QuickfixAdvanced
  autocmd!
  autocmd FileType qf if g:quickfix_advanced_mode | call s:SetQuickfixMappings() | endif
augroup END