" simple_yurii_note: Parent/BackLink だけの最小 PKM。Child は本文。
" ノート形式:
"   front matter(title) + 本文（ここに子リンク） + ### Parent + ### BackLink

if exists('g:autoloaded_simple_yurii_note')
  finish
endif
let g:autoloaded_simple_yurii_note = 1

function! s:py() abort
  return expand('<sfile>:p:h') . '/../python/simple_sync.py'
endfunction

function! s:py_cmd() abort
  return executable('python3') ? 'python3' : 'python'
endfunction

" PKM ルート: g:simple_yurii_note_root → index.md を持つ親ディレクトリを探索
function! simple_yurii_note#root() abort
  if exists('g:simple_yurii_note_root') && !empty(g:simple_yurii_note_root)
    return fnamemodify(expand(g:simple_yurii_note_root), ':p')
  endif
  let l:dir = expand('%:p:h')
  while !empty(l:dir)
    if filereadable(l:dir . '/index.md')
      let g:simple_yurii_note_root = l:dir
      return fnamemodify(l:dir, ':p')
    endif
    let l:parent = fnamemodify(l:dir, ':h')
    if l:parent ==# l:dir
      break
    endif
    let l:dir = l:parent
  endwhile
  return ''
endfunction

" ルート（index.md を持つ想定のディレクトリ）を選び直す。
function! simple_yurii_note#choose_root() abort
  let l:default = simple_yurii_note#root()
  if empty(l:default)
    let l:default = getcwd()
  endif
  let l:root = trim(input('Index directory: ', l:default, 'dir'))
  if empty(l:root)
    echo 'キャンセル'
    return
  endif
  let g:simple_yurii_note_root = fnamemodify(expand(l:root), ':p')
  echo 'simple_yurii_note root: ' . g:simple_yurii_note_root
endfunction

function! s:rel(from_dir, target) abort
  let l:out = systemlist(s:py_cmd() . ' -c "import os,sys; print(os.path.relpath(sys.argv[2], sys.argv[1]))" '
        \ . shellescape(a:from_dir) . ' ' . shellescape(a:target))
  return empty(l:out) ? fnamemodify(a:target, ':t') : substitute(l:out[0], '\\', '/', 'g')
endfunction

function! s:title(path) abort
  let l:t = ''
  for l:ln in readfile(a:path, '', 30)
    let l:m = matchstr(l:ln, '^\s*title\s*:\s*\zs.\+$')
    if !empty(l:m)
      let l:t = trim(l:m)
      break
    endif
  endfor
  return empty(l:t) ? fnamemodify(a:path, ':t:r') : l:t
endfunction

function! s:now_yaml() abort
  return strftime('%Y-%m-%d %H:%M:%S')
endfunction

function! s:note_template(title, parent_path, is_group) abort
  let l:lines = [
        \ '---',
        \ 'time: ' . s:now_yaml(),
        \ 'title: ' . a:title,
        \ ] + (a:is_group ? ['group: true'] : []) + [
        \ '---',
        \ '# ' . a:title,
        \ '',
        \ '',
        \ '### Parent',
        \ ]
  if !empty(a:parent_path)
    let l:rel = s:rel(fnamemodify(a:parent_path, ':p:h'), a:parent_path)
    call add(l:lines, '[' . s:title(a:parent_path) . '](' . l:rel . ')')
  endif
  call add(l:lines, '### BackLink')
  call add(l:lines, '')
  return l:lines
endfunction

" 現在バッファの本文（### Parent の直前）へリンク 1 行を差し込む
function! s:insert_body_link(link) abort
  let l:parent_line = 0
  for l:i in range(1, line('$'))
    if trim(getline(l:i)) ==# '### Parent'
      let l:parent_line = l:i
      break
    endif
  endfor
  if l:parent_line == 0
    call append(line('$'), a:link)
    call append(line('$'), '### Parent')
    return
  endif
  " 直前の空行の位置に置く
  let l:pos = l:parent_line - 1
  while l:pos > 1 && trim(getline(l:pos)) ==# ''
    let l:pos -= 1
  endwhile
  call append(l:pos, a:link)
endfunction

" zn: 子ノートを新規作成（本文にリンク、新ノートの Parent に今のノート）
function! simple_yurii_note#new_child() abort
  call s:new_related(0)
endfunction

" zk: グループノートを新規作成（front matter に group: true）
function! simple_yurii_note#new_group() abort
  call s:new_related(1)
endfunction

