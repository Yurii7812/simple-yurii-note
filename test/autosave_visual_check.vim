" ビジュアル選択中にオートセーブのタイマーが来ても、選択が解除されず、
" 保存も選択中には走らない（選択を抜けた直後に保存される）ことを
" pty（test/autosave_net.sh の script 経由）で確認する。
" -es ではビジュアルモードが維持されないため、この項目は pty で走らせる。
set noswapfile
let s:dir = $AUTOSAVE_WORK . '/vault'
let g:simple_yurii_note_root = s:dir
let g:simple_yurii_note_autosync = 0
let g:simple_yurii_note_open_index_on_startup = 0
let g:simple_yurii_note_autosave_delay = 300

function! s:Tick() abort
  call writefile([printf('mode=%s modified=%d line=%s', mode(1), &modified,
        \ get(readfile(s:dir . '/vis.md'), 0, ''))], $AUTOSAVE_WORK . '/out_visual.txt')
  call timer_start(200, {-> execute('qall!')})
endfunction

execute 'edit ' . s:dir . '/vis.md'
call setline(1, 'visual-keep')
" 実際の TextChanged と同じ経路でオートセーブを予約してからビジュアルへ入る。
" タイマーが選択中に何度来ても mode は V のまま・modified は 1 のままのはず。
doautocmd TextChanged
normal! V
call timer_start(1200, {-> s:Tick()})
