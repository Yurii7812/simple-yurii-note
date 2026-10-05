" 保存タイミングの回帰テスト（test/autosave_net.sh から -es で走る）。
" 環境変数 $AUTOSAVE_WORK: テスト用の作業ディレクトリ。
" 方針: 保存が要る瞬間（Esc・離脱・gm・\tD・同期）だけ書かれ、:q! 相当の
" 破棄はしない、という現仕様を固定する。
set noswapfile
let s:dir = $AUTOSAVE_WORK . '/vault'
let g:simple_yurii_note_root = s:dir
let g:simple_yurii_note_autosync = 0
let g:simple_yurii_note_open_index_on_startup = 0
let g:simple_yurii_note_python = $AUTOSAVE_WORK . '/fake_sync.py'

function! s:say(name, text) abort
  call writefile(split(a:text, "\n", 1), $AUTOSAVE_WORK . '/out_' . a:name . '.txt')
endfunction

" 1) save_current_note は modified を書く
execute 'edit ' . s:dir . '/a.md'
call setline(1, 'one')
call simple_yurii_note#save_current_note()
call s:say('save', printf('modified=%d line=%s', &modified,
      \ get(readfile(s:dir . '/a.md'), 0, '')))

" 2) is_autosave_target: vault の .md / .csv は 1、外は 0
call s:say('target', printf('md=%d csv=%d outside=%d',
      \ simple_yurii_note#is_autosave_target(s:dir . '/a.md'),
      \ simple_yurii_note#is_autosave_target(s:dir . '/x.csv'),
      \ simple_yurii_note#is_autosave_target('/etc/hosts')))

" 3) Esc（InsertLeave）で即保存
execute 'edit ' . s:dir . '/b.md'
call setline(1, 'bee')
execute "normal! ggA!\<Esc>"
sleep 300m
call s:say('insertleave', printf('modified=%d line=%s', &modified,
      \ get(readfile(s:dir . '/b.md'), 0, '')))

" 4) バッファを離れたら即保存
execute 'edit ' . s:dir . '/c.md'
call setline(1, 'see')
execute 'edit ' . s:dir . '/a.md'
sleep 300m
call s:say('bufleave', get(readfile(s:dir . '/c.md'), 0, ''))

" 5) autosave=0 では書かない
let g:simple_yurii_note_autosave = 0
execute 'edit ' . s:dir . '/a.md'
call setline(1, 'nope')
execute "normal! ggA!\<Esc>"
sleep 300m
call s:say('off', printf('modified=%d line=%s', &modified,
      \ get(readfile(s:dir . '/a.md'), 0, '')))
let g:simple_yurii_note_autosave = 1

" 6) gm は保存してから既定アプリで開く（xdg-open は shell 側の偽物）
execute 'edit ' . s:dir . '/e.md'
call setline(1, 'gmtest')
execute 'normal gm'
sleep 500m
call s:say('gm', printf('modified=%d line=%s', &modified,
      \ get(readfile(s:dir . '/e.md'), 0, '')))

" 7) \tD は rename の前に保存（結果の確認は shell 側。最後のバッファなら
"    ここで Vim が終了するため、このテストを最後に置く）
execute 'edit ' . s:dir . '/d.md'
call setline(1, 'latest edit')
call simple_yurii_note#trash_current()
sleep 300m
qall!