function! s:new_related(is_group) abort
  let l:cur = expand('%:p')
  if empty(l:cur)
    echohl WarningMsg | echo 'simple_yurii_note: 名前付きファイルで実行して' | echohl None
    return
  endif
  let l:dir = expand('%:p:h')
  let l:ts = strftime('%y%m%d%H%M%S')
  let l:file = l:dir . '/' . l:ts . '.md'
  let l:title = l:ts
  call writefile(s:note_template(l:title, l:cur, a:is_group), l:file)

  " 今のノートの本文にリンクを張る（本文 = 子）
  let l:link = '[' . l:title . '](' . s:rel(l:dir, l:file) . ')'
  call s:insert_body_link(l:link)
  silent! write
  call simple_yurii_note#sync_one()
  execute 'edit ' . fnameescape(l:file)
  let l:h1 = search('^#\s', 'nw')
  if l:h1 > 0 | call cursor(l:h1 + 2, 1) | endif
  startinsert
endfunction

" \l: 既存ノートへ本文リンクを張る。今のノートを親にするか聞く
function! simple_yurii_note#link() abort
  let l:cur = expand('%:p')
  if empty(l:cur)
    echohl WarningMsg | echo 'simple_yurii_note: 名前付きファイルで実行して' | echohl None
    return
  endif
  let l:target = s:target_from_clipboard()
  if empty(l:target)
    let l:target = trim(input('リンク先ファイル: ', '', 'file'))
  endif
  if empty(l:target)
    echo 'キャンセル'
    return
  endif
  let l:target = fnamemodify(expand(l:target), ':p')
  if !filereadable(l:target)
    echohl WarningMsg | echo '見つかりません: ' . l:target | echohl None
    return
  endif

  let l:link = '[' . s:title(l:target) . '](' . s:rel(expand('%:p:h'), l:target) . ')'
  call s:insert_body_link(l:link)

  let l:ans = tolower(trim(input('今のノートを ' . s:title(l:target) . ' の親にする？ (y/n): ')))
  if l:ans ==# 'y'
    call s:add_parent(l:target, l:cur)
  endif
  silent! write
  call simple_yurii_note#sync_one()
endfunction

function! s:target_from_clipboard() abort
  let l:raw = trim(getreg('+'))
  if empty(l:raw) | let l:raw = trim(getreg('"')) | endif
  let l:m = matchstr(l:raw, '\[[^\]]*\](\([^)]\+\))')
  if !empty(l:m)
    let l:t = matchstr(l:m, '(\zs[^)]\+\ze)')
    if l:t =~? '\.md$'
      return l:t
    endif
  endif
  if l:raw =~? '\.md$'
    return l:raw
  endif
  return ''
endfunction

" 相手ノートの ### Parent に 1 行足す
function! s:add_parent(target, parent_path) abort
  let l:lines = readfile(a:target)
  let l:plink = '[' . s:title(a:parent_path) . '](' . s:rel(fnamemodify(a:target, ':p:h'), a:parent_path) . ')'
  let l:phdr = -1
  let l:bhdr = -1
  for l:i in range(0, len(l:lines) - 1)
    if trim(l:lines[l:i]) ==# '### Parent' | let l:phdr = l:i | endif
    if trim(l:lines[l:i]) ==# '### BackLink' | let l:bhdr = l:i | endif
  endfor
  if l:phdr < 0
    call add(l:lines, '### Parent')
    call add(l:lines, l:plink)
  else
    " Parent セクション内に既にあるなら何もしない
    let l:end = l:bhdr > l:phdr ? l:bhdr : len(l:lines)
    for l:i in range(l:phdr + 1, l:end - 1)
      if l:lines[l:i] ==# l:plink | return | endif
    endfor
    call insert(l:lines, l:plink, l:end - 1 < l:phdr + 1 ? l:phdr + 1 : l:end)
  endif
  call writefile(l:lines, a:target)
endfunction

function! simple_yurii_note#sync() abort
  let l:root = simple_yurii_note#root()
  if empty(l:root)
    echohl WarningMsg | echo 'simple_yurii_note: ルート未設定（index.md を持つフォルダで開くか g:simple_yurii_note_root を設定）' | echohl None
    return
  endif
  echo system(s:py_cmd() . ' ' . shellescape(s:py()) . ' update ' . shellescape(l:root))
  if expand('%:p') =~? '\.md$'
    silent! edit
  endif
endfunction

function! simple_yurii_note#sync_one() abort
  let l:root = simple_yurii_note#root()
  if empty(l:root) || !filereadable(s:py())
    return
  endif
  let l:file = expand('%:p')
  if empty(l:file) || l:file !~? '\.md$'
    return
  endif
  call system(s:py_cmd() . ' ' . shellescape(s:py()) . ' update_one ' . shellescape(l:file) . ' ' . shellescape(l:root))
endfunction
