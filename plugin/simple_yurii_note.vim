" simple-yurii-note: Parent/BackLink だけの最小 PKM。Child は本文。
" （Vim の関数名・autoload 名はハイフン不可のため simple_yurii_note# を使う）

if exists('g:loaded_simple_yurii_note')
  finish
endif
let g:loaded_simple_yurii_note = 1

command! SSync call simple_yurii_note#sync()

nnoremap <silent> zn :<C-u>call simple_yurii_note#new_child()<CR>
nnoremap <silent> zk :<C-u>call simple_yurii_note#new_group()<CR>
nnoremap <silent> <leader>l :<C-u>call simple_yurii_note#link()<CR>

" 保存時に軽く同期（BackLink 再生成・死にリンク掃除）
augroup simple_yurii_note_autosync
  autocmd!
  autocmd BufWritePost *.md call simple_yurii_note#sync_one()
augroup END
