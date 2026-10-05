" 挿入モードのまま手が止まっても、無操作デバウンスで保存されることを
" pty（test/autosave_net.sh の script 経由）で確認する。
" -es では startinsert が維持されないため、この項目だけ pty で走らせる。
set noswapfile
let s:dir = $AUTOSAVE_WORK . '/vault'
let g:simple_yurii_note_root = s:dir
let g:simple_yurii_note_autosync = 0
let g:simple_yurii_note_open_index_on_startup = 0
let g:simple_yurii_note_autosave_delay = 300

function! s:Tick() abort
  call writefile([printf('mode=%s modified=%d line=%s', mode(), &modified,
        \ get(readfile(s:dir . '/ins.md'), 0, ''))], $AUTOSAVE_WORK . '/out_insert.txt')
  call timer_start(200, {-> execute('qall!')})
endfunction

execute 'edit ' . s:dir . '/ins.md'
call setline(1, 'insert-pause')
call timer_start(1500, {-> s:Tick()})
startinsert
