" =============================================================================
" autoload/yurii_pkm.vim
" yurii_PKM - Vimwiki非依存 Markdown PKM プラグイン (autoload)
" =============================================================================

" ---------------------------------------------------------------------------
" Internal helpers
" ---------------------------------------------------------------------------

let s:link_pat = '\v\[[^\]]+\]\([^)]*\)'
let s:fixed_link_text_marker = 'pkm:fixed-text'

function! s:sep() abort
  return has('win32') ? '\' : '/'
endfunction

function! s:python_cmd() abort
  if has('win32')
    return 'python'
  endif
  return executable('python3') ? 'python3' : 'python'
endfunction

function! s:is_markdown_file(path) abort
  return tolower(fnamemodify(a:path, ':e')) ==# 'md'
endfunction

function! s:is_markdown_target(target) abort
  return tolower(fnamemodify(a:target, ':e')) ==# 'md'
endfunction

function! s:run_sync(args_list) abort
  if !filereadable(g:yurii_pkm_python)
    echoerr 'yurii_PKM: Python script not found: ' . g:yurii_pkm_python
    return ''
  endif
  let l:cmd = s:python_cmd()
  for a in a:args_list
    let l:cmd .= ' ' . shellescape(a)
  endfor
  return system(l:cmd)
endfunction

" ---------------------------------------------------------------------------
" Title cache (session-level)
" ---------------------------------------------------------------------------

let s:title_cache = {}
let s:filename_resolve_cache = {}

function! yurii_pkm#clear_title_cache() abort
  let s:title_cache = {}
  let s:filename_resolve_cache = {}
endfunction

function! s:get_title(filepath) abort
  let l:fp = fnamemodify(a:filepath, ':p')
  if !s:is_markdown_file(l:fp)
    return ''
  endif
  if has_key(s:title_cache, l:fp)
    return s:title_cache[l:fp]
  endif
  if !filereadable(l:fp)
    return ''
  endif
  let l:lines = readfile(l:fp, '', 30)
  let l:in_yaml = 0
  for l:line in l:lines
    if l:line =~# '^---\s*$'
      if l:in_yaml | break | endif
      let l:in_yaml = 1
      continue
    endif
    if l:in_yaml && l:line =~? '^title:\s*'
      let l:title = trim(matchstr(l:line, ':\s*\zs.*'))
      let l:title = substitute(l:title, '^[\"'']\|[\"'']$', '', 'g')
      let s:title_cache[l:fp] = l:title
      return l:title
    endif
    if !l:in_yaml && l:line =~# '^#\+\s\+'
      let l:title = trim(substitute(l:line, '^#\+\s\+', '', ''))
      let s:title_cache[l:fp] = l:title
      return l:title
    endif
  endfor
  let l:stem = fnamemodify(l:fp, ':t:r')
  let s:title_cache[l:fp] = l:stem
  return l:stem
endfunction

" ---------------------------------------------------------------------------
" Current file helpers
" ---------------------------------------------------------------------------

function! s:get_yaml_title(filepath) abort
  let l:fp = fnamemodify(a:filepath, ':p')
  if !s:is_markdown_file(l:fp) || !filereadable(l:fp)
    return ''
  endif
  let l:lines = readfile(l:fp, '', 30)
  let l:in_yaml = 0
  for l:line in l:lines
    if l:line =~# '^---\s*$'
      if l:in_yaml | break | endif
      let l:in_yaml = 1
      continue
    endif
    if l:in_yaml && l:line =~? '^title:\s*'
      let l:title = trim(matchstr(l:line, ':\s*\zs.*'))
      return substitute(l:title, '^[\"'']\|[\"'']$', '', 'g')
    endif
  endfor
  return ''
endfunction

function! yurii_pkm#current_file() abort
  return expand('%:p')
endfunction

function! yurii_pkm#current_title() abort
  let l:lines = getline(1, min([30, line('$')]))
  let l:in_yaml = 0
  for l:line in l:lines
    if l:line =~# '^---\s*$'
      if l:in_yaml | break | endif
      let l:in_yaml = 1
      continue
    endif
    if l:in_yaml && l:line =~? '^title:\s*'
      let l:t = trim(matchstr(l:line, ':\s*\zs.*'))
      return substitute(l:t, '^[\"'']\|[\"'']$', '', 'g')
    endif
    if !l:in_yaml && l:line =~# '^#\+\s\+'
      return trim(substitute(l:line, '^#\s\+', '', ''))
    endif
  endfor
  return expand('%:t:r')
endfunction

function! s:outline_collect() abort
  let l:items = []
  let l:max_lnum = line('$')
  let lnum = 1
  while lnum <= l:max_lnum
    let l:line = getline(lnum)
    if l:line =~# '^\s*#\+\s\+'
      let l:indent = matchstr(l:line, '^\s*')
      let l:head = matchstr(l:line, '#\+')
      let l:title = substitute(l:line, '^\s*#\+\s\+', '', '')
      let l:title = substitute(l:title, '^\s\+', '', '')
      let l:title = substitute(l:title, '\s\+$', '', '')

      call add(l:items, {
            \ 'src_lnum': lnum,
            \ 'indent': l:indent,
            \ 'level': strlen(l:head),
            \ 'title': l:title,
            \ })
    endif
    let lnum += 1
  endwhile

  return l:items
endfunction

function! s:outline_editor_lines(items) abort
  let l:lines = []
  call add(l:lines, '# OutlineEdit: 見出しを編集して :write で反映')
  call add(l:lines, '# <- / -> : 見出しレベル変更（# の数を減増）')
  call add(l:lines, '# Visual選択して <- / -> : 選択範囲を一括変更')
  call add(l:lines, '# q / ZZ / :OutlineApply で反映（Q は保存せず閉じる）')
  call add(l:lines, '')

  for l:item in a:items
    call add(l:lines, repeat('#', l:item.level) . ' ' . l:item.title)
  endfor
  return l:lines
endfunction

function! s:outline_shift_range(first, last, delta) abort
  let l:base = get(b:, 'yurii_outline_base', 6)
  let l:last_edit = l:base + len(get(b:, 'yurii_outline_items', [])) - 1
  let l:start = max([a:first, l:base])
  let l:end = min([a:last, l:last_edit])
  if l:start > l:end
    return
  endif

  for lnum in range(l:start, l:end)
    let l:line = getline(lnum)
    if l:line !~# '^\s*#\+\s\+'
      continue
    endif
    let l:level = strlen(matchstr(l:line, '#\+')) + a:delta
    let l:level = max([1, l:level])
    let l:title = trim(substitute(l:line, '^\s*#\+\s\+', '', ''))
    call setline(lnum, repeat('#', l:level) . ' ' . l:title)
  endfor
endfunction

function! yurii_pkm#outline_shift_current(delta) abort
  call s:outline_shift_range(line('.'), line('.'), a:delta)
endfunction

function! yurii_pkm#outline_shift_visual(delta) range abort
  call s:outline_shift_range(a:firstline, a:lastline, a:delta)
endfunction

function! yurii_pkm#outline_editor_apply() abort
  if !get(b:, 'yurii_outline_editor', 0)
    return
  endif
  let l:src_buf = get(b:, 'yurii_outline_src_bufnr', -1)
  let l:items = get(b:, 'yurii_outline_items', [])
  let l:base = get(b:, 'yurii_outline_base', 6)
  if l:src_buf < 0 || empty(l:items)
    echoerr 'OutlineEdit: invalid editor state'
    return
  endif

  for l:i in range(0, len(l:items) - 1)
    let l:src = l:items[l:i]
    let l:line = trim(getline(l:base + l:i))
    if l:line =~# '^#\+\s\+'
      let l:new_level = strlen(matchstr(l:line, '^#\+'))
      let l:new_title = trim(substitute(l:line, '^#\+\s\+', '', ''))
    else
      let l:new_level = max([1, get(l:src, 'level', 1)])
      let l:new_title = empty(l:line) ? get(l:src, 'title', '') : l:line
    endif
    let l:new_line = get(l:src, 'indent', '') . repeat('#', l:new_level) . ' ' . l:new_title
    call setbufline(l:src_buf, l:src.src_lnum, l:new_line)
  endfor

  setlocal nomodified
  echom 'OutlineEdit: 反映しました'
endfunction

function! yurii_pkm#outline_edit() abort
  if !s:is_markdown_file(expand('%:p'))
    echoerr 'yurii_PKM: OutlineEdit は Markdown ファイルでのみ利用できます'
    return
  endif

  let l:items = s:outline_collect()

  if empty(l:items)
    echom 'yurii_PKM: 見出しが見つかりませんでした'
    return
  endif

  let l:origin_win = win_getid()
  vertical botright new
  execute 'file ' . fnameescape('[YuriiOutlineEdit]')

  call setline(1, s:outline_editor_lines(l:items))

  let b:yurii_outline_editor = 1
  let b:yurii_outline_src_bufnr = winbufnr(l:origin_win)
  let b:yurii_outline_items = deepcopy(l:items)
  let b:yurii_outline_base = 6

  setlocal buftype=acwrite
  setlocal bufhidden=wipe
  setlocal noswapfile
  setlocal nobuflisted
  setlocal filetype=markdown
  setlocal nonumber
  setlocal norelativenumber
  setlocal foldcolumn=0
  setlocal signcolumn=no
  setlocal nowrap
  setlocal modifiable

  augroup yurii_pkm_outline_editor
    autocmd! * <buffer>
    autocmd BufWriteCmd <buffer> call yurii_pkm#outline_editor_apply()
  augroup END
  command! -buffer OutlineApply call yurii_pkm#outline_editor_apply()
  nnoremap <silent><buffer> q  <Cmd>call yurii_pkm#outline_editor_apply()<CR><Cmd>bd!<CR>
  nnoremap <silent><buffer> Q  <Cmd>bd!<CR>
  nnoremap <silent><buffer> ZZ <Cmd>call yurii_pkm#outline_editor_apply()<CR><Cmd>bd!<CR>

  nnoremap <silent><buffer> <Left>  <Cmd>call yurii_pkm#outline_shift_current(-1)<CR>
  nnoremap <silent><buffer> <Right> <Cmd>call yurii_pkm#outline_shift_current(1)<CR>
  xnoremap <silent><buffer> <Left>  :<C-u>call yurii_pkm#outline_shift_visual(-1)<CR>
  xnoremap <silent><buffer> <Right> :<C-u>call yurii_pkm#outline_shift_visual(1)<CR>

  call cursor(b:yurii_outline_base, 1)
endfunction


function! s:state_dir() abort
  if exists('*stdpath')
    return stdpath('data') . s:sep() . 'yurii_pkm'
  endif
  return expand('~/.vim/yurii_pkm')
endfunction

function! s:root_state_file() abort
  return s:state_dir() . s:sep() . 'root.txt'
endfunction

function! s:load_persisted_root() abort
  let l:file = s:root_state_file()
  if !filereadable(l:file)
    return ''
  endif
  let l:lines = readfile(l:file)
  if empty(l:lines)
    return ''
  endif
  let l:root = trim(l:lines[0])
  if empty(l:root)
    return ''
  endif
  return fnamemodify(expand(l:root), ':p')
endfunction

function! s:save_persisted_root(root) abort
  if empty(a:root)
    return
  endif
  let l:dir = s:state_dir()
  if !isdirectory(l:dir)
    call mkdir(l:dir, 'p')
  endif
  call writefile([fnamemodify(a:root, ':p')], s:root_state_file())
endfunction

function! s:get_pkm_root() abort
  let l:root = ''
  if exists('g:yurii_pkm_root')
    let l:root = trim(get(g:, 'yurii_pkm_root', ''))
  endif
  if empty(l:root)
    let l:root = s:load_persisted_root()
    if !empty(l:root)
      let g:yurii_pkm_root = l:root
    endif
  endif
  if empty(l:root)
    return ''
  endif
  return fnamemodify(expand(l:root), ':p')
endfunction

function! s:index_path(root) abort
  return fnamemodify(a:root, ':p') . s:sep() . 'index.md'
endfunction

function! s:is_root_note_path(path) abort
  let l:root = s:get_pkm_root()
  if empty(l:root) || empty(a:path)
    return 0
  endif
  let l:path = fnamemodify(a:path, ':p')
  let l:root = fnamemodify(l:root, ':p')
  return s:is_markdown_file(l:path)
        \ && filereadable(l:path)
        \ && stridx(l:path, l:root) == 0
        \ && index(split(l:path, s:sep()), '.undo') < 0
endfunction

function! s:pkm_format() abort
  return get(g:, 'yurii_pkm_format', 'v2')
endfunction

" 索引テンプレート。a:with_guide が真のときだけ操作ガイドへのリンクを 1 本
" 本文（## Parent の前）に置く。本文のリンクは sync が再生成しないので、
" 自分で消せば復活せず、ディレクトリ移動で Index を作り直しても付かない。
" 付けるのはガイドを新規作成する初回のみ。
function! s:index_template(...) abort
  " index.md は全ノートの最上位の容器なので、v2 では最初から
  " attribute: グループ を付ける（無いと sync が index を容器と認識できず、
  " index に足したリンクが自動で グループ: ラベルにならない）。
  let l:with_guide = a:0 ? a:1 : 0
  let l:v2 = s:pkm_format() ==# 'v2'
  let l:head = [
        \ '---',
        \ 'time: ' . yurii_pkm#timestamp_yaml(),
        \ 'title: Index',
        \ ] + (l:v2 ? ['attribute: group'] : []) + [
        \ '---',
        \ '',
        \ '# Index',
        \ '',
        \ ]
  if l:v2
    let l:out = l:head
    if l:with_guide
      let l:out += [s:guide_link(), '']
    endif
    return l:out + [s:v2_up_mark, s:v2_down_mark]
  endif
  return l:head
endfunction

" Index 作成時に生成する操作ガイド。全コマンドを簡略にまとめる。
let s:guide_name = 'yurii_pkm_guide.md'

function! s:guide_link() abort
  return '[yurii_pkm 操作ガイド](' . s:guide_name . ')'
endfunction

function! s:guide_template() abort
  let l:title = 'yurii_pkm 操作ガイド'
  let l:body = [
        \ '## ノート作成',
        \ '',
        \ '- `zn` … ノート作成。位置キーを 1 つ選ぶ:',
        \ '  `h`=カーソル直下（本文） / `Enter`=Child の最後尾 / `o`=リンク無し（孤立） / `p`=Parent の末尾',
        \ '- `zk` … グループノート作成（`attribute: group`）。位置キーは `zn` と同じ',
        \ '- `zh` … カーソル直下にリンク（本文扱い → 相手にはバックリンク）',
        \ '',
        \ '## リンク移動',
        \ '',
        \ '- `<Tab>` / `<S-Tab>` … 次の / 前のリンクへ',
        \ '- `<CR>` … カーソル下のリンクを開く',
        \ '- `<BS>` … 戻る ・ `<S-BS>` / `\.` … 進む ・ `_` … 直前のノートと往復',
        \ '- `1`〜`9` / `0` … 本文→Parent/Child の通し番号のリンクを開く',
        \ '',
        \ '## ナビゲータ（<Space> / gs）',
        \ '',
        \ '- `<Space>` … 今のノートのリンク ・ `gs` … 全ノート検索',
        \ '- `⇥` スコープ切替 / `i` 入力 / `⏎` 開く / `l` 潜る / `⌫`・`h` 戻る',
        \ '- 入力中は記号もそのまま打てる（`-` など）',
        \ '',
        \ '## 関係の追加・編集',
        \ '',
        \ '- `ca` / `cu` / `at` / `bc` … クリップボードのリンクを関係付きで追加',
        \ '- `za` … クリップボードを Child に追加（既定のノート関係）',
        \ '- `pe` … 現ノート周辺を 1 つの md に展開',
        \ '- `zt` / `zT` … タイトル変更 ・ `zl` / `zL` … リンク表示名の変更',
        \ '- `zd` … Child のリンク表示名をリンク先タイトルに更新',
        \ '',
        \ '## ラベル記法（関係の接尾辞）',
        \ '',
        \ '- `語:` … 相手側は `(語):` でミラー',
        \ '- `語:;` … 相手側も `語:;`（括弧なし）',
        \ '- `語;` … 相手側には書かない',
        \ '- `語::` … 両方の同じセクションに `語:`',
        \ '- 見出し無しの裸リンクは、Parent の先頭ブロックが `group`、2 番目以降が `ノート`',
        \ '',
        \ '## 同期',
        \ '',
        \ '- 保存時に自動同期（`:UpdateMD` で全体を整合）',
        \ '- 相手側のラベルは自動でミラー。括弧を外して手書きしたら sticky',
        \ '',
        \ '## ハブ',
        \ '',
        \ '- `\1`〜`\9` … ハブへ直行 ・ `\H` … 現在ノートを登録 ・ `\0` … 一覧',
        \ ]
  return [
        \ '---',
        \ 'time: ' . yurii_pkm#timestamp_yaml(),
        \ 'title: ' . l:title,
        \ '---',
        \ '',
        \ '# ' . l:title,
        \ '',
        \ ] + l:body + [
        \ '',
        \ s:v2_up_mark,
        \ s:v2_down_mark,
        \ ]
endfunction

" 操作ガイドを最新のテンプレートへ更新する。無ければ作る。既存の time 行は
" 引き継いで、内容が変わったときだけ書き換える（毎回の無駄な差分を避ける）。
function! s:refresh_guide(root) abort
  let l:guide = a:root . s:sep() . s:guide_name
  let l:new = s:guide_template()
  if filereadable(l:guide)
    let l:old = readfile(l:guide)
    let l:old_time = matchstr(join(l:old, "\n"), '^time:.*$')
    if !empty(l:old_time)
      call map(l:new, 'v:val =~# "^time:" ? l:old_time : v:val')
    endif
    if l:old ==# l:new
      return
    endif
  endif
  call writefile(l:new, l:guide)
endfunction

" 公開: 既存の操作ガイドを最新にする（VimEnter 用。無ければ何もしない）。
function! yurii_pkm#refresh_guide() abort
  let l:root = s:get_pkm_root()
  if empty(l:root) || !isdirectory(l:root)
    return
  endif
  if !filereadable(l:root . s:sep() . s:guide_name)
    return
  endif
  call s:refresh_guide(l:root)
endfunction

" 公開: 操作ガイドを作り直す（無ければ作る。:YuriiGuide 用）。
function! yurii_pkm#write_guide() abort
  let l:root = s:get_pkm_root()
  if empty(l:root) || !isdirectory(l:root)
    echo 'yurii_PKM: PKM root 未設定'
    return
  endif
  call s:refresh_guide(l:root)
  echo 'yurii_PKM: 操作ガイドを更新: ' . s:guide_name
endfunction

" index.md と操作ガイドをまとめて作る（ガイドは常に最新へ）。
" ガイドへのリンクは、ガイドを新規に作る初回だけ Index に置く。既にガイドが
" あるとき（ディレクトリ移動で Index を作り直すときなど）はリンクしない。
function! s:write_index_and_guide(root) abort
  let l:index = s:index_path(a:root)
  let l:guide = fnamemodify(a:root, ':p') . s:sep() . s:guide_name
  let l:first_guide = !filereadable(l:guide)
  call s:refresh_guide(a:root)
  call writefile(s:index_template(l:first_guide), l:index)
  call s:mark_index_created()
endfunction

function! s:setup_persistent_undo_for_root(root) abort
  if !get(g:, 'yurii_pkm_persistent_undo', 1)
    return
  endif
  if empty(a:root)
    return
  endif
  let l:root_abs = fnamemodify(a:root, ':p')
  let l:root_abs = substitute(l:root_abs, s:sep() . '\+$', '', '')
  let l:undo_dir = l:root_abs . s:sep() . '.undo'
  if !isdirectory(l:undo_dir)
    try
      call mkdir(l:undo_dir, 'p')
    catch /^Vim\%((\a\+)\)\=:E739/
      let l:fallback = expand('~/.vim/undo')
      if !isdirectory(l:fallback)
        call mkdir(l:fallback, 'p')
      endif
      let l:undo_dir = l:fallback
      echohl WarningMsg
      echom 'yurii_PKM: persistent undo dir could not be created under root; fallback to ~/.vim/undo'
      echohl None
    endtry
  endif
  execute 'set undodir=' . fnameescape(l:undo_dir)
  set undofile
  set undolevels=10000
  set undoreload=100000
endfunction

function! yurii_pkm#init_persistent_undo_if_ready() abort
  let l:root = s:get_pkm_root()
  if empty(l:root) || !isdirectory(l:root)
    return
  endif
  if !filereadable(s:index_path(l:root))
    return
  endif
  call s:setup_persistent_undo_for_root(l:root)
endfunction

let s:startup_root_recovery_active = 0
let s:index_created_recently = 0

function! s:mark_index_created() abort
  let s:index_created_recently = 1
endfunction

function! s:consume_index_created_flag() abort
  let l:created = get(s:, 'index_created_recently', 0)
  let s:index_created_recently = 0
  return l:created
endfunction

function! s:timer_edit_file_cb(...) abort
  " timer_start() の callback 引数順は Vim 実装/呼び出し方で差が出ることがあるため、
  " 文字列の引数を path として拾う。
  let l:path = ''
  if a:0 >= 1 && type(a:1) == v:t_string
    let l:path = a:1
  elseif a:0 >= 2 && type(a:2) == v:t_string
    let l:path = a:2
  endif
  if empty(l:path)
    return
  endif
  execute 'edit ' . fnameescape(l:path)

endfunction

function! s:timer_redraw_cb(timer) abort
  redraw!
endfunction

function! s:open_index_with_delay(index_path) abort
  call yurii_pkm#push_history()
  call timer_start(0, function('s:timer_edit_file_cb', [a:index_path]))
  call timer_start(50, function('s:timer_redraw_cb'))
endfunction

function! s:startup_recover_missing_root() abort
  let l:new_root = s:prompt_index_root()
  if empty(l:new_root)
    return ''
  endif

  let g:yurii_pkm_root = l:new_root
  call s:save_persisted_root(l:new_root)

  let l:index = s:index_path(l:new_root)
  if !filereadable(l:index)
    let l:ans = tolower(trim(input('Create index.md? y/n: ')))
    if l:ans !=# 'y'
      echom 'index.md not created'
      return l:new_root
    endif
    if !isdirectory(l:new_root)
      call mkdir(l:new_root, 'p')
    endif
    call s:setup_persistent_undo_for_root(l:new_root)
    call s:write_index_and_guide(l:new_root)
    call yurii_pkm#clear_title_cache()
    echom 'Created: ' . l:index
  endif

  if filereadable(l:index)
    execute 'cd ' . fnameescape(l:new_root)
    if s:consume_index_created_flag()
      call s:open_index_with_delay(l:index)
    else
      call yurii_pkm#push_history()
      execute 'edit ' . fnameescape(l:index)
    endif
  endif
  return l:new_root
endfunction

function! yurii_pkm#startup_restore_root() abort
  if get(s:, 'startup_root_recovery_active', 0)
    return
  endif
  let s:startup_root_recovery_active = 1
  try
    let l:root = s:get_pkm_root()
    if empty(l:root)
      return
    endif
    if isdirectory(l:root) && filereadable(s:index_path(l:root))
      let g:yurii_pkm_root = l:root
      call s:setup_persistent_undo_for_root(l:root)
      return
    endif

    if !isdirectory(l:root)
      echom 'Remembered PKM root not found: ' . l:root
      call s:startup_recover_missing_root()
      return
    endif

    " root は覚えているが Index が無い → 勝手には作らず、どこに作るか・
    " 作ってよいかを聞く（s:setup_root_and_index が両方を尋ねる）。
    echom 'Remembered index not found: ' . s:index_path(l:root)
    let g:yurii_pkm_root = l:root
    call s:save_persisted_root(l:root)
    call s:setup_persistent_undo_for_root(l:root)
    call s:setup_root_and_index(1)
    return
  finally
    let s:startup_root_recovery_active = 0
  endtry
endfunction

" ディレクトリ選択 -> Index作成 -> Indexを開く までを一括で行うヘルパー
" a:open_index: 作成後にIndexを開くかどうか (1=開く, 0=開かない)
" 戻り値: 設定したrootのパス、キャンセル時は ''
function! s:setup_root_and_index(open_index) abort
  " Step1: ディレクトリ選択
  let l:default = s:get_pkm_root()
  if empty(l:default)
    let l:default = getcwd()
  endif
  try
    let l:root = trim(input('Index directory: ', l:default, 'dir'))
  catch /^Vim:Interrupt$/
    echo 'Cancelled'
    return ''
  endtry
  if empty(l:root)
    echo 'Cancelled'
    return ''
  endif
  let l:root = fnamemodify(expand(l:root), ':p')

  if !isdirectory(l:root)
    call mkdir(l:root, 'p')
  endif
  let g:yurii_pkm_root = l:root
  call s:save_persisted_root(l:root)
  call s:setup_persistent_undo_for_root(l:root)

  " Step2: Index作成確認
  let l:index = s:index_path(l:root)
  if !filereadable(l:index)
    let l:ans = tolower(trim(input('Create index.md? y/n: ')))
    if l:ans ==# 'y'
      call s:write_index_and_guide(l:root)
      call yurii_pkm#clear_title_cache()
      echom 'Created: ' . l:index
    else
      echom 'index.md not created'
      return l:root
    endif
  endif

  " Step3: Indexを開く
  if a:open_index && filereadable(l:index)
    execute 'cd ' . fnameescape(l:root)
    if s:consume_index_created_flag()
      call s:open_index_with_delay(l:index)
    else
      call yurii_pkm#push_history()
      execute 'edit ' . fnameescape(l:index)
    endif
  endif

  return l:root
endfunction

function! s:prompt_index_root() abort
  let l:default = s:get_pkm_root()
  if empty(l:default)
    let l:default = getcwd()
  endif
  try
    let l:dir = trim(input('Index directory: ', l:default, 'dir'))
  catch /^Vim:Interrupt$/
    echo 'Cancelled'
    return ''
  endtry
  if empty(l:dir)
    echo 'Cancelled'
    return ''
  endif
  return fnamemodify(expand(l:dir), ':p')
endfunction

function! yurii_pkm#ensure_root_and_index() abort
  let l:root = s:get_pkm_root()

  if get(s:, 'startup_root_recovery_active', 0)
    if !empty(l:root) && filereadable(s:index_path(l:root))
      return l:root
    endif
    return ''
  endif

  " rootもIndexも正常
  if !empty(l:root) && filereadable(s:index_path(l:root))
    let g:yurii_pkm_root = l:root
    call s:save_persisted_root(l:root)
    call s:setup_persistent_undo_for_root(l:root)
    return l:root
  endif

  " rootは設定済みだがディレクトリが消えている → 選び直し
  if !empty(l:root) && !isdirectory(l:root)
    return s:setup_root_and_index(1)
  endif

  " rootは設定済みでディレクトリはあるがIndexがない → Index作成だけ
  if !empty(l:root)
    let g:yurii_pkm_root = l:root
    call s:save_persisted_root(l:root)
    call s:setup_persistent_undo_for_root(l:root)
    let l:index = s:index_path(l:root)
    let l:ans = tolower(trim(input('Create index.md? y/n: ')))
    if l:ans ==# 'y'
      call s:write_index_and_guide(l:root)
      call yurii_pkm#clear_title_cache()
      echom 'Created: ' . l:index
      return l:root
    else
      echom 'index.md not created'
      return ''
    endif
  endif

  " rootが未設定 → ディレクトリ選択から
  return s:setup_root_and_index(0)
endfunction

function! yurii_pkm#choose_index_root() abort
  let l:current_root = s:get_pkm_root()
  let l:new_root = s:setup_root_and_index(1)
  if empty(l:new_root)
    return ''
  endif
  if !empty(l:current_root) && fnamemodify(l:current_root, ':p') !=# fnamemodify(l:new_root, ':p')
    echom 'Switched PKM root to: ' . l:new_root
  else
    echom 'PKM root set to: ' . l:new_root
  endif
  return l:new_root
endfunction

function! s:current_dir_for_prefix_check() abort
  let l:file = expand('%:p')
  if !empty(l:file)
    return fnamemodify(l:file, ':p:h')
  endif
  return getcwd()
endfunction

function! s:is_in_pkm_root(path) abort
  let l:root = s:get_pkm_root()
  if empty(l:root)
    return 0
  endif
  let l:path = fnamemodify(a:path, ':p')
  return l:path =~# '^' . escape(l:root, '\')
endfunction

function! s:missing_prefix_files_in_dir(dir) abort
  let l:files = []
  for l:path in sort(glob(a:dir . '/*', 0, 1))
    if !filereadable(l:path)
      continue
    endif
    let l:name = fnamemodify(l:path, ':t')
    if l:name ==# 'index.md' || l:name =~# '^\.'
      continue
    endif
    if l:name =~# '^[A-Z]_'
      continue
    endif
    call add(l:files, l:path)
  endfor
  return l:files
endfunction

function! s:rename_missing_prefix_files(dir, files) abort
  let l:cur = expand('%:p')
  let l:renamed = []
  for l:old in a:files
    let l:new = fnamemodify(l:old, ':h') . '/M_' . fnamemodify(l:old, ':t')
    if filereadable(l:new) || isdirectory(l:new)
      echom 'skip (already exists): ' . fnamemodify(l:new, ':t')
      continue
    endif
    if rename(l:old, l:new) != 0
      echom 'rename failed: ' . fnamemodify(l:old, ':t')
      continue
    endif
    if !empty(l:cur) && fnamemodify(l:cur, ':p') ==# fnamemodify(l:old, ':p')
      execute 'silent keepalt file ' . fnameescape(l:new)
      let l:cur = l:new
    endif
    call add(l:renamed, fnamemodify(l:new, ':t'))
  endfor
  return l:renamed
endfunction

function! yurii_pkm#check_missing_prefix_in_current_dir() abort
  return 1
endfunction

function! yurii_pkm#check_missing_prefix_in_current_dir_once() abort
  return
endfunction

" ---------------------------------------------------------------------------
" Section helpers (buffer-level)
" ---------------------------------------------------------------------------

function! s:bare_section_name(text) abort
  let l:s = trim(a:text)
  let l:s = substitute(l:s, '^#\+\s*', '', '')
  let l:s = substitute(l:s, ':\s*$', '', '')
  return tolower(l:s)
endfunction

function! s:section_aliases(name) abort
  let l:target = tolower(a:name)
  if l:target ==# 'parent' || l:target ==# 'up'
    return ['parent', 'up']
  endif
  if l:target ==# 'child' || l:target ==# 'down' || l:target ==# 'branch'
    return ['child', 'down', 'branch']
  endif
  if l:target ==# 'back' || l:target ==# 'backlink'
    return ['back', 'backlink']
  endif
  return [l:target]
endfunction

function! s:canonical_section_title(name) abort
  let l:target = tolower(a:name)
  if l:target ==# 'parent' || l:target ==# 'up'
    return 'Parent:'
  endif
  if l:target ==# 'child' || l:target ==# 'down' || l:target ==# 'branch'
    return 'Child:'
  endif
  if l:target ==# 'back' || l:target ==# 'backlink'
    return 'BackLink:'
  endif
  return toupper(strpart(a:name, 0, 1)) . strpart(a:name, 1) . ':'
endfunction

function! s:is_section_header_text(text, name) abort
  let l:sec = s:bare_section_name(a:text)
  return index(s:section_aliases(a:name), l:sec) >= 0
endfunction

function! s:is_known_section_header_text(text) abort
  let l:sec = s:bare_section_name(a:text)
  return index(['parent', 'up', 'child', 'down', 'branch', 'back', 'backlink'], l:sec) >= 0
endfunction

function! s:find_section_index_in_lines(lines, name) abort
  let l:found = -1
  let l:in_fence = 0
  for l:i in range(0, len(a:lines) - 1)
    let l:s = trim(a:lines[l:i])
    if l:s =~# '^```'
      let l:in_fence = !l:in_fence
    endif
    if !l:in_fence && s:is_section_header_text(l:s, a:name)
      let l:found = l:i
    endif
  endfor
  return l:found
endfunction

" Return line number (1-based) of section header, or 0
function! s:find_section_line(name) abort
  let l:found = 0
  let l:in_fence = 0
  for l:i in range(1, line('$'))
    let l:s = trim(getline(l:i))
    if l:s =~# '^```'
      let l:in_fence = !l:in_fence
    endif
    if !l:in_fence && s:is_section_header_text(l:s, a:name)
      let l:found = l:i
    endif
  endfor
  return l:found
endfunction

" Ensure the buffer has a Child: section, placed after Parent: and before BackLink:.
function! s:ensure_down_section() abort
  if s:find_section_line('down') > 0
    return
  endif

  let l:back = s:find_section_line('back')
  if l:back > 0
    call append(l:back - 1, s:canonical_section_title('down'))
    return
  endif

  let l:up_end = s:up_end_line()
  if l:up_end > 0
    call append(l:up_end, s:canonical_section_title('down'))
    return
  endif

  call append(line('$'), s:canonical_section_title('down'))
endfunction

" Return insertion end line for outgoing links in Child:.
function! s:down_end_line() abort
  let l:down = s:find_section_line('down')
  if l:down > 0
    let l:back_after_down = 0
    for l:i in range(l:down + 1, line('$'))
      if s:is_section_header_text(getline(l:i), 'back')
        let l:back_after_down = l:i
        break
      endif
    endfor
    return l:back_after_down > 0 ? l:back_after_down - 1 : line('$')
  endif

  return 0
endfunction

" Return line number where appending inserts at top of Child:.
function! s:down_top_insert_line() abort
  let l:down = s:find_section_line('down')
  if l:down > 0
    return l:down
  endif

  return 0
endfunction

function! s:is_current_index_buffer() abort
  let l:root = s:get_pkm_root()
  if empty(l:root) || empty(expand('%:p'))
    return 0
  endif
  return fnamemodify(expand('%:p'), ':p') ==# fnamemodify(s:index_path(l:root), ':p')
endfunction

function! s:structural_link_append_line() abort
  let l:down = s:down_end_line()
  if l:down > 0
    return l:down
  endif
  if s:is_current_index_buffer()
    return line('$')
  endif
  return 0
endfunction

function! s:structural_link_prepend_line() abort
  let l:down = s:down_top_insert_line()
  if l:down > 0
    return l:down
  endif
  if s:is_current_index_buffer()
    return line('$')
  endif
  return 0
endfunction

" Return insertion end line for Parent: section (just before next section header / EOF).
function! s:before_up_line() abort
  let l:up = s:find_section_line('up')
  if l:up > 0
    return l:up - 1
  endif
  return s:down_end_line()
endfunction

function! s:up_end_line() abort
  let l:up = s:find_section_line('up')
  if l:up <= 0
    return 0
  endif
  for l:i in range(l:up + 1, line('$'))
    if s:is_known_section_header_text(getline(l:i))
      return l:i - 1
    endif
  endfor
  return line('$')
endfunction

function! s:replace_section(name, new_lines) abort
  let l:sec = s:find_section_line(a:name)
  if l:sec <= 0
    return 0
  endif

  let l:end = l:sec
  for l:i in range(l:sec + 1, line('$'))
    if s:is_known_section_header_text(getline(l:i))
      let l:end = l:i - 1
      break
    endif
    let l:end = l:i
  endfor

  if l:end >= l:sec + 1
    execute (l:sec + 1) . ',' . l:end . 'delete _'
  endif

  if !empty(a:new_lines)
    call append(l:sec, a:new_lines)
  endif
  return 1
endfunction

function! s:section_end_line(name) abort
  let l:sec = s:find_section_line(a:name)
  if l:sec <= 0
    return 0
  endif
  let l:end = l:sec
  for l:i in range(l:sec + 1, line('$'))
    if s:is_known_section_header_text(getline(l:i))
      return l:i - 1
    endif
    let l:end = l:i
  endfor
  return l:end
endfunction

function! s:append_link_to_buffer_section(name, link) abort
  let l:sec = s:find_section_line(a:name)
  if l:sec <= 0
    return 0
  endif

  let l:end = s:section_end_line(a:name)
  if l:end > l:sec
    let l:new_target = s:extract_target(a:link)
    let l:new_fp = empty(l:new_target) ? '' : fnamemodify(yurii_pkm#resolve_link(l:new_target, expand('%:p:h')), ':p')
    for l:line in getline(l:sec + 1, l:end)
      if l:line ==# a:link
        return 0
      endif
      let l:old_target = s:extract_target(l:line)
      if !empty(l:new_fp) && !empty(l:old_target)
        let l:old_fp = fnamemodify(yurii_pkm#resolve_link(l:old_target, expand('%:p:h')), ':p')
        if l:old_fp ==# l:new_fp
          return 0
        endif
      endif
    endfor
  endif

  call append(l:end, a:link)
  return 1
endfunction

function! s:append_structural_link_to_buffer(link) abort
  let l:down = s:find_section_line('down')
  if l:down > 0
    return s:append_link_to_buffer_section('down', a:link)
  endif

  if !s:is_current_index_buffer()
    return 0
  endif

  let l:new_target = s:extract_target(a:link)
  let l:new_fp = empty(l:new_target) ? '' : fnamemodify(yurii_pkm#resolve_link(l:new_target, expand('%:p:h')), ':p')
  for l:i in range(1, line('$'))
    let l:old_target = s:extract_target(getline(l:i))
    if getline(l:i) ==# a:link
      return 0
    endif
    if !empty(l:new_fp) && !empty(l:old_target)
      let l:old_fp = fnamemodify(yurii_pkm#resolve_link(l:old_target, expand('%:p:h')), ':p')
      if l:old_fp ==# l:new_fp
        return 0
      endif
    endif
  endfor
  call append(line('$'), a:link)
  return 1
endfunction

function! s:section_end_index_in_lines(lines, start_idx) abort
  let l:end = len(a:lines)
  if a:start_idx + 1 >= len(a:lines)
    return l:end
  endif
  for l:i in range(a:start_idx + 1, len(a:lines) - 1)
    if s:is_known_section_header_text(get(a:lines, l:i, ''))
      let l:end = l:i
      break
    endif
  endfor
  return l:end
endfunction

function! s:ensure_section_in_lines(lines, name) abort
  let l:lines = copy(a:lines)
  let l:idx = s:find_section_index_in_lines(l:lines, a:name)
  return {'lines': l:lines, 'idx': l:idx}
endfunction

function! s:add_link_to_lines_section(lines, name, link) abort
  let l:ensured = s:ensure_section_in_lines(a:lines, a:name)
  let l:lines = l:ensured.lines
  let l:idx = l:ensured.idx
  if l:idx < 0
    return {'lines': l:lines, 'added': 0}
  endif
  let l:end = s:section_end_index_in_lines(l:lines, l:idx)
  if index(l:lines[l:idx + 1 : l:end - 1], a:link) >= 0
    return {'lines': l:lines, 'added': 0}
  endif
  call insert(l:lines, a:link, l:end)
  return {'lines': l:lines, 'added': 1}
endfunction


" ---------------------------------------------------------------------------
" Realtime reciprocal Parent/Child link sync (lightweight)
" ---------------------------------------------------------------------------

let s:realtime_sync_busy = 0

function! s:section_link_targets_from_lines(lines, name, base_dir) abort
  let l:idx = s:find_section_index_in_lines(a:lines, a:name)
  if l:idx < 0
    return []
  endif
  let l:end = s:section_end_index_in_lines(a:lines, l:idx)
  let l:targets = []
  let l:seen = {}
  let l:in_fence = 0
  for l:line in a:lines[l:idx + 1 : l:end - 1]
    let l:stripped = trim(l:line)
    if l:stripped =~# '^```'
      let l:in_fence = !l:in_fence
      continue
    endif
    if l:in_fence || l:stripped =~# '^_\{3,}\s*$'
      continue
    endif
    let l:start = 0
    while 1
      let l:m = matchstrpos(l:line, '\v\[[^\]]+\]\(([^)]*)\)', l:start)
      if empty(l:m) || l:m[1] < 0
        break
      endif
      let l:raw = l:m[0]
      let l:target = s:extract_target(l:raw)
      if !empty(l:target)
        let l:fp = yurii_pkm#resolve_link(l:target, a:base_dir)
        if filereadable(l:fp) && s:is_markdown_file(l:fp)
          let l:fp = fnamemodify(l:fp, ':p')
          if !has_key(l:seen, l:fp)
            let l:seen[l:fp] = 1
            call add(l:targets, l:fp)
          endif
        endif
      endif
      let l:start = l:m[2]
    endwhile
  endfor
  return l:targets
endfunction

function! s:body_link_targets_from_lines(lines, base_dir) abort
  let l:targets = []
  let l:seen = {}
  let l:in_yaml = 0
  let l:in_fence = 0
  for l:i in range(0, len(a:lines) - 1)
    let l:line = a:lines[l:i]
    let l:stripped = trim(l:line)
    if l:i == 0 && l:stripped ==# '---'
      let l:in_yaml = 1
      continue
    endif
    if l:in_yaml
      if l:stripped ==# '---'
        let l:in_yaml = 0
      endif
      continue
    endif
    if l:stripped =~# '^```'
      let l:in_fence = !l:in_fence
      continue
    endif
    if l:in_fence
      continue
    endif
    if l:stripped =~# '^_\{3,}\s*$'
      break
    endif
    if s:is_known_section_header_text(l:stripped)
      break
    endif

    let l:start = 0
    while 1
      let l:m = matchstrpos(l:line, '\v\[[^\]]+\]\(([^)]*)\)', l:start)
      if empty(l:m) || l:m[1] < 0
        break
      endif
      let l:target = s:extract_target(l:m[0])
      if !empty(l:target)
        let l:fp = yurii_pkm#resolve_link(l:target, a:base_dir)
        if filereadable(l:fp) && s:is_markdown_file(l:fp)
          let l:fp = fnamemodify(l:fp, ':p')
          if !has_key(l:seen, l:fp)
            let l:seen[l:fp] = 1
            call add(l:targets, l:fp)
          endif
        endif
      endif
      let l:start = l:m[2]
    endwhile
  endfor
  return l:targets
endfunction

function! s:current_reciprocal_snapshot(...) abort
  let l:include_back = a:0 > 0 ? a:1 : get(g:, 'yurii_pkm_realtime_backlink_sync', 0)
  let l:file = expand('%:p')
  if empty(l:file)
    return {'up': [], 'down': [], 'back': []}
  endif
  let l:lines = getline(1, '$')
  let l:base = fnamemodify(l:file, ':h')
  return {
        \ 'up': s:section_link_targets_from_lines(l:lines, 'up', l:base),
        \ 'down': s:section_link_targets_from_lines(l:lines, 'down', l:base),
        \ 'back': l:include_back ? s:body_link_targets_from_lines(l:lines, l:base) : [],
        \ }
endfunction

function! yurii_pkm#realtime_sync_snapshot() abort
  if !s:is_markdown_file(expand('%:p'))
    return
  endif
  if line('$') > get(g:, 'yurii_pkm_realtime_link_sync_max_lines', 2000)
    let b:yurii_pkm_realtime_snapshot = {'up': [], 'down': [], 'back': []}
    return
  endif
  let b:yurii_pkm_realtime_snapshot = s:current_reciprocal_snapshot()
endfunction

function! s:list_diff(new, old) abort
  let l:old = {}
  for l:item in a:old
    let l:old[l:item] = 1
  endfor
  let l:diff = []
  for l:item in a:new
    if !has_key(l:old, l:item)
      call add(l:diff, l:item)
    endif
  endfor
  return l:diff
endfunction

function! s:note_lines_for_path(path) abort
  let l:buf = bufnr(a:path)
  if l:buf > 0 && bufloaded(l:buf)
    return getbufline(l:buf, 1, '$')
  endif
  return filereadable(a:path) ? readfile(a:path) : []
endfunction

function! s:write_note_lines_for_path(path, lines) abort
  let l:buf = bufnr(a:path)
  if l:buf > 0 && bufloaded(l:buf)
    call setbufline(l:buf, 1, a:lines)
    let l:old_last = getbufinfo(l:buf)[0].linecount
    if l:old_last > len(a:lines)
      call deletebufline(l:buf, len(a:lines) + 1, l:old_last)
    endif
  else
    call writefile(a:lines, a:path)
  endif
endfunction

function! s:remove_link_to_path_from_lines_section(lines, name, target_path, base_dir) abort
  let l:idx = s:find_section_index_in_lines(a:lines, a:name)
  if l:idx < 0
    return {'lines': copy(a:lines), 'removed': 0}
  endif
  let l:lines = copy(a:lines)
  let l:end = s:section_end_index_in_lines(l:lines, l:idx)
  let l:out = []
  let l:removed = 0
  let l:target = fnamemodify(a:target_path, ':p')
  let l:in_fence = 0
  for l:line in l:lines[l:idx + 1 : l:end - 1]
    let l:stripped = trim(l:line)
    if l:stripped =~# '^```'
      let l:in_fence = !l:in_fence
      call add(l:out, l:line)
      continue
    endif
    if l:in_fence
      call add(l:out, l:line)
      continue
    endif
    let l:new_line = ''
    let l:last = 0
    let l:start = 0
    let l:line_removed = 0
    while 1
      let l:m = matchstrpos(l:line, '\v\[[^\]]+\]\(([^)]*)\)', l:start)
      if empty(l:m) || l:m[1] < 0
        break
      endif
      let l:raw = l:m[0]
      let l:target_text = s:extract_target(l:raw)
      let l:resolved = empty(l:target_text) ? '' : yurii_pkm#resolve_link(l:target_text, a:base_dir)
      let l:new_line .= strpart(l:line, l:last, l:m[1] - l:last)
      if !empty(l:resolved) && fnamemodify(l:resolved, ':p') ==# l:target
        let l:removed = 1
        let l:line_removed = 1
      else
        let l:new_line .= l:raw
      endif
      let l:last = l:m[2]
      let l:start = l:m[2]
    endwhile
    let l:new_line .= strpart(l:line, l:last)
    if l:line_removed && empty(trim(l:new_line))
      continue
    endif
    call add(l:out, l:line_removed ? substitute(l:new_line, '\s\+$', '', '') : l:line)
  endfor
  if !l:removed
    return {'lines': l:lines, 'removed': 0}
  endif
  return {'lines': l:lines[: l:idx] + l:out + l:lines[l:end :], 'removed': 1}
endfunction

function! s:add_reciprocal_link(target_path, section_name, current_file, current_title) abort
  if !filereadable(a:target_path)
    return 0
  endif
  let l:lines = s:note_lines_for_path(a:target_path)
  let l:link = s:make_link_from_dir(a:current_file, a:current_title, fnamemodify(a:target_path, ':h'))
  let l:result = s:add_link_to_lines_section(l:lines, a:section_name, l:link)
  if l:result.added
    call s:write_note_lines_for_path(a:target_path, l:result.lines)
    return 1
  endif
  return 0
endfunction

function! s:remove_reciprocal_link(target_path, section_name, current_file) abort
  if !filereadable(a:target_path)
    return 0
  endif
  let l:lines = s:note_lines_for_path(a:target_path)
  let l:result = s:remove_link_to_path_from_lines_section(
        \ l:lines, a:section_name, a:current_file, fnamemodify(a:target_path, ':h'))
  if l:result.removed
    call s:write_note_lines_for_path(a:target_path, l:result.lines)
    return 1
  endif
  return 0
endfunction

function! s:realtime_sync_apply() abort
  if s:realtime_sync_busy || !get(g:, 'yurii_pkm_realtime_link_sync', 1)
    return
  endif
  if !s:is_markdown_file(expand('%:p')) || &buftype !=# ''
    return
  endif
  let l:file = expand('%:p')
  let l:root = s:get_pkm_root()
  if empty(l:root) || empty(l:file) || l:file !~# '^' . escape(l:root, '/\')
    return
  endif

  let l:old = get(b:, 'yurii_pkm_realtime_snapshot', {'up': [], 'down': []})
  if line('$') > get(g:, 'yurii_pkm_realtime_link_sync_max_lines', 2000)
    return
  endif
  let l:new = s:current_reciprocal_snapshot()
  let l:title = yurii_pkm#current_title()
  let l:changed = 0
  let l:back_changed = get(g:, 'yurii_pkm_realtime_backlink_sync', 0)
        \ && (!empty(s:list_diff(l:new.back, get(l:old, 'back', [])))
        \ || !empty(s:list_diff(get(l:old, 'back', []), l:new.back)))

  let s:realtime_sync_busy = 1
  try
    for l:target in s:list_diff(l:new.down, get(l:old, 'down', []))
      let l:changed += s:add_reciprocal_link(l:target, 'up', l:file, l:title)
    endfor
    for l:target in s:list_diff(get(l:old, 'down', []), l:new.down)
      let l:changed += s:remove_reciprocal_link(l:target, 'up', l:file)
    endfor
    for l:target in s:list_diff(l:new.up, get(l:old, 'up', []))
      let l:changed += s:add_reciprocal_link(l:target, 'down', l:file, l:title)
    endfor
    for l:target in s:list_diff(get(l:old, 'up', []), l:new.up)
      let l:changed += s:remove_reciprocal_link(l:target, 'down', l:file)
    endfor
    if l:back_changed
      if &modified
        silent noautocmd update
      endif
      call s:run_update_one_for_sync(l:file)
    endif
  finally
    let s:realtime_sync_busy = 0
  endtry

  let b:yurii_pkm_realtime_snapshot = s:current_reciprocal_snapshot()
  if l:changed
    checktime
  endif
endfunction

function! s:realtime_sync_timer(timer) abort
  call s:realtime_sync_apply()
endfunction

function! yurii_pkm#realtime_sync_on_text_changed() abort
  if !get(g:, 'yurii_pkm_realtime_link_sync', 1)
    return
  endif
  if exists('b:yurii_pkm_realtime_timer')
    call timer_stop(b:yurii_pkm_realtime_timer)
  endif
  if has('timers')
    let b:yurii_pkm_realtime_timer = timer_start(get(g:, 'yurii_pkm_realtime_link_sync_delay', 800), function('s:realtime_sync_timer'))
  else
    call s:realtime_sync_apply()
  endif
endfunction

" Backward compatible name
function! s:branch_end_line() abort
  return s:down_end_line()
endfunction


" Return last line of 'back' section (before ___ or EOF), or 0
function! s:back_end_line() abort
  let l:back = s:find_section_line('back')
  if l:back <= 0
    return 0
  endif
  for l:i in range(l:back + 1, line('$'))
    if getline(l:i) =~# '^_\{3,}\s*$'
      return l:i - 1
    endif
  endfor
  return line('$')
endfunction

function! s:in_back_section(lnum) abort
  let l:back = s:find_section_line('back')
  if l:back <= 0
    return 0
  endif
  return a:lnum >= l:back + 1
endfunction

function! s:in_up_section(lnum) abort
  let l:up = s:find_section_line('up')
  if l:up <= 0
    return 0
  endif
  let l:up_end = s:up_end_line()
  return a:lnum >= l:up + 1 && a:lnum <= l:up_end
endfunction

function! s:find_reciprocal_link_pos(target_path, source_name) abort
  if !filereadable(a:target_path)
    return [0, 0]
  endif
  let l:lines = readfile(a:target_path)
  let l:back_line = len(l:lines) + 1
  for l:i in range(0, len(l:lines) - 1)
    if s:is_section_header_text(l:lines[l:i], 'back')
      let l:back_line = l:i + 1
      break
    endif
  endfor

  for l:lnum in range(1, l:back_line - 1)
    let l:line = get(l:lines, l:lnum - 1, '')
    let l:start = 0
    while 1
      let l:m = matchstrpos(l:line, s:link_pat, l:start)
      if len(l:m) < 3 || l:m[1] < 0
        break
      endif
      let l:parts = matchlist(l:m[0], '\v\[([^\]]+)\]\(([^)]*)\)')
      let l:target = fnamemodify(get(l:parts, 2, ''), ':t')
      if l:target ==# a:source_name
        return [l:lnum, l:m[1] + 1]
      endif
      let l:start = l:m[2]
    endwhile
  endfor
  return [0, 0]
endfunction


" ---------------------------------------------------------------------------
" Link navigation
" ---------------------------------------------------------------------------

function! yurii_pkm#jump_link(forward) abort
  let l:flags = a:forward ? 'W' : 'bW'
  if !search(s:link_pat, l:flags)
    echo 'No more links'
    return
  endif
  " search() のマッチ先頭 ([) にそのまま止める
endfunction


function! s:jump_to_line(lnum) abort
  call cursor(a:lnum, 1)
  normal! zv
endfunction

function! yurii_pkm#jump_section_header(name) abort
  let l:sec = s:find_section_line(a:name)
  if l:sec <= 0
    echo '# ' . a:name . ' section not found'
    return
  endif

  call s:jump_to_line(l:sec)
endfunction

function! s:section_link_positions(name) abort
  let l:sec = s:find_section_line(a:name)
  if l:sec <= 0
    return []
  endif

  let l:end = s:section_end_line(a:name)
  if l:end <= l:sec
    return []
  endif

  let l:positions = []
  for l:lnum in range(l:sec + 1, l:end)
    let l:line = getline(l:lnum)
    let l:start = 0
    while 1
      let l:m = matchstrpos(l:line, s:link_pat, l:start)
      if len(l:m) < 3 || l:m[1] < 0
        break
      endif
      call add(l:positions, {'lnum': l:lnum, 'col': l:m[1] + 1})
      let l:start = l:m[2]
    endwhile
  endfor
  return l:positions
endfunction

function! yurii_pkm#jump_up() abort
  let l:up = s:find_section_line('up')
  if l:up <= 0
    echo 'Parent: section not found'
    return
  endif

  let l:links = s:section_link_positions('up')
  if len(l:links) == 1
    call cursor(l:links[0].lnum, l:links[0].col)
    normal! zv
    call yurii_pkm#open_link_under_cursor()
    return
  endif
  if len(l:links) >= 2
    call cursor(l:links[0].lnum, l:links[0].col)
    normal! zv
    return
  endif

  call s:jump_to_line(l:up)
endfunction

function! yurii_pkm#jump_down_top() abort
  let l:down = s:find_section_line('down')
  if l:down <= 0
    echo 'Child: section not found'
    return
  endif

  let l:end = s:section_end_line('down')
  call s:jump_to_line(l:end > l:down ? l:down + 1 : l:down)
endfunction

function! yurii_pkm#jump_down_bottom() abort
  let l:up_links = s:section_link_positions('up')
  if len(l:up_links) >= 2
    call cursor(l:up_links[0].lnum, l:up_links[0].col)
    normal! zv
    return
  endif

  let l:down = s:find_section_line('down')
  if l:down <= 0
    echo 'Child: section not found'
    return
  endif

  let l:end = s:section_end_line('down')
  call s:jump_to_line(l:end > l:down ? l:end : l:down)
endfunction

function! yurii_pkm#jump_last_link_before_up() abort
  let l:up = s:find_section_line('up')
  if l:up <= 0
    echo 'Parent section not found'
    return
  endif

  let l:last_lnum = 0
  let l:last_col = 0
  for l:lnum in range(1, l:up - 1)
    let l:line = getline(l:lnum)
    let l:start = 0
    while 1
      let l:m = matchstrpos(l:line, s:link_pat, l:start)
      if len(l:m) < 3 || l:m[1] < 0
        break
      endif
      let l:last_lnum = l:lnum
      let l:last_col = l:m[1] + 1
      let l:start = l:m[2]
    endwhile
  endfor

  if l:last_lnum <= 0
    let l:up_end = s:up_end_line()
    if l:up_end > l:up
      for l:lnum in range(l:up + 1, l:up_end)
        let l:line = getline(l:lnum)
        let l:m = matchstrpos(l:line, s:link_pat, 0)
        if len(l:m) >= 3 && l:m[1] >= 0
          let l:last_lnum = l:lnum
          let l:last_col = l:m[1] + 1
          break
        endif
      endfor
    endif
  endif

  if l:last_lnum <= 0
    echo 'No links before Parent or in Parent'
    return
  endif

  call cursor(l:last_lnum, l:last_col)
  normal! zv
endfunction

" --- v2: 文中リンク / 関係リンクの位置一覧 --------------------------------
function! s:link_positions_in_range(lo, hi) abort
  let l:pos = []
  let l:lo = max([a:lo, 1])
  let l:hi = min([a:hi, line('$')])
  if l:lo > l:hi | return l:pos | endif
  for l:lnum in range(l:lo, l:hi)
    let l:line = getline(l:lnum)
    let l:start = 0
    while 1
      let l:m = matchstrpos(l:line, s:link_pat, l:start)
      if len(l:m) < 3 || l:m[1] < 0 | break | endif
      call add(l:pos, {'lnum': l:lnum, 'col': l:m[1] + 1})
      let l:start = l:m[2]
    endwhile
  endfor
  return l:pos
endfunction

" 本文（こっちにとって の見張りより前）のリンク。v2 ノート以外は空。
function! s:v2_body_link_positions() abort
  let [l:up_m, l:dn_m] = s:v2_boundaries()
  if l:up_m <= 0 | return [] | endif
  return s:link_positions_in_range(1, l:up_m - 1)
endfunction

" parent/child（こっちにとって + そっちにとって）のリンク。
" v2 なら見張りコメント基準、v1 なら旧セクション基準。
function! s:v2_relation_link_positions() abort
  let [l:up_m, l:dn_m] = s:v2_boundaries()
  if l:up_m > 0
    return s:link_positions_in_range(l:up_m + 1, line('$'))
  endif
  return s:section_link_positions('up') + s:section_link_positions('down')
endfunction

function! s:pos_after(a, b) abort
  return a:a[0] > a:b[0] || (a:a[0] == a:b[0] && a:a[1] > a:b[1])
endfunction

" <Space> … parent/child（文中は対象外）のリンクを順に巡回。端で折り返す。
function! yurii_pkm#jump_relation_link(forward) abort
  let l:pos = s:v2_relation_link_positions()
  if empty(l:pos)
    " ノートじゃない／関係リンクなし → 通常の <Space>/<BS> 相当
    execute 'normal! ' . (a:forward ? 'l' : 'h')
    return
  endif
  let l:cur = [line('.'), col('.')]
  let l:dest = []
  if a:forward
    for l:p in l:pos
      if s:pos_after([l:p.lnum, l:p.col], l:cur)
        let l:dest = l:p | break
      endif
    endfor
    if empty(l:dest) | let l:dest = l:pos[0] | endif
  else
    for l:i in range(len(l:pos) - 1, 0, -1)
      if s:pos_after(l:cur, [l:pos[l:i].lnum, l:pos[l:i].col])
        let l:dest = l:pos[l:i] | break
      endif
    endfor
    if empty(l:dest) | let l:dest = l:pos[-1] | endif
  endif
  call cursor(l:dest.lnum, l:dest.col)
  normal! zv
endfunction

" --- 行配列ベースの収集ヘルパ（ウォークモード用。バッファ非依存） -----------

" s:link_positions_in_range() の行配列版（lo/hi は 1-based）
function! s:link_positions_in_lines(lines, lo, hi) abort
  let l:pos = []
  let l:lo = max([a:lo, 1])
  let l:hi = min([a:hi, len(a:lines)])
  if l:lo > l:hi | return l:pos | endif
  for l:lnum in range(l:lo, l:hi)
    let l:line = a:lines[l:lnum - 1]
    let l:start = 0
    while 1
      let l:m = matchstrpos(l:line, s:link_pat, l:start)
      if len(l:m) < 3 || l:m[1] < 0 | break | endif
      call add(l:pos, {'lnum': l:lnum, 'col': l:m[1] + 1})
      let l:start = l:m[2]
    endwhile
  endfor
  return l:pos
endfunction

" s:v2_boundaries() の行配列版（返り値も 1-based 行番号）
function! s:v2_boundaries_in_lines(lines) abort
  let l:up_m = 0 | let l:dn_m = 0
  for l:i in range(0, len(a:lines) - 1)
    let l:s = trim(a:lines[l:i])
    if l:s ==# s:v2_up_mark || index(s:v2_up_marks_legacy, l:s) >= 0     | let l:up_m = l:i + 1 | endif
    if l:s ==# s:v2_down_mark || index(s:v2_down_marks_legacy, l:s) >= 0 | let l:dn_m = l:i + 1 | endif
  endfor
  if l:up_m > 0 && l:dn_m > l:up_m
    return [l:up_m, l:dn_m]
  endif
  return [0, 0]
endfunction

function! s:section_link_positions_in_lines(lines, name) abort
  let l:idx = s:find_section_index_in_lines(a:lines, a:name)
  if l:idx < 0 | return [] | endif
  let l:end = s:section_end_index_in_lines(a:lines, l:idx)
  if l:end <= l:idx + 1 | return [] | endif
  return s:link_positions_in_lines(a:lines, l:idx + 2, l:end)
endfunction

" s:v2_relation_link_positions() の行配列版
function! s:v2_relation_link_positions_in_lines(lines) abort
  let [l:up_m, l:dn_m] = s:v2_boundaries_in_lines(a:lines)
  if l:up_m > 0
    return s:link_positions_in_lines(a:lines, l:up_m + 1, len(a:lines))
  endif
  return s:section_link_positions_in_lines(a:lines, 'up')
        \ + s:section_link_positions_in_lines(a:lines, 'down')
endfunction

" parent/child のリンクを『ラベル / 表示名 / こっちにとって・そっちにとって』付きで集める。
"   {lnum, col, side('up'|'down'), label, text, target}
function! s:relation_links_from_lines(lines, base_dir) abort
  let l:pos = s:v2_relation_link_positions_in_lines(a:lines)
  if empty(l:pos) | return [] | endif
  let [l:up_m, l:dn_m] = s:v2_boundaries_in_lines(a:lines)
  let l:down_start = l:dn_m > 0 ? l:dn_m
        \ : (s:find_section_index_in_lines(a:lines, 'down') + 1)
  let l:out = []
  for l:p in l:pos
    " ラベル: その行 or 上方向で最初に見つかる『語:』行（リンク行は飛ばす）
    let l:label = ''
    for l:ln in range(l:p.lnum, max([l:p.lnum - 20, 1]), -1)
      let l:t = get(a:lines, l:ln - 1, '')
      if l:t =~# '^\s*\[' | continue | endif
      let l:h = matchstr(l:t, '^\s*\zs[^[:space:]:][^:]\{-}\ze\s*:')
      if !empty(l:h) | let l:label = trim(l:h) | break | endif
    endfor
    let l:raw = matchstr(get(a:lines, l:p.lnum - 1, ''), s:link_pat, l:p.col - 1)
    let l:parts = matchlist(l:raw, '\v\[([^\]]*)\]\(([^)]*)\)')
    call add(l:out, {
          \ 'lnum': l:p.lnum, 'col': l:p.col,
          \ 'side': (l:down_start > 0 && l:p.lnum > l:down_start) ? 'down' : 'up',
          \ 'label': l:label,
          \ 'text': get(l:parts, 1, ''), 'target': get(l:parts, 2, '')})
  endfor
  return l:out
endfunction

" 本文（こっちにとって 見張りより前）のリンクを、直近の見出しを label にして集める。
"   {lnum, col, side('body'), label, text, target}
function! s:body_links_from_lines(lines, base_dir) abort
  let [l:up_m, l:dn_m] = s:v2_boundaries_in_lines(a:lines)
  if l:up_m <= 0 | return [] | endif
  let l:pos = s:link_positions_in_lines(a:lines, 1, l:up_m - 1)
  if empty(l:pos) | return [] | endif
  let l:out = []
  for l:p in l:pos
    let l:label = ''
    for l:ln in range(l:p.lnum, max([l:p.lnum - 40, 1]), -1)
      let l:t = get(a:lines, l:ln - 1, '')
      let l:hd = matchstr(l:t, '^#\+\s\+\zs.\+')
      if !empty(l:hd) | let l:label = trim(l:hd) | break | endif
    endfor
    let l:raw = matchstr(get(a:lines, l:p.lnum - 1, ''), s:link_pat, l:p.col - 1)
    let l:parts = matchlist(l:raw, '\v\[([^\]]*)\]\(([^)]*)\)')
    call add(l:out, {
          \ 'lnum': l:p.lnum, 'col': l:p.col, 'side': 'body',
          \ 'label': l:label,
          \ 'text': get(l:parts, 1, ''), 'target': get(l:parts, 2, '')})
  endfor
  return l:out
endfunction

" 文中 / こっちにとって / そっちにとって の3グループにまとめる
function! s:space_collect(lines, base_dir) abort
  let l:rel = s:relation_links_from_lines(a:lines, a:base_dir)
  return {
        \ 'body': s:body_links_from_lines(a:lines, a:base_dir),
        \ 'up':   filter(copy(l:rel), 'v:val.side ==# "up"'),
        \ 'down': filter(copy(l:rel), 'v:val.side ==# "down"'),
        \ }
endfunction

" グループを区切り行付きの平坦な一覧にする（区切りは {sep:1, title:...}）
function! s:space_flatten(groups) abort
  let l:items = []
  for [l:key, l:title] in [['body', '文中'], ['up', 'こっちにとって'], ['down', 'そっちにとって']]
    let l:g = get(a:groups, l:key, [])
    if empty(l:g) | continue | endif
    call add(l:items, {'sep': 1, 'title': l:title})
    call extend(l:items, l:g)
  endfor
  return l:items
endfunction

" ---------------------------------------------------------------------------
" <Space> ナビゲータ
"   スコープ  local（今のノートのリンク） / global（全ノート検索）
"   サブモード input（打つ=絞り込み） / select（プレーンキーでナビ）
" キーは両スコープ共通。ラベルキーは常に「選択」だけ。
" ---------------------------------------------------------------------------

let s:rlp_win = -1
let s:rlp_pvwin = -1
let s:rlp_items = []          " 表示中の行（区切り込み）
let s:rlp_sel = 0
let s:rlp_top = 0
let s:rlp_rows = 14
let s:rlp_geo = {}
let s:rlp_scope = 'local'     " 'local' | 'global'
let s:rlp_input = 0           " 1 = 打つとクエリ / 0 = 打つとコマンド
let s:rlp_query = ''
let s:rlp_terms = []
let s:rlp_path = ''           " アンカー = いま一覧を出しているノート
let s:rlp_base = ''
let s:rlp_groups = {}         " local: s:space_collect の結果
let s:rlp_stack = []          " [{path,base,sel,top,scope,query,mode}]
let s:rlp_crumbs = []
let s:rlp_origin = {}         " {bufnr,pos,path}
let s:rlp_cands = []          " [{p,t,b}] 全ノート索引
let s:rlp_rowmap = {}         " ラベル文字 -> s:rlp_items のインデックス
let s:rlp_marks = {}          " path -> 1（popup を閉じても残す）
let s:rlp_want_cursor_init = 0
" コマンド文字（j k l h g G f b i c p y a m n d q）を避けたラベル
let s:rlp_labels = '1234567890esrtuvwxzo'

function! s:rlp_labels_str() abort
  return get(g:, 'yurii_pkm_space_labels', s:rlp_labels)
endfunction

" --- 行の基本操作 -----------------------------------------------------------

function! s:rlp_is_sel(i) abort
  return a:i >= 0 && a:i < len(s:rlp_items) && !get(s:rlp_items[a:i], 'sep', 0)
endfunction

function! s:rlp_first_sel() abort
  for l:i in range(len(s:rlp_items))
    if !get(s:rlp_items[l:i], 'sep', 0) | return l:i | endif
  endfor
  return -1
endfunction

function! s:rlp_last_sel() abort
  for l:i in range(len(s:rlp_items) - 1, 0, -1)
    if !get(s:rlp_items[l:i], 'sep', 0) | return l:i | endif
  endfor
  return -1
endfunction

function! s:rlp_step_sel(dir) abort
  let l:i = s:rlp_sel + a:dir
  while l:i >= 0 && l:i < len(s:rlp_items)
    if !get(s:rlp_items[l:i], 'sep', 0)
      let s:rlp_sel = l:i | return
    endif
    let l:i += a:dir
  endwhile
endfunction

function! s:rlp_sel_item() abort
  return s:rlp_is_sel(s:rlp_sel) ? s:rlp_items[s:rlp_sel] : {}
endfunction

" 行 -> 実ファイルパス（link 行はアンカー基準で解決、それ以外は path をそのまま）
function! s:rlp_row_path(it) abort
  if empty(a:it) | return '' | endif
  if get(a:it, 'kind', '') ==# 'link'
    return s:resolve_link_for_navigation(a:it.target, s:rlp_base)
  endif
  return get(a:it, 'path', '')
endfunction

" 末尾を残して頭を削る（パンくず用。今どこに居るかは末尾が大事）
function! s:rlp_trunc_tail(s, w) abort
  if a:w <= 1 | return a:s | endif
  if strdisplaywidth(a:s) <= a:w | return a:s | endif
  let l:s = a:s
  while strchars(l:s) > 1 && strdisplaywidth(l:s) > a:w - 1
    let l:s = strcharpart(l:s, 1)
  endwhile
  return '…' . l:s
endfunction

" 頭を残して末尾を削る（ノート名・ラベル用。頭が読めないと何のノートか分からない）
function! s:rlp_trunc_head(s, w) abort
  if a:w <= 1 | return a:s | endif
  if strdisplaywidth(a:s) <= a:w | return a:s | endif
  let l:s = a:s
  while strchars(l:s) > 1 && strdisplaywidth(l:s) > a:w - 1
    let l:s = strcharpart(l:s, 0, strchars(l:s) - 1)
  endwhile
  return l:s . '…'
endfunction

function! s:rlp_crumb_line(w) abort
  let l:c = copy(s:rlp_crumbs)
  if empty(l:c) | return '·' | endif
  call map(l:c, {_, v -> strchars(v) > 16 ? strcharpart(v, 0, 15) . '…' : v})
  let l:s = len(l:c) <= 2 ? join(l:c, ' › ') : l:c[0] . ' › … › ' . l:c[-1]
  return s:rlp_trunc_tail(l:s, a:w)
endfunction

" --- 候補の組み立て ---------------------------------------------------------

function! s:rlp_set_terms() abort
  let s:rlp_terms = map(
        \ filter(split(substitute(s:rlp_query, '　', ' ', 'g'), ' '), 'v:val !=# ""'),
        \ 'tolower(v:val)')
endfunction

function! s:rlp_match(hay) abort
  if empty(s:rlp_terms) | return 1 | endif
  let l:h = tolower(a:hay)
  for l:t in s:rlp_terms
    if stridx(l:h, l:t) < 0 | return 0 | endif
  endfor
  return 1
endfunction

function! s:rlp_build_local() abort
  let l:items = []
  if !empty(s:rlp_path) && filereadable(s:rlp_path)
    call add(l:items, {'kind': 'anchor', 'path': s:rlp_path, 'label': '',
          \ 'text': s:get_title(s:rlp_path)})
  endif
  for [l:key, l:title] in [['body', '文中'], ['up', 'こっちにとって'], ['down', 'そっちにとって']]
    let l:g = get(s:rlp_groups, l:key, [])
    let l:hit = filter(copy(l:g), 's:rlp_match(v:val.label . " " . v:val.text)')
    if empty(l:hit) | continue | endif
    call add(l:items, {'sep': 1, 'title': l:title})
    for l:x in l:hit
      let l:y = copy(l:x)
      let l:y.kind = 'link'
      call add(l:items, l:y)
    endfor
  endfor
  return l:items
endfunction

function! s:rlp_build_global() abort
  let l:items = []
  for l:c in s:rlp_cands
    if s:rlp_match(l:c.t . ' ' . l:c.b)
      call add(l:items, {'kind': 'note', 'path': l:c.p, 'text': l:c.t, 'label': ''})
    endif
  endfor
  return l:items
endfunction

function! s:rlp_refresh() abort
  call s:rlp_set_terms()
  let s:rlp_items = (s:rlp_scope ==# 'global')
        \ ? s:rlp_build_global() : s:rlp_build_local()
  if !s:rlp_is_sel(s:rlp_sel)
    let s:rlp_sel = max([s:rlp_first_sel(), 0])
  endif
endfunction

function! s:rlp_build_index() abort
  let l:root = s:get_pkm_root()
  if empty(l:root) || !isdirectory(l:root) | let l:root = getcwd() | endif
  let l:idx = get(g:, 'yurii_search_index', '')
  let s:rlp_cands = []
  if !empty(l:idx) && filereadable(l:idx) && executable('python3')
    for l:ln in systemlist('python3 ' . shellescape(l:idx) . ' ' . shellescape(l:root))
      let l:f = split(l:ln, "\t", 1)
      if len(l:f) >= 2
        call add(s:rlp_cands, {'p': l:f[0], 't': l:f[1], 'b': get(l:f, 2, '')})
      endif
    endfor
  endif
  if empty(s:rlp_cands)
    " フォールバック: *.md を舐めてタイトルだけ（本文検索は効かない）
    for l:p in split(globpath(l:root, '**/*.md', 0), "\n")
      if l:p =~# '[\\/]\.undo[\\/]' | continue | endif
      call add(s:rlp_cands, {'p': l:p, 't': s:get_title(l:p), 'b': ''})
    endfor
  endif
  " 最近訪問した順に固定する。無クエリでも絞り込み後でも並びが安定し、
  " 「決める時間」が減る（NAVIGATION.md 根本4）。
  let l:recent = yurii_pkm#recent_map()
  call map(s:rlp_cands, {_, c -> extend(c,
        \ {'r': get(l:recent, fnamemodify(c.p, ':p'), 0)})})
  call sort(s:rlp_cands, {a, b -> b.r == a.r ? (a.t < b.t ? -1 : 1) : b.r - a.r})
endfunction

" --- ジオメトリ -------------------------------------------------------------

function! s:rlp_geometry() abort
  if get(g:, 'yurii_pkm_space_fullscreen', 1)
    " popup 1 個の画面占有 = 宣言幅/高 + border(2) + padding(横2/縦0)
    let l:chrome_w = 4
    let l:chrome_h = 2
    let l:outer = 1
    let l:gap = 1
    let l:top = 1 + l:outer
    let l:h = max([&lines - l:chrome_h - 2 * l:outer, 8])
    let l:lw = get(g:, 'yurii_pkm_space_list_width', 0)
    if l:lw <= 0
      let l:lw = max([36, min([float2nr(&columns * 0.38), 58])])
    endif
    let l:list_col = 1 + l:outer
    let l:pv_col = l:list_col + l:lw + l:chrome_w + l:gap
    let l:pvw = max([&columns - l:pv_col - l:chrome_w - l:outer + 1, 20])
    return {
          \ 'list_line': l:top, 'list_col': l:list_col, 'list_w': l:lw, 'h': l:h,
          \ 'pv_line': l:top, 'pv_col': l:pv_col, 'pv_w': l:pvw,
          \ 'rows': max([l:h - 6, 3]),
          \ }
  endif
  let l:rows = min([max([len(s:rlp_items), 1]), 10])
  let l:h = l:rows + 5
  let l:w = min([float2nr(&columns * 0.40), 56])
  let l:pv = min([float2nr(&columns * 0.46), 90])
  let l:col = max([(&columns - (l:w + 3 + l:pv)) / 2, 2])
  let l:line = max([(&lines - l:h) / 2, 1])
  return {
        \ 'list_line': l:line, 'list_col': l:col, 'list_w': l:w, 'h': l:h,
        \ 'pv_line': l:line, 'pv_col': l:col + l:w + 3, 'pv_w': l:pv,
        \ 'rows': l:rows,
        \ }
endfunction

" --- 読み込み / 移動 --------------------------------------------------------

function! s:rlp_load(path, base, ...) abort
  let l:keep_sel = a:0 > 0 ? a:1 : -1
  let l:keep_top = a:0 > 1 ? a:2 : 0
  let s:rlp_path = a:path
  let s:rlp_base = a:base
  let s:rlp_scope = 'local'
  if a:path ==# get(s:rlp_origin, 'path', '') && get(s:rlp_origin, 'bufnr', -1) > 0
    let l:lines = getbufline(s:rlp_origin.bufnr, 1, '$')
  else
    let l:lines = filereadable(a:path) ? readfile(a:path) : []
  endif
  let s:rlp_groups = s:space_collect(l:lines, a:base)
  call s:rlp_refresh()

  if s:rlp_want_cursor_init
    let s:rlp_want_cursor_init = 0
    let l:cur = s:rlp_origin.pos[1:2]
    let s:rlp_sel = max([s:rlp_first_sel(), 0])
    for l:i in range(len(s:rlp_items))
      let l:it = s:rlp_items[l:i]
      if get(l:it, 'kind', '') !=# 'link' | continue | endif
      if s:pos_after([l:it.lnum, l:it.col], l:cur)
        let s:rlp_sel = l:i | break
      endif
    endfor
    let s:rlp_top = 0
  elseif l:keep_sel >= 0 && s:rlp_is_sel(l:keep_sel)
    let s:rlp_sel = l:keep_sel
    let s:rlp_top = l:keep_top
  else
    let s:rlp_sel = max([s:rlp_first_sel(), 0])
    let s:rlp_top = 0
  endif
  call s:rlp_render()
endfunction

" 選択行のノートへ『潜る』（ポップアップは開いたまま local ビューを積む）
function! s:rlp_dive(idx) abort
  if !s:rlp_is_sel(a:idx) | return | endif
  let l:it = s:rlp_items[a:idx]
  if get(l:it, 'kind', '') ==# 'anchor'
    " アンカー（自分自身）には潜れない。選ぶだけ ＝ ⏎ で開ける状態にする
    let s:rlp_sel = a:idx
    call s:rlp_render()
    return
  endif
  let l:p = s:rlp_row_path(l:it)
  if empty(l:p) || (!filereadable(l:p) && !isdirectory(l:p)) | return | endif
  if isdirectory(l:p) || !s:is_markdown_file(l:p)
    call popup_close(s:rlp_win, {'open': a:idx})
    return
  endif
  call add(s:rlp_stack, {'path': s:rlp_path, 'base': s:rlp_base,
        \ 'sel': s:rlp_sel, 'top': s:rlp_top,
        \ 'scope': s:rlp_scope, 'query': s:rlp_query, 'input': s:rlp_input})
  call add(s:rlp_crumbs, fnamemodify(l:p, ':t:r'))
  let s:rlp_query = ''
  let s:rlp_input = 0
  call s:rlp_load(l:p, fnamemodify(l:p, ':h'))
endfunction

function! s:rlp_back() abort
  if empty(s:rlp_stack)
    call popup_close(s:rlp_win, {'cancel': 1})
    return
  endif
  let l:prev = remove(s:rlp_stack, -1)
  if !empty(s:rlp_crumbs) | call remove(s:rlp_crumbs, -1) | endif
  let s:rlp_query = get(l:prev, 'query', '')
  let s:rlp_input = get(l:prev, 'input', 0)
  if get(l:prev, 'scope', 'local') ==# 'global'
    let s:rlp_scope = 'global'
    call s:rlp_refresh()
    let s:rlp_sel = l:prev.sel
    let s:rlp_top = l:prev.top
    if !s:rlp_is_sel(s:rlp_sel)
      let s:rlp_sel = max([s:rlp_first_sel(), 0])
    endif
    call s:rlp_render()
    return
  endif
  call s:rlp_load(l:prev.path, l:prev.base, l:prev.sel, l:prev.top)
endfunction

" --- マーク -----------------------------------------------------------------

function! s:rlp_toggle_mark() abort
  let l:p = s:rlp_row_path(s:rlp_sel_item())
  if empty(l:p) | return | endif
  if has_key(s:rlp_marks, l:p)
    unlet s:rlp_marks[l:p]
  else
    let s:rlp_marks[l:p] = 1
  endif
endfunction

" 適用対象: マークがあればマーク全部、無ければ選択行
function! s:rlp_targets() abort
  if !empty(s:rlp_marks) | return sort(keys(s:rlp_marks)) | endif
  let l:p = s:rlp_row_path(s:rlp_sel_item())
  return empty(l:p) ? [] : [l:p]
endfunction

" --- 描画 -------------------------------------------------------------------

function! s:rlp_render() abort
  if s:rlp_win < 0 | return | endif
  let l:w = max([get(s:rlp_geo, 'list_w', 46) - 2, 10])
  let l:total = len(s:rlp_items)
  if s:rlp_sel < s:rlp_top | let s:rlp_top = s:rlp_sel | endif
  if s:rlp_sel >= s:rlp_top + s:rlp_rows | let s:rlp_top = s:rlp_sel - s:rlp_rows + 1 | endif
  if s:rlp_top < 0 | let s:rlp_top = 0 | endif

  let l:lw = 0
  for l:it in s:rlp_items
    if get(l:it, 'sep', 0) | continue | endif
    let l:lw = max([l:lw, strdisplaywidth(get(l:it, 'label', ''))])
  endfor
  let l:lw = min([l:lw, 14])

  " 上部 = パンくず / 検索バー / 区切り。打つ場所と見る場所を近づける。
  let l:nsel = 0
  for l:it in s:rlp_items
    if !get(l:it, 'sep', 0) | let l:nsel += 1 | endif
  endfor
  let l:nmark = len(s:rlp_marks)
  let l:pos = printf(' %d/%d%s',
        \ l:nsel ? index(filter(range(len(s:rlp_items)),
        \   '!get(s:rlp_items[v:val], "sep", 0)'), s:rlp_sel) + 1 : 0,
        \ l:nsel, l:nmark > 0 ? ' *' . l:nmark : '')
  if s:rlp_typing()
    " 打っているツールだけ検索バーを出す。カーソル ▏ が見えている＝打てる合図。
    let l:qtext = (s:rlp_scope ==# 'global' ? '検索 ' : '絞込 ') . s:rlp_query . '▏'
    let l:right = l:pos
  elseif s:rlp_scope ==# 'global'
    " グローバルのコマンド状態。i で打てることと、効いているクエリを見せる
    let l:qtext = '全ノート' . (empty(s:rlp_query) ? '' : ' ' . s:rlp_query)
    let l:qtext = s:rlp_trunc_head(l:qtext, l:w - 14)
    let l:right = l:pos
  else
    " ローカルは打たないので、バーではなく居場所だけ出す
    let l:qtext = '◎ ' . s:rlp_trunc_head(s:get_title(s:rlp_path), l:w - 14)
    let l:right = l:pos
  endif
  let l:bar = s:rlp_trunc_tail(l:qtext,
        \ max([l:w - strdisplaywidth(l:right), 4]))
  let l:bar .= repeat(' ',
        \ max([l:w - strdisplaywidth(l:bar) - strdisplaywidth(l:right), 0])) . l:right

  let l:lines = [s:rlp_crumb_line(l:w), l:bar, repeat('─', l:w)]
  let l:labels = s:rlp_labels_str()
  let l:ln = 0
  let s:rlp_rowmap = {}
  let l:end = min([s:rlp_top + s:rlp_rows, l:total])
  for l:i in range(s:rlp_top, l:end - 1)
    let l:it = s:rlp_items[l:i]
    if get(l:it, 'sep', 0)
      let l:t = '── ' . l:it.title . ' '
      call add(l:lines, l:t . repeat('─', max([l:w - strdisplaywidth(l:t), 0])))
      continue
    endif
    let l:lbl = ' '
    if l:ln < strchars(l:labels)
      let l:lbl = strcharpart(l:labels, l:ln, 1)
      let s:rlp_rowmap[l:lbl] = l:i
      let l:ln += 1
    endif
    let l:cur = (l:i == s:rlp_sel) ? '▶' : ' '
    let l:mk = has_key(s:rlp_marks, s:rlp_row_path(l:it)) ? '*' : ' '
    let l:kind = get(l:it, 'kind', '')
    if l:kind ==# 'anchor'
      call add(l:lines, l:cur . l:lbl . l:mk . '◎ '
            \ . s:rlp_trunc_head(l:it.text, l:w - 5))
    elseif l:kind ==# 'note'
      call add(l:lines, l:cur . l:lbl . l:mk . '  '
            \ . s:rlp_trunc_head(l:it.text, l:w - 5))
    else
      let l:arw = (l:it.side ==# 'up') ? '→' : (l:it.side ==# 'down' ? '←' : '¶')
      let l:pad = repeat(' ', max([l:lw - strdisplaywidth(l:it.label), 0]))
      let l:pre = printf('%s%s%s%s %s%s  ',
            \ l:cur, l:lbl, l:mk, l:arw, l:it.label, l:pad)
      call add(l:lines, l:pre
            \ . s:rlp_trunc_head(l:it.text, max([l:w - strdisplaywidth(l:pre), 4])))
    endif
  endfor

  let l:below = max([0, l:total - l:end])
  call add(l:lines, l:below > 0
        \ ? '─── ↓' . l:below . ' ' . repeat('─', max([l:w - 6 - len(string(l:below)), 0]))
        \ : repeat('─', l:w))
  if s:rlp_input
    call add(l:lines, '打つ 絞る  ↑↓ 選択  → 潜る  ⏎ 入力終了  ⌫ 消す  ⎋ 消して終了')
  else
    call add(l:lines, s:rlp_scope ==# 'global'
          \ ? '字 移動  ⏎ 開く  l 潜る  ⌫ 戻る  fb プレ  cp 子親  ym  i 打つ  ⇥ 切替'
          \ : '字 潜る  jk 選択  ⏎ 開く  ⌫ 戻る  ␣ ここ  fb プレ  cp 子親  ym  i 打つ  ⇥ 切替')
  endif
  call popup_settext(s:rlp_win, l:lines)
  call popup_setoptions(s:rlp_win,
        \ {'title': s:rlp_scope ==# 'global' ? ' 全ノート ' : ' ローカル '})
  call s:rlp_preview()
endfunction

function! s:rlp_preview() abort
  if s:rlp_pvwin < 0 | return | endif
  let l:it = s:rlp_sel_item()
  if empty(l:it)
    call popup_settext(s:rlp_pvwin, ['(該当なし)'])
    return
  endif
  let l:path = s:rlp_row_path(l:it)
  if empty(l:path) || (!filereadable(l:path) && !isdirectory(l:path))
    call popup_settext(s:rlp_pvwin,
          \ ['(開けない: ' . get(l:it, 'target', get(l:it, 'path', '')) . ')'])
    return
  endif
  if isdirectory(l:path)
    call popup_settext(s:rlp_pvwin, ['(ディレクトリ)', l:path])
    return
  endif
  let l:body = readfile(l:path, '', get(g:, 'yurii_pkm_space_preview_lines', 400))
  if !empty(l:body) && l:body[0] =~# '^---\s*$'
    let l:e = 1
    while l:e < len(l:body) && l:body[l:e] !~# '^\%(---\|\.\.\.\)\s*$'
      let l:e += 1
    endwhile
    let l:body = l:body[l:e + 1 :]
  endif
  while !empty(l:body) && l:body[0] =~# '^\s*$'
    call remove(l:body, 0)
  endwhile
  let l:head = s:get_title(l:path) . '   ' . fnamemodify(l:path, ':t')
  let l:rule = repeat('─', max([get(s:rlp_geo, 'pv_w', 46) - 2, 10]))

  " 検索語を強調し、最初のヒット行が見えるところまでスクロールする。
  " ヒットが見えないと「なぜこれが出てきたのか」が分からず判断できない。
  if empty(s:rlp_terms)
    call popup_settext(s:rlp_pvwin, [l:head, l:rule] + l:body)
    call popup_setoptions(s:rlp_pvwin, {'firstline': 1})
    return
  endif
  call s:rlp_ensure_hl()
  let l:lines = [{'text': l:head}, {'text': l:rule}]
  let l:first = 0
  let l:n = 2
  for l:b in l:body
    let l:n += 1
    let l:props = s:rlp_hit_props(l:b)
    if empty(l:props)
      call add(l:lines, {'text': l:b})
    else
      if l:first == 0 | let l:first = l:n | endif
      call add(l:lines, {'text': l:b, 'props': l:props})
    endif
  endfor
  call popup_settext(s:rlp_pvwin, l:lines)
  " ヒット行の少し上から見せる（文脈が要るので 2 行手前）
  call popup_setoptions(s:rlp_pvwin,
        \ {'firstline': l:first > 0 ? max([l:first - 2, 1]) : 1})
endfunction

" プレビュー内のヒット強調用。reverse なので配色を問わず必ず見える。
function! s:rlp_ensure_hl() abort
  highlight default YuriiNavMatch term=reverse cterm=reverse gui=reverse
  if empty(prop_type_get('yuriiNavMatch'))
    call prop_type_add('yuriiNavMatch',
          \ {'highlight': 'YuriiNavMatch', 'combine': v:true})
  endif
endfunction

" 1 行の中の検索語一致に付ける text-property のリスト
function! s:rlp_hit_props(text) abort
  let l:props = []
  if empty(a:text) | return l:props | endif
  let l:hay = tolower(a:text)
  for l:t in s:rlp_terms
    if empty(l:t) | continue | endif
    let l:len = strlen(l:t)
    let l:start = 0
    while 1
      let l:i = stridx(l:hay, l:t, l:start)
      if l:i < 0 | break | endif
      call add(l:props, {'col': l:i + 1, 'length': l:len, 'type': 'yuriiNavMatch'})
      let l:start = l:i + l:len
    endwhile
  endfor
  return l:props
endfunction

" --- キー -------------------------------------------------------------------

" 打鍵がクエリに行くか（＝グローバル、またはローカルの一時絞り込み中）
" 打鍵がクエリに行く状態か
function! s:rlp_typing() abort
  return s:rlp_input
endfunction

" c/p/y/m の共通処理。記号からも英字からも呼ばれる。
function! s:rlp_op(op) abort
  if a:op ==# 'child'
    call popup_close(s:rlp_win, {'link': 1, 'below': 1, 'targets': s:rlp_targets()})
  elseif a:op ==# 'parent'
    call popup_close(s:rlp_win, {'link': 1, 'below': 0, 'targets': s:rlp_targets()})
  elseif a:op ==# 'yank'
    call popup_close(s:rlp_win, {'yank': s:rlp_targets()})
  elseif a:op ==# 'mark'
    call s:rlp_toggle_mark()
    call s:rlp_render()
  endif
endfunction

" =============================================================================
" キー
"
"   状態は 1 つだけ: 打つ（入力） / 打たない（コマンド）。
"     ⏎ で入力を終える → コマンド
"     i で入力に戻る（/ はクエリを消して入力）
"   コマンド状態のキーは **ローカルでもグローバルでも完全に同じ**。
"   スコープ（ローカル / グローバル）は候補が何かの違いでしかない。
" =============================================================================
function! s:rlp_key(winid, key) abort
  " --- 状態に関係なく同じ意味（特殊キー・矢印・⇥） ---
  if a:key ==# "\<Tab>"
    call s:rlp_switch_scope()
    return 1
  elseif a:key ==# "\<Down>"
    call s:rlp_step_sel(1)  | call s:rlp_render() | return 1
  elseif a:key ==# "\<Up>"
    call s:rlp_step_sel(-1) | call s:rlp_render() | return 1
  elseif a:key ==# "\<Right>"
    call s:rlp_dive(s:rlp_sel) | return 1
  elseif a:key ==# "\<Left>"
    call s:rlp_back() | return 1
  elseif a:key ==# "\<PageDown>"
    if s:rlp_pvwin >= 0 | call win_execute(s:rlp_pvwin, "normal! \<C-f>") | endif
    return 1
  elseif a:key ==# "\<PageUp>"
    if s:rlp_pvwin >= 0 | call win_execute(s:rlp_pvwin, "normal! \<C-b>") | endif
    return 1
  endif

  " ===== 入力状態: 打つとクエリ =====
  if s:rlp_input
    if a:key ==# "\<CR>"
      " 入力終了 → コマンド状態（ここからラベル1タップで潜れる）
      let s:rlp_input = 0
    elseif a:key ==# "\<Esc>" || a:key ==# "\<C-c>"
      " クエリを捨てて入力終了。空で押したら閉じる
      if empty(s:rlp_query)
        call popup_close(s:rlp_win, {'cancel': 1})
        return 1
      endif
      let s:rlp_query = ''
      let s:rlp_input = 0
      call s:rlp_refresh()
      let s:rlp_sel = max([s:rlp_first_sel(), 0])
    elseif a:key ==# "\<BS>" || a:key ==# "\<C-h>"
      if empty(s:rlp_query)
        call s:rlp_back()
        return 1
      endif
      let s:rlp_query = strcharpart(s:rlp_query, 0,
            \ max([strchars(s:rlp_query) - 1, 0]))
      call s:rlp_refresh()
      let s:rlp_sel = max([s:rlp_first_sel(), 0])
    elseif a:key =~# '^.$' && a:key !~# '^[[:cntrl:]]$'
      let s:rlp_query .= a:key
      call s:rlp_refresh()
      let s:rlp_sel = max([s:rlp_first_sel(), 0])
      let s:rlp_top = 0
    endif
    call s:rlp_render()
    return 1
  endif

  " ===== コマンド状態: 打たない。ローカル / グローバルで同じキー =====
  " 記号は入力中はクエリ文字として打てるので、コマンドとして効くのはここだけ。
  if a:key ==# '+'
    call s:rlp_op('child')  | return 1
  elseif a:key ==# '-'
    call s:rlp_op('parent') | return 1
  elseif a:key ==# '*'
    call s:rlp_op('mark')   | return 1
  elseif a:key ==# '='
    call s:rlp_op('yank')   | return 1
  elseif a:key ==# "\<Esc>" || a:key ==# "\<C-c>"
    call popup_close(s:rlp_win, {'cancel': 1})
    return 1
  elseif a:key ==# "\<CR>"
    call popup_close(s:rlp_win, {'open': s:rlp_sel})
    return 1
  elseif a:key ==# "\<BS>" || a:key ==# "\<C-h>" || a:key ==# 'h' || a:key ==# 'q'
    call s:rlp_back()
    return 1
  elseif a:key ==# ' '
    call popup_close(s:rlp_win, {'open_anchor': 1})
    return 1
  elseif a:key ==# 'l'
    call s:rlp_dive(s:rlp_sel)
    return 1
  elseif a:key ==# 'i'
    " クエリを残したまま入力へ戻る
    let s:rlp_input = 1
  elseif a:key ==# '/'
    " クエリを消して入力へ
    let s:rlp_input = 1
    let s:rlp_query = ''
    call s:rlp_refresh()
    let s:rlp_sel = max([s:rlp_first_sel(), 0])
  elseif a:key ==# 'j'
    call s:rlp_step_sel(1)
  elseif a:key ==# 'k'
    call s:rlp_step_sel(-1)
  elseif a:key ==# 'g'
    let s:rlp_sel = max([s:rlp_first_sel(), 0])
  elseif a:key ==# 'G'
    let s:rlp_sel = max([s:rlp_last_sel(), 0])
  elseif a:key ==# 'f'
    if s:rlp_pvwin >= 0 | call win_execute(s:rlp_pvwin, "normal! \<C-f>") | endif
    return 1
  elseif a:key ==# 'b'
    if s:rlp_pvwin >= 0 | call win_execute(s:rlp_pvwin, "normal! \<C-b>") | endif
    return 1
  elseif a:key ==# 'c'
    call s:rlp_op('child')  | return 1
  elseif a:key ==# 'p'
    call s:rlp_op('parent') | return 1
  elseif a:key ==# 'y'
    call s:rlp_op('yank')   | return 1
  elseif a:key ==# 'm'
    call s:rlp_op('mark')   | return 1
  elseif a:key ==# 'M'
    let s:rlp_marks = {}
  elseif a:key ==# 'a'
    call s:rlp_dive(s:rlp_sel)
    return 1
  elseif has_key(s:rlp_rowmap, a:key)
    if s:rlp_scope ==# 'global'
      " 検索結果ではラベルは「移動だけ」。7 番を見たいのに ↓ を 7 回は野暮なので
      " 1 打で飛び、プレビューで中身を見てから ⏎ 開く / l 潜る を選ぶ。
      let s:rlp_sel = s:rlp_rowmap[a:key]
    else
      " ローカルは相手が既に分かっているので1タップでそのまま潜る。
      " 潜ってもアンカー行 ◎ とプレビューに出続け ⌫ で即戻れる（＝非破壊）。
      call s:rlp_dive(s:rlp_rowmap[a:key])
      return 1
    endif
  else
    return 1
  endif
  call s:rlp_render()
  return 1
endfunction

" ⇥ … スコープを切り替える（候補が何かだけが変わる）
"   ローカル → グローバル（全ノートを空クエリ・入力状態で）
"   グローバル → ローカル（選択中のノートへ潜る＝そこが新しいアンカー）
function! s:rlp_switch_scope() abort
  if s:rlp_scope ==# 'local'
    if empty(s:rlp_cands) | call s:rlp_build_index() | endif
    let s:rlp_scope = 'global'
    let s:rlp_input = 1
    let s:rlp_query = ''
    let s:rlp_sel = 0
    let s:rlp_top = 0
    call s:rlp_refresh()
    let s:rlp_sel = max([s:rlp_first_sel(), 0])
    call s:rlp_render()
    return
  endif
  if s:rlp_is_sel(s:rlp_sel)
    call s:rlp_dive(s:rlp_sel)
    return
  endif
  let s:rlp_scope = 'local'
  let s:rlp_input = 0
  let s:rlp_query = ''
  call s:rlp_refresh()
  let s:rlp_sel = max([s:rlp_first_sel(), 0])
  call s:rlp_render()
endfunction

" --- 確定後の処理 -----------------------------------------------------------

" アンカーノートへ関係付きリンクを足す。アンカーが別バッファなら一時的に切り替える。
function! s:rlp_link_apply(targets, below, ...) abort
  let l:anchor = s:rlp_path
  if empty(l:anchor) || !filereadable(l:anchor)
    echohl WarningMsg | echo 'yurii_PKM: アンカーが不正' | echohl NONE
    return
  endif
  if empty(a:targets)
    echo 'yurii_PKM: 対象なし'
    return
  endif
  let l:rel = (a:0 > 0 && a:1 !=# '') ? a:1 : s:v2_pick_relation()
  if empty(l:rel) | echo 'yurii_PKM: キャンセル' | return | endif
  let l:side = s:v2_relation_side(l:rel)
  let l:below = l:side >= 0 ? l:side : a:below

  let l:cur_buf = bufnr('%')
  let l:view = winsaveview()
  let l:same = fnamemodify(expand('%:p'), ':p') ==# fnamemodify(l:anchor, ':p')
  if !l:same
    execute 'silent keepalt hide edit ' . fnameescape(l:anchor)
  endif

  let l:dir = expand('%:p:h')
  let l:n = 0
  let l:save_ai = &autoindent | let l:save_si = &smartindent
  setlocal noautoindent nosmartindent
  for l:t in a:targets
    if fnamemodify(l:t, ':p') ==# fnamemodify(l:anchor, ':p') | continue | endif
    let l:title = s:get_title(l:t)
    if s:v2_insert_link(l:rel, s:make_link_from_dir(l:t, l:title, l:dir), l:below)
      let l:n += 1
    endif
  endfor
  let &autoindent = l:save_ai | let &smartindent = l:save_si
  if l:n > 0 | silent! write | endif

  if !l:same
    execute 'silent keepalt hide buffer ' . l:cur_buf
    call winrestview(l:view)
  endif
  let s:rlp_marks = {}
  echo printf('yurii_PKM: %s %s %s += %d 件',
        \ fnamemodify(l:anchor, ':t'), l:rel, l:below ? '↓そっちにとって' : '↑こっちにとって', l:n)
endfunction

function! s:rlp_open_path(path, ...) abort
  let l:it = a:0 > 0 ? a:1 : {}
  if empty(a:path) || (!filereadable(a:path) && !isdirectory(a:path))
    echo 'yurii_PKM: 開けない: ' . a:path
    return
  endif
  call yurii_pkm#push_history()
  silent! execute 'hide edit ' . fnameescape(a:path)
  if !empty(l:it) && get(l:it, 'kind', '') ==# 'link'
        \ && (l:it.side ==# 'up' || l:it.side ==# 'down')
    let l:rp = s:find_reciprocal_link_pos(a:path, fnamemodify(s:rlp_path, ':t'))
    if get(l:rp, 0, 0) > 0
      call cursor(l:rp[0], l:rp[1])
      normal! zv
    endif
  endif
endfunction

function! s:rlp_done(winid, result) abort
  let s:rlp_win = -1
  if s:rlp_pvwin >= 0
    call popup_close(s:rlp_pvwin)
    let s:rlp_pvwin = -1
  endif
  if type(a:result) != v:t_dict | return | endif

  " y … リンク記法でヤンク
  if has_key(a:result, 'yank')
    let l:links = []
    for l:t in a:result.yank
      call add(l:links, s:make_link_from_dir(l:t, s:get_title(l:t), expand('%:p:h')))
    endfor
    if empty(l:links) | echo 'yurii_PKM: 対象なし' | return | endif
    let l:txt = join(l:links, "\n")
    let @" = l:txt
    if has('clipboard') | let @+ = l:txt | endif
    let s:rlp_marks = {}
    echo 'yurii_PKM: ヤンク ' . len(l:links) . ' 件'
    return
  endif

  " c / p … アンカーへ関係付きリンクを追加
  if has_key(a:result, 'link')
    call s:rlp_link_apply(get(a:result, 'targets', []), get(a:result, 'below', 1))
    return
  endif

  " ␣ … アンカーノート自体を開く
  if has_key(a:result, 'open_anchor')
    if empty(s:rlp_path) || s:rlp_path ==# get(s:rlp_origin, 'path', '') | return | endif
    call s:rlp_open_path(s:rlp_path)
    return
  endif

  " ⏎ … 選択行を開く
  if !has_key(a:result, 'open') | return | endif
  let l:idx = a:result.open
  let l:it = s:rlp_is_sel(l:idx) ? s:rlp_items[l:idx] : {}
  if empty(l:it)
    if s:rlp_path !=# get(s:rlp_origin, 'path', '')
      call s:rlp_open_path(s:rlp_path)
    endif
    return
  endif
  if get(l:it, 'kind', '') ==# 'anchor'
    if s:rlp_path ==# get(s:rlp_origin, 'path', '') | return | endif
    call s:rlp_open_path(s:rlp_path)
    return
  endif
  call s:rlp_open_path(s:rlp_row_path(l:it), l:it)
endfunction

" --- 入口 -------------------------------------------------------------------

" <Space> … 文中 / こっちにとって / そっちにとって ＋ 全ノート検索のナビゲータ。
"   jk/ラベル 選択  l 潜る  h 戻る  ⏎ 開く  ␣ アンカーを開く  fb プレビュー
"   c/p 子/親に追加  y ヤンク  m マーク  a アンカー移動  i 絞込  ⇥ local⇄global
function! yurii_pkm#relation_link_popup() abort
  call yurii_pkm#note_navigator('local')
endfunction

" gs … 同じナビゲータを global スコープ（全ノート検索）で開く
function! yurii_pkm#note_search() abort
  call yurii_pkm#note_navigator('global')
endfunction

" a:scope … 'local'（今のノートのリンク） / 'global'（全ノート検索）
function! yurii_pkm#note_navigator(scope) abort
  let l:origin_path = expand('%:p')
  let l:is_note = !empty(l:origin_path) && s:is_markdown_file(l:origin_path)
  let l:groups0 = l:is_note
        \ ? s:space_collect(getline(1, '$'), expand('%:p:h')) : {}
  if a:scope ==# 'local'
    if empty(get(l:groups0, 'body', [])) && empty(get(l:groups0, 'up', []))
          \ && empty(get(l:groups0, 'down', []))
      call yurii_pkm#jump_relation_link(1)
      return
    endif
  endif

  let s:rlp_origin = {'bufnr': bufnr('%'), 'pos': getpos('.'), 'path': l:origin_path}
  let s:rlp_stack = []
  let s:rlp_crumbs = [fnamemodify(l:origin_path, ':t:r')]
  let s:rlp_scope = 'local'
  let s:rlp_input = 0
  let s:rlp_query = ''
  let s:rlp_terms = []
  let s:rlp_cands = []
  let s:rlp_path = l:origin_path
  let s:rlp_base = expand('%:p:h')
  let s:rlp_groups = l:groups0
  let s:rlp_want_cursor_init = 1
  call s:rlp_refresh()

  let l:geo = s:rlp_geometry()
  let s:rlp_geo = l:geo
  let s:rlp_rows = l:geo.rows

  let s:rlp_win = popup_create([], {
        \ 'title': ' ローカル ',
        \ 'line': l:geo.list_line, 'col': l:geo.list_col,
        \ 'minwidth': l:geo.list_w, 'maxwidth': l:geo.list_w,
        \ 'minheight': l:geo.h, 'maxheight': l:geo.h,
        \ 'zindex': 300,
        \ 'border': [], 'borderchars': ['─','│','─','│','╭','╮','╯','╰'],
        \ 'borderhighlight': ['Comment'], 'padding': [0,1,0,1],
        \ 'mapping': 0,
        \ 'filter': function('s:rlp_key'), 'callback': function('s:rlp_done'),
        \ })
  let s:rlp_pvwin = popup_create([], {
        \ 'title': ' プレビュー ',
        \ 'line': l:geo.pv_line, 'col': l:geo.pv_col,
        \ 'minwidth': l:geo.pv_w, 'maxwidth': l:geo.pv_w,
        \ 'minheight': l:geo.h, 'maxheight': l:geo.h,
        \ 'zindex': 299,
        \ 'border': [], 'borderchars': ['─','│','─','│','╭','╮','╯','╰'],
        \ 'borderhighlight': ['Comment'], 'padding': [0,1,0,1],
        \ })
  call s:rlp_load(l:origin_path, expand('%:p:h'))
  if a:scope ==# 'global'
    " gs 相当。索引を読んで、打てる状態（入力）から始める
    if empty(s:rlp_cands) | call s:rlp_build_index() | endif
    let s:rlp_scope = 'global'
    let s:rlp_input = 1
    let s:rlp_query = ''
    let s:rlp_sel = 0
    let s:rlp_top = 0
    call s:rlp_refresh()
    let s:rlp_sel = max([s:rlp_first_sel(), 0])
    call s:rlp_render()
  endif
endfunction

" ---------------------------------------------------------------------------
" リンクへのラベルジャンプ（本文 → Parent/Child の通し番号）
"   1-9,0    … その番号のリンクを直接開く（生の数字キー、0は10番目）
"   文字+数字 … 11番目以降（z1, z2, …, z9, z0, t1, … の2打、1→0順）
" 実際に見えている番号・ラベルがリンクの手前に仮想テキストで表示されるので、
" 数えなくても押すキーが分かる（g:yurii_pkm_link_hints=0 で無効化）。
" 11番目以降の文字は、このプラグインがすでに2打コマンドの頭文字として
" 使っている文字だけを使う（z, t, c, b, m, p, y ─ zc/zp/ta/tt/cu/ca/
" bu/bc/mp/mx/pe/yn 等）。n は検索リピート（n/N）に使うので外してある。
" これらの生キーはすでに「次の1打を待つ」状態になっているので、数字を
" 後ろに続けても新たな干渉や体感速度の悪化は発生しない。a, i, o, … など
" 他の生キーには一切手を出さない。
" ---------------------------------------------------------------------------

let s:hint_prop_type = 'yuriiLinkHint'
let s:hint_label_letters = 'ztcbmpy'

" 通し番号(1始まり)からラベル文字列を作る。1-9,0はそのまま（0は10番目）、
" 以降は文字+数字（z1, z2, …, z9, z0, t1, …、キー配列と同じ 1→0 順で
" 10個ずつ）。生の 0 キーは vim 標準の「行頭へ移動」を上書きするが、
" 該当リンクが無ければ digit_key() 側で通常の 0 に素通しされる。
" 割り当て切れ（7文字×10 を超える）なら空文字。
function! s:hint_label(idx) abort
  if a:idx <= 9 | return string(a:idx) | endif
  if a:idx == 10 | return '0' | endif
  let l:n = a:idx - 11
  let l:letter_i = l:n / 10
  let l:pos_in_group = l:n % 10
  let l:digit = (l:pos_in_group == 9) ? 0 : l:pos_in_group + 1
  if l:letter_i >= strlen(s:hint_label_letters) | return '' | endif
  return s:hint_label_letters[l:letter_i] . l:digit
endfunction

" 現在バッファの候補位置（本文 → Parent/Child の順、digit_key と同じ並び）。
function! s:hint_positions() abort
  return s:v2_body_link_positions() + s:v2_relation_link_positions()
endfunction

" ラベル→位置の対応表を作る。割り当て切れの位置は含めない。
function! s:hint_build_map() abort
  let l:map = {}
  let l:idx = 0
  for l:p in s:hint_positions()
    let l:idx += 1
    let l:label = s:hint_label(l:idx)
    if empty(l:label) | break | endif
    let l:map[l:label] = l:p
  endfor
  return l:map
endfunction

function! s:hint_ensure_prop_type() abort
  if !has('textprop') | return 0 | endif
  highlight default link YuriiLinkHint Special
  if empty(prop_type_get(s:hint_prop_type))
    call prop_type_add(s:hint_prop_type, {'highlight': 'YuriiLinkHint'})
  endif
  return 1
endfunction

" ラベル位置へ移動してそのままリンクを開く（Enter を省く）。
function! s:hint_go(pos) abort
  normal! m'
  call cursor(a:pos.lnum, a:pos.col)
  normal! zv
  call yurii_pkm#open_link_under_cursor()
endfunction

" 使わなくなった2文字ラベルの一時マッピングを外し、新しく必要な分を張る。
" 対象は10番目以降の文字+数字ラベルのみ（例: z3, c7）。頭文字は
" z/t/c/b/m/p/y に限定しており、このプラグインの既存2打コマンド
" （zc, ta, cu, bu, mp, pe, yn 等）と完全一致することはない
" （2文字目が数字 vs 既存は文字なので重複しない）。
function! s:hint_sync_full_maps(labels) abort
  let l:have = get(b:, 'yurii_hint_full_labels', [])
  for l:label in l:have
    if index(a:labels, l:label) < 0
      silent! execute 'nunmap <buffer> ' . l:label
    endif
  endfor
  for l:label in a:labels
    if index(l:have, l:label) < 0
      execute printf('nnoremap <silent><buffer> %s <Cmd>call yurii_pkm#hint_goto(%s)<CR>', l:label, string(l:label))
    endif
  endfor
  let b:yurii_hint_full_labels = a:labels
endfunction

" 本文・Parent/Child のリンク手前に、ラベル（1-9 / 文字+数字）を仮想テキストで表示する。
function! yurii_pkm#refresh_link_hints() abort
  if !get(g:, 'yurii_pkm_link_hints', 1) || !has('textprop') | return | endif
  if &l:filetype !=# 'markdown' && &l:filetype !=# 'vimwiki' | return | endif
  if !s:hint_ensure_prop_type() | return | endif
  call prop_remove({'type': s:hint_prop_type, 'all': v:true})
  let b:yurii_hint_map = s:hint_build_map()
  if empty(b:yurii_hint_map)
    call s:hint_sync_full_maps([])
    return
  endif
  let l:full_labels = []
  for [l:label, l:pos] in items(b:yurii_hint_map)
    call prop_add(l:pos.lnum, l:pos.col, {'type': s:hint_prop_type, 'text': l:label})
    if strchars(l:label) > 1 | call add(l:full_labels, l:label) | endif
  endfor
  call s:hint_sync_full_maps(l:full_labels)
endfunction

" 数字キー（生の 1-9,0）… 本文 → Parent/Child の順で通し番号にした N 番目の
" リンクを直接開く（0は10番目）。該当が無ければ通常のカウント/行頭移動として送る。
function! yurii_pkm#digit_key(idx, key) abort
  let l:pos = s:hint_positions()
  if !empty(l:pos) && a:idx >= 1 && a:idx <= len(l:pos)
    call s:hint_go(l:pos[a:idx - 1])
    return
  endif
  call feedkeys((v:count > 0 ? v:count : '') . a:key, 'n')
endfunction

" 文字+数字（11番目以降のラベル）… 対応する位置を開く。
function! yurii_pkm#hint_goto(label) abort
  let l:pos = get(b:, 'yurii_hint_map', {})
  if has_key(l:pos, a:label)
    call s:hint_go(l:pos[a:label])
  endif
endfunction

function! yurii_pkm#get_link_under_cursor() abort
  let l:line   = getline('.')
  let l:cursor = col('.') - 1
  let l:start  = 0
  while 1
    let l:m = matchstrpos(l:line, s:link_pat, l:start)
    if len(l:m) < 3 || l:m[1] < 0
      return {}
    endif
    if l:cursor >= l:m[1] && l:cursor < l:m[2]
      let l:parts = matchlist(l:m[0], '\v\[([^\]]+)\]\(([^)]*)\)')
      return {
            \ 'raw':      l:m[0],
            \ 'text':     get(l:parts, 1, ''),
            \ 'target':   get(l:parts, 2, ''),
            \ 'startcol': l:m[1] + 1,
            \ 'endcol':   l:m[2]
            \ }
    endif
    " カーソルがリンクより後ろかチェック
    " [xxx](yyy) の形式で、リンク終端の直後にいる場合
    if l:cursor >= l:m[2]
      let l:after = strpart(l:line, l:m[2])
      " 直後がスペース2つ以上 + テキスト の形式
      if l:after =~# '^\s\{2,}\S'
        " 次のリンクが始まる前の範囲内にカーソルがあるか確認
        let l:next = matchstrpos(l:line, s:link_pat, l:m[2])
        let l:title_end = (len(l:next) >= 3 && l:next[1] >= 0) ? l:next[1] : len(l:line)
        if l:cursor < l:title_end
          let l:parts = matchlist(l:m[0], '\v\[([^\]]+)\]\(([^)]*)\)')
          return {
                \ 'raw':      l:m[0],
                \ 'text':     get(l:parts, 1, ''),
                \ 'target':   get(l:parts, 2, ''),
                \ 'startcol': l:m[1] + 1,
                \ 'endcol':   l:title_end
                \ }
        endif
      endif
    endif
    let l:start = l:m[2]
  endwhile
endfunction

function! s:is_absolute_path(path) abort
  let l:path = trim(a:path)
  return l:path =~# '^/' || l:path =~# '^\\' || l:path =~# '^\a\+:' || l:path =~# '^\~[\\/]'
endfunction

function! s:expand_user_path(path) abort
  let l:path = trim(a:path)
  if l:path =~# '^\~[\\/]'
    return fnamemodify(expand(l:path), ':p')
  endif
  return l:path
endfunction

function! s:path_has_directory(target) abort
  return a:target =~# '[\\/]'
endfunction

function! s:markdown_relative_target(relpath) abort
  let l:rel = substitute(a:relpath, '\\', '/', 'g')
  if empty(l:rel)
    return l:rel
  endif
  " Links to files in child directories should be explicit Markdown relative
  " links from the current note directory, e.g. ./2026-03-26/260616161959.md.
  if l:rel !~# '^\.\.\?/' && l:rel =~# '/'
    return './' . l:rel
  endif
  return l:rel
endfunction

function! s:relpath_from_dir(path, base) abort
  let l:path = fnamemodify(a:path, ':p')
  let l:base = fnamemodify(a:base, ':p')
  let l:path_dir = fnamemodify(l:path, ':h:p')
  let l:path_dir_cmp = substitute(l:path_dir, '[\\/]\+$', '', '')
  let l:base_cmp = substitute(l:base, '[\\/]\+$', '', '')

  " Same-directory links must stay as plain filenames.  In particular, notes
  " created from index.md should get [Index](index.md), never [Index](/index.md).
  if l:path_dir_cmp ==# l:base_cmp
    return fnamemodify(l:path, ':t')
  endif

  let l:path_norm = substitute(l:path, '\\', '/', 'g')
  let l:base_norm = substitute(l:base, '\\', '/', 'g')
  let l:path_parts = split(l:path_norm, '/')
  let l:base_parts = split(l:base_norm, '/')

  while !empty(l:path_parts) && !empty(l:base_parts) && l:path_parts[0] ==# l:base_parts[0]
    call remove(l:path_parts, 0)
    call remove(l:base_parts, 0)
  endwhile

  let l:rel_parts = repeat(['..'], len(l:base_parts)) + l:path_parts
  if empty(l:rel_parts)
    return fnamemodify(l:path, ':t')
  endif
  let l:rel = join(l:rel_parts, '/')
  return empty(l:rel) ? fnamemodify(l:path, ':t') : s:markdown_relative_target(l:rel)
endfunction

function! s:ancestor_dirs_until_root(base) abort
  let l:dirs = []
  let l:root = s:get_pkm_root()
  let l:root = empty(l:root) ? '' : fnamemodify(l:root, ':p')
  let l:dir = fnamemodify(a:base, ':p')

  while !empty(l:dir)
    call add(l:dirs, l:dir)
    if !empty(l:root) && l:dir ==# l:root
      break
    endif
    let l:parent = fnamemodify(l:dir, ':h:p')
    if l:parent ==# l:dir
      break
    endif
    let l:dir = l:parent
  endwhile
  return l:dirs
endfunction

function! s:find_unique_file_near_current_tree(base, name) abort
  let l:root = s:get_pkm_root()
  let l:search_base = !empty(l:root) ? fnamemodify(l:root, ':p') : fnamemodify(a:base, ':p')
  let l:cache_key = fnamemodify(a:base, ':p') . '|' . l:search_base . '|' . a:name
  if has_key(s:filename_resolve_cache, l:cache_key)
    let l:cached = s:filename_resolve_cache[l:cache_key]
    return empty(l:cached) || filereadable(l:cached) ? l:cached : ''
  endif

  let l:files = []
  let l:seen = {}

  for l:dir in s:ancestor_dirs_until_root(a:base)
    let l:candidate = fnamemodify(l:dir . '/' . a:name, ':p')
    if filereadable(l:candidate) && !has_key(l:seen, l:candidate)
      let l:seen[l:candidate] = 1
      call add(l:files, l:candidate)
    endif
  endfor
  if len(l:files) == 1
    let s:filename_resolve_cache[l:cache_key] = l:files[0]
    return l:files[0]
  elseif len(l:files) > 1
    let s:filename_resolve_cache[l:cache_key] = ''
    return ''
  endif

  for l:m in globpath(l:search_base, '**/' . a:name, 0, 1)
    let l:path = fnamemodify(l:m, ':p')
    if has_key(l:seen, l:path)
      continue
    endif
    let l:seen[l:path] = 1
    if filereadable(l:path) && index(split(l:path, '[\\/]'), '.undo') < 0 && fnamemodify(l:path, ':t') ==# a:name
      call add(l:files, l:path)
    endif
  endfor

  let l:resolved = len(l:files) == 1 ? l:files[0] : ''
  let s:filename_resolve_cache[l:cache_key] = l:resolved
  return l:resolved
endfunction

function! s:resolve_existing_link_target(target, ...) abort
  let l:base = a:0 ? a:1 : expand('%:p:h')
  let l:target = s:expand_user_path(a:target)
  if empty(l:target) || l:target =~# '\v^\w+://'
    return ''
  endif
  if s:is_absolute_path(l:target)
    let l:absolute = fnamemodify(l:target, ':p')
    return filereadable(l:absolute) ? l:absolute : ''
  endif

  let l:direct = fnamemodify(l:base . '/' . l:target, ':p')
  if filereadable(l:direct)
    return l:direct
  endif

  if !s:path_has_directory(l:target)
    return s:find_unique_file_near_current_tree(l:base, l:target)
  endif

  " Directory-bearing links copied from another note are often relative to
  " the PKM root/current working directory (for example ./N_root.md or
  " folder/N_child.md).  If they do not exist relative to the destination
  " note, resolve them from the root so link insertion can rebase them to
  " ../... for notes inside subdirectories.
  let l:root = s:get_pkm_root()
  if !empty(l:root)
    let l:root_candidate = fnamemodify(l:root . '/' . l:target, ':p')
    if filereadable(l:root_candidate)
      return l:root_candidate
    endif
  endif

  let l:cwd_candidate = fnamemodify(getcwd() . '/' . l:target, ':p')
  if filereadable(l:cwd_candidate)
    return l:cwd_candidate
  endif

  return ''
endfunction

function! s:display_target_from_current_dir(target) abort
  let l:base = expand('%:p:h')
  let l:path = s:resolve_existing_link_target(a:target, l:base)
  if !empty(l:path)
    return s:relpath_from_dir(l:path, l:base)
  endif
  return substitute(s:expand_user_path(a:target), '\\', '/', 'g')
endfunction

function! yurii_pkm#resolve_link(target, ...) abort
  let l:base = a:0 ? a:1 : expand('%:p:h')
  let l:existing = s:resolve_existing_link_target(a:target, l:base)
  if !empty(l:existing)
    return l:existing
  endif
  let l:target = s:expand_user_path(a:target)
  if s:is_absolute_path(l:target)
    return fnamemodify(l:target, ':p')
  endif
  return fnamemodify(l:base . '/' . l:target, ':p')
endfunction

function! s:resolve_link_for_navigation(target, ...) abort
  let l:base = a:0 ? a:1 : expand('%:p:h')
  let l:target = s:expand_user_path(a:target)
  if empty(l:target) || l:target =~# '\v^\w+://'
    return ''
  endif
  if s:is_absolute_path(l:target)
    return fnamemodify(l:target, ':p')
  endif

  let l:direct = fnamemodify(l:base . '/' . l:target, ':p')
  if filereadable(l:direct) || isdirectory(l:direct)
    return l:direct
  endif

  if s:path_has_directory(l:target)
    let l:root = s:get_pkm_root()
    if !empty(l:root)
      let l:root_candidate = fnamemodify(l:root . '/' . l:target, ':p')
      if filereadable(l:root_candidate) || isdirectory(l:root_candidate)
        return l:root_candidate
      endif
    endif

    let l:cwd_candidate = fnamemodify(getcwd() . '/' . l:target, ':p')
    if filereadable(l:cwd_candidate) || isdirectory(l:cwd_candidate)
      return l:cwd_candidate
    endif
  elseif get(g:, 'yurii_pkm_global_bare_link_navigation', 0)
    let l:global = s:find_unique_file_near_current_tree(l:base, l:target)
    if !empty(l:global)
      return l:global
    endif
  endif

  return l:direct
endfunction

function! s:clipboard_text() abort
  let l:cb = @+
  if empty(l:cb)
    let l:cb = @"
  endif
  return trim(l:cb)
endfunction

function! s:extract_markdown_link(raw) abort
  let l:raw = trim(a:raw)
  if empty(l:raw)
    return {'text': '', 'target': ''}
  endif
  let l:m = matchlist(l:raw, '^\[\([^]]*\)\](\([^)]\+\))')
  if !empty(l:m)
    return {'text': l:m[1], 'target': trim(l:m[2])}
  endif
  return {'text': '', 'target': ''}
endfunction

function! s:extract_target(raw) abort
  let l:raw = trim(a:raw)
  if empty(l:raw)
    return ''
  endif
  let l:link = s:extract_markdown_link(l:raw)
  if !empty(l:link.target)
    return l:link.target
  endif
  return l:raw
endfunction

function! s:extract_targets_from_clipboard(text) abort
  let l:targets = []
  let l:seen = {}

  if empty(trim(a:text))
    return l:targets
  endif

  " まず Markdown リンクを全文から全部拾う
  let l:start = 0
  while 1
    let l:m = matchstrpos(a:text, '\v\[[^\]]+\]\(([^)]*)\)', l:start)
    if empty(l:m) || l:m[1] < 0
      break
    endif
    let l:raw = get(l:m, 0, '')
    let l:target = s:extract_target(l:raw)
    if !empty(l:target) && !has_key(l:seen, l:target)
      let l:seen[l:target] = 1
      call add(l:targets, l:target)
    endif
    let l:start = l:m[2]
  endwhile

  " Markdown リンクが無ければ、各行をそのままターゲットとして扱う
  if empty(l:targets)
    for l:raw in split(a:text, "\n")
      let l:target = s:extract_target(l:raw)
      if !empty(l:target) && !has_key(l:seen, l:target)
        let l:seen[l:target] = 1
        call add(l:targets, l:target)
      endif
    endfor
  endif

  return l:targets
endfunction

function! s:is_filename_target(target) abort
  let l:t = trim(a:target)
  if empty(l:t)
    return 0
  endif
  if l:t =~# '\v^\w\+://'
    return 0
  endif
  return l:t =~# '\v(^|[\\/])[^\\/]+\.[A-Za-z0-9_-]+$'
endfunction

function! s:existing_title_for_target(target) abort
  let l:path = yurii_pkm#resolve_link(a:target)
  if filereadable(l:path) && s:is_markdown_target(a:target)
    return s:get_title(l:path)
  endif
  return ''
endfunction

function! s:link_from_target(target) abort
  let l:target = trim(a:target)
  if empty(l:target)
    return ''
  endif
  let l:display_target = s:display_target_from_current_dir(l:target)
  let l:name = fnamemodify(l:display_target, ':t')
  " md は YAML/H1 タイトルをリンク文字列にする。非mdは拡張子を除いたファイル名
  let l:title = s:existing_title_for_target(l:display_target)
  if s:is_markdown_target(l:display_target)
    let l:text = empty(l:title) ? fnamemodify(l:name, ':r') : l:title
  else
    let l:text = fnamemodify(l:name, ':r')
  endif
  return '[' . l:text . '](' . l:display_target . ')'
endfunction

function! s:link_from_clipboard_raw(raw) abort
  let l:link = s:extract_markdown_link(a:raw)
  if !empty(l:link.target)
    let l:display_target = s:display_target_from_current_dir(l:link.target)
    return '[' . l:link.text . '](' . l:display_target . ')'
  endif
  return s:link_from_target(a:raw)
endfunction

function! s:retitle_markdown_links_in_line(line, base_dir) abort
  let l:line = a:line
  let l:new_line = ''
  let l:last = 0
  let l:start = 0
  let l:changed = 0
  while 1
    let l:m = matchstrpos(l:line, '\v\[[^\]]*\]\(([^)]*)\)', l:start)
    if empty(l:m) || l:m[1] < 0
      break
    endif
    let l:raw = l:m[0]
    let l:parts = matchlist(l:raw, '\v\[([^\]]*)\]\(([^)]*)\)')
    let l:target = get(l:parts, 2, '')
    let l:new_link = l:raw
    if !empty(l:target) && s:is_markdown_target(l:target)
      let l:path = yurii_pkm#resolve_link(l:target, a:base_dir)
      let l:title = s:get_yaml_title(l:path)
      if !empty(l:title)
        let l:new_link = '[' . l:title . '](' . l:target . ')'
        if l:new_link !=# l:raw
          let l:changed = 1
        endif
      endif
    endif
    let l:new_line .= strpart(l:line, l:last, l:m[1] - l:last) . l:new_link
    let l:last = l:m[2]
    let l:start = l:m[2]
  endwhile
  let l:new_line .= strpart(l:line, l:last)
  return {'line': l:changed ? l:new_line : a:line, 'changed': l:changed}
endfunction

function! yurii_pkm#rename_down_links_to_yaml_title(line1, line2, range) range abort
  let l:base = expand('%:p:h')
  if a:range > 0
    let l:start = a:line1
    let l:end = a:line2
  else
    let l:down = s:find_section_line('down')
    if l:down <= 0
      echo 'Error: child section not found'
      return
    endif
    let l:start = l:down + 1
    let l:end = s:down_end_line()
  endif

  if l:start > l:end
    echo 'No links to update'
    return
  endif

  let l:changed = 0
  let l:in_fence = 0
  for l:lnum in range(l:start, l:end)
    let l:line = getline(l:lnum)
    if trim(l:line) =~# '^```'
      let l:in_fence = !l:in_fence
      continue
    endif
    if l:in_fence
      continue
    endif
    let l:result = s:retitle_markdown_links_in_line(l:line, l:base)
    if l:result.changed
      call setline(l:lnum, l:result.line)
      let l:changed += 1
    endif
  endfor

  if l:changed
    silent write
  endif
  echo 'YAML title link text updated ' . l:changed . ' line(s)'
endfunction

function! s:insert_link_below_cursor(link) abort
  if empty(a:link)
    return 0
  endif
  call append(line('.'), a:link)
  return 1
endfunction

function! s:link_already_present_in_branch(link) abort
  let l:down = s:find_section_line('down')
  if l:down <= 0
    let l:down = s:find_section_line('branch')
  endif
  if l:down <= 0
    return 0
  endif
  let l:end = s:down_end_line()
  for l:i in range(l:down + 1, l:end)
    if getline(l:i) ==# a:link
      return 1
    endif
  endfor
  return 0
endfunction

" ---------------------------------------------------------------------------
" History (Back key)
" ---------------------------------------------------------------------------

" --- 履歴 / 直前ノート / ハブ / 最近訪問 --------------------------------------

function! s:hist_state_file(name) abort
  return s:state_dir() . s:sep() . a:name
endfunction

function! s:load_json_state(name, default) abort
  let l:f = s:hist_state_file(a:name)
  if !filereadable(l:f) | return a:default | endif
  try
    return json_decode(join(readfile(l:f), ''))
  catch
    return a:default
  endtry
endfunction

function! s:save_json_state(name, value) abort
  let l:dir = s:state_dir()
  if !isdirectory(l:dir) | call mkdir(l:dir, 'p') | endif
  try
    call writefile([json_encode(a:value)], s:hist_state_file(a:name))
  catch
  endtry
endfunction

" 最近訪問（path -> epoch）。global スコープの無クエリ時の並び順に使う。
function! yurii_pkm#recent_map() abort
  if !exists('g:yurii_pkm_recent')
    let g:yurii_pkm_recent = s:load_json_state('recent.json', {})
  endif
  return g:yurii_pkm_recent
endfunction

function! s:recent_touch(path) abort
  if empty(a:path) || !s:is_markdown_file(a:path) | return | endif
  let l:m = yurii_pkm#recent_map()
  let l:m[fnamemodify(a:path, ':p')] = localtime()
  " 上限を超えたら古いものから捨てる
  let l:cap = get(g:, 'yurii_pkm_recent_max', 500)
  if len(l:m) > l:cap
    let l:pairs = sort(items(l:m), {a, b -> a[1] - b[1]})
    for l:i in range(len(l:pairs) - l:cap)
      call remove(l:m, l:pairs[l:i][0])
    endfor
  endif
  let g:yurii_pkm_recent = l:m
  call s:save_json_state('recent.json', l:m)
endfunction

" ハブ（'1'..'9' -> path）
function! yurii_pkm#hub_map() abort
  if !exists('g:yurii_pkm_hubs')
    let g:yurii_pkm_hubs = s:load_json_state('hubs.json', {})
  endif
  return g:yurii_pkm_hubs
endfunction

" 引数が数値でも文字列でも '1'..'9' の文字列に揃える（string() は引用符を付ける）
function! s:hub_key(v) abort
  return type(a:v) == v:t_number ? printf('%d', a:v) : trim(a:v)
endfunction

function! yurii_pkm#hub_set(...) abort
  let l:n = a:0 > 0 ? s:hub_key(a:1) : ''
  if empty(l:n)
    echo 'ハブ番号 1-9: '
    let l:c = getchar()
    redraw
    let l:n = type(l:c) == v:t_number ? nr2char(l:c) : l:c
  endif
  if l:n !~# '^[1-9]$'
    echo 'yurii_PKM: 1-9 で指定して' | return
  endif
  let l:file = expand('%:p')
  if empty(l:file) || !s:is_markdown_file(l:file)
    echohl WarningMsg | echo 'yurii_PKM: ノート上で実行して' | echohl NONE | return
  endif
  let l:m = yurii_pkm#hub_map()
  let l:m[l:n] = l:file
  let g:yurii_pkm_hubs = l:m
  call s:save_json_state('hubs.json', l:m)
  echo printf('yurii_PKM: ハブ %s = %s', l:n, s:get_title(l:file))
endfunction

function! yurii_pkm#hub_jump(n) abort
  let l:m = yurii_pkm#hub_map()
  let l:p = get(l:m, s:hub_key(a:n), '')
  if empty(l:p) || !filereadable(l:p)
    echo printf('yurii_PKM: ハブ %s は未登録（\H%s で登録）', a:n, a:n)
    return
  endif
  if fnamemodify(expand('%:p'), ':p') ==# fnamemodify(l:p, ':p') | return | endif
  call yurii_pkm#push_history()
  silent! execute 'hide edit ' . fnameescape(l:p)
endfunction

function! yurii_pkm#hub_list() abort
  let l:m = yurii_pkm#hub_map()
  let l:out = []
  for l:n in map(range(1, 9), 'string(v:val)')
    let l:p = get(l:m, l:n, '')
    call add(l:out, printf('%s  %s', l:n,
          \ empty(l:p) ? '(未登録)' : s:get_title(l:p)))
  endfor
  echo join(l:out, "\n")
endfunction

function! yurii_pkm#push_history() abort
  let l:file = yurii_pkm#current_file()
  if empty(l:file) | return | endif
  call add(g:yurii_pkm_history, {'file': l:file, 'pos': getpos('.')})
  if len(g:yurii_pkm_history) > g:yurii_pkm_history_max
    call remove(g:yurii_pkm_history, 0)
  endif
  " 新しい移動が起きたら「進む」履歴は無効になる（ブラウザと同じ）
  let g:yurii_pkm_forward = []
  " 直前ノート（⌥ トグル用）
  let g:yurii_pkm_alt = l:file
  call s:recent_touch(l:file)
endfunction

" 直前に居たノートとの1キー往復。押すたび A→B→A→B。
function! yurii_pkm#toggle_alternate() abort
  let l:cur = expand('%:p')
  let l:alt = get(g:, 'yurii_pkm_alt', '')
  if empty(l:alt) && !empty(get(g:, 'yurii_pkm_history', []))
    let l:alt = g:yurii_pkm_history[-1].file
  endif
  if empty(l:alt) || !filereadable(l:alt)
    echo 'yurii_PKM: 直前のノートがない'
    return
  endif
  if fnamemodify(l:alt, ':p') ==# fnamemodify(l:cur, ':p')
    echo 'yurii_PKM: 直前のノートが自分自身'
    return
  endif
  call add(g:yurii_pkm_history, {'file': l:cur, 'pos': getpos('.')})
  if len(g:yurii_pkm_history) > g:yurii_pkm_history_max
    call remove(g:yurii_pkm_history, 0)
  endif
  let g:yurii_pkm_forward = []
  let g:yurii_pkm_alt = l:cur
  silent! execute 'hide edit ' . fnameescape(l:alt)
  call s:recent_touch(l:alt)
endfunction

" 履歴を前に進む（⌫ の対）。戻るが可逆になる。
function! yurii_pkm#go_forward() abort
  if !exists('g:yurii_pkm_forward') || empty(g:yurii_pkm_forward)
    echo 'yurii_PKM: これ以上進めない'
    return
  endif
  let l:item = remove(g:yurii_pkm_forward, -1)
  if get(g:, 'yurii_pkm_sync_before_link_navigation', 0)
    call s:write_current_and_sync_now()
  elseif get(g:, 'yurii_pkm_save_before_link_navigation', 0) && &modified && &buftype ==# '' && &modifiable
    silent update
  endif
  let l:cur = expand('%:p')
  if !empty(l:cur)
    call add(g:yurii_pkm_history, {'file': l:cur, 'pos': getpos('.')})
    let g:yurii_pkm_alt = l:cur
  endif
  silent! execute 'hide edit ' . fnameescape(l:item.file)
  call setpos('.', l:item.pos)
  call s:snap_cursor_to_link()
  call s:recent_touch(l:item.file)
endfunction

function! yurii_pkm#open_link_under_cursor() abort
  let l:link = yurii_pkm#get_link_under_cursor()
  if empty(l:link) || empty(l:link.target)
    echo 'No link under cursor'
    return
  endif
  let l:path = s:resolve_link_for_navigation(l:link.target)
  if !filereadable(l:path) && !isdirectory(l:path)
    echo 'Link target not found: ' . l:path
    return
  endif
  let l:source_name = expand('%:t')
  let l:from_back = s:in_back_section(line('.'))
  let l:from_up = s:in_up_section(line('.'))
  if get(g:, 'yurii_pkm_sync_before_link_navigation', 0)
    call s:write_current_and_sync_now()
  elseif get(g:, 'yurii_pkm_save_before_link_navigation', 0) && &modified && &buftype ==# '' && &modifiable
    silent update
  endif
  call yurii_pkm#push_history()
  silent! execute 'hide edit ' . fnameescape(l:path)
  if l:from_back || l:from_up
    let l:pos = s:find_reciprocal_link_pos(l:path, l:source_name)
    if get(l:pos, 0, 0) > 0
      call cursor(l:pos[0], l:pos[1])
    endif
  endif
endfunction


function! yurii_pkm#go_back() abort
  if !exists('g:yurii_pkm_history') || empty(g:yurii_pkm_history)
    echo 'History is empty'
    return
  endif
  let l:item = remove(g:yurii_pkm_history, -1)
  if get(g:, 'yurii_pkm_sync_before_link_navigation', 0)
    call s:write_current_and_sync_now()
  elseif get(g:, 'yurii_pkm_save_before_link_navigation', 0) && &modified && &buftype ==# '' && &modifiable
    silent update
  endif
  " 戻る前に「今いる場所」を進む履歴へ積む（戻りを可逆にする）
  let l:cur = expand('%:p')
  if !empty(l:cur)
    if !exists('g:yurii_pkm_forward') | let g:yurii_pkm_forward = [] | endif
    call add(g:yurii_pkm_forward, {'file': l:cur, 'pos': getpos('.')})
    if len(g:yurii_pkm_forward) > g:yurii_pkm_history_max
      call remove(g:yurii_pkm_forward, 0)
    endif
    let g:yurii_pkm_alt = l:cur
  endif
  silent! execute 'hide edit ' . fnameescape(l:item.file)
  call setpos('.', l:item.pos)
  call s:snap_cursor_to_link()
  call s:recent_touch(l:item.file)
endfunction

" 戻った直後、カーソルがリンク上でなければ一番近いリンクへ寄せる。
" （同期で行がずれてもリンクを見失わないように）
function! s:snap_cursor_to_link() abort
  let l:lnum = line('.')
  " まず現在行にリンクがあればその先頭へ
  let l:m = matchstrpos(getline(l:lnum), s:link_pat)
  if l:m[1] >= 0
    call cursor(l:lnum, l:m[1] + 1)
    return
  endif
  " なければ前後 12 行を近い順に探索
  let l:last = line('$')
  for l:d in range(1, 12)
    for l:cand in [l:lnum + l:d, l:lnum - l:d]
      if l:cand < 1 || l:cand > l:last | continue | endif
      let l:mm = matchstrpos(getline(l:cand), s:link_pat)
      if l:mm[1] >= 0
        call cursor(l:cand, l:mm[1] + 1)
        return
      endif
    endfor
  endfor
endfunction

" ---------------------------------------------------------------------------
" Note template
" ---------------------------------------------------------------------------

function! yurii_pkm#timestamp_filename() abort
  return strftime('%y%m%d%H%M%S')
endfunction

function! yurii_pkm#timestamp_yaml() abort
  return strftime('%Y-%m-%d %H:%M:%S')
endfunction

function! s:k_note_template(title) abort
  if s:pkm_format() ==# 'v2'
    return [
          \ '---',
          \ 'time: ' . yurii_pkm#timestamp_yaml(),
          \ 'title: ' . a:title,
          \ '---',
          \ '',
          \ '# ' . a:title,
          \ '',
          \ '',
          \ s:v2_up_mark,
          \ s:v2_down_mark ]
  endif
  return [
        \ '---',
        \ 'time: ' . yurii_pkm#timestamp_yaml(),
        \ 'filetype: K',
        \ 'title: ' . a:title,
        \ '---',
        \ '',
        \ '# ' . a:title,
        \ '',
        \ s:canonical_section_title('up'),
        \ s:canonical_section_title('down'),
        \ s:canonical_section_title('backlink'),
        \ '[Index](index.md)' ]
endfunction

function! s:k_note_template_with_down(title, down_lines) abort
  let l:content = s:k_note_template(a:title)
  let l:down_lines = s:trim_blank_edges(a:down_lines)
  let l:down_lines = filter(copy(l:down_lines), 'v:val !~# ''^\[Index\](index\.md)$''')
  if !empty(l:down_lines)
    let l:down_idx = s:find_section_index_in_lines(l:content, 'down')
    call extend(l:content, l:down_lines, l:down_idx + 1)
  endif
  return l:content
endfunction

function! s:new_note_insert_line() abort
  let l:ctx = search('^Context:', 'nw')
  if l:ctx > 0
    return min([l:ctx + 1, line('$')])
  endif
  let l:max = min([40, line('$')])
  for lnum in range(1, l:max)
    if getline(lnum) =~# '^#\s\+'
      " H1 の下に空行が複数ある場合は中央の空行に置く（本文入力開始位置）
      if lnum + 2 <= line('$')
            \ && getline(lnum + 1) =~# '^\s*$'
            \ && getline(lnum + 2) =~# '^\s*$'
        return lnum + 2
      endif
      if lnum + 1 <= line('$') && getline(lnum + 1) =~# '^\s*$'
        return lnum + 1
      endif
      return min([lnum + 1, line('$')])
    endif
  endfor
  return min([8, line('$')])
endfunction

function! s:body_top_insert_line() abort
  let l:max = min([120, line('$')])
  for lnum in range(1, l:max)
    if getline(lnum) =~# '^#\s\+'
      if lnum < line('$') && getline(lnum + 1) =~# '^\s*$'
        return lnum + 1
      endif
      return lnum
    endif
  endfor
  return 1
endfunction

" a:1 = v2 で 1 なら `attribute: グループ` を付ける（容器ノート）
function! yurii_pkm#note_template(title, ...) abort
  let l:is_cat = (a:0 > 0 && s:pkm_format() ==# 'v2' && a:1)
  let l:header = [
        \ '---',
        \ 'time: ' . yurii_pkm#timestamp_yaml(),
        \ 'title: ' . a:title,
        \ ]
  if l:is_cat
    call add(l:header, 'attribute: group')
  endif
  call add(l:header, '---')
  if s:pkm_format() ==# 'v2'
    " 普通のノート（zn）は本文の余白を 3 行（最初のカーソルは真ん中）、
    " グループノート（zk）は 1 行だけ空ける（グループは容器で本文を持たないため）。
    let l:gap = l:is_cat ? [''] : ['', '', '']
    return l:header + ['', '# ' . a:title] + l:gap + [s:v2_up_mark, s:v2_down_mark]
  endif
  return l:header + [
        \ '',
        \ '# ' . a:title,
        \ '',
        \ '',
        \ '',
        \ s:canonical_section_title('up'),
        \ s:canonical_section_title('down'),
        \ s:canonical_section_title('backlink'),
        \ '[Index](index.md)',
        \ ]
endfunction


" ---------------------------------------------------------------------------
" v2: 関係(relation)付きリンク追加（--- より上の「こっちにとって」側へ 1 行だけ挿入）
" 逆側は書かない。sync が相方ノートの下側に生成する。
" ---------------------------------------------------------------------------

" ピッカーで選べる関係。論点 / 見解 / 前提 は廃止。
" 既存ノートの 論点: / 見解: / 前提: はそのまま残り、sync の並び替えでも壊れない。
" グループ は選ばせない（相手が attribute: グループ なら sync が自動で付ける。
" 手動で選べると向きが固定で壊れる — zw 専用で s:v2_new_attr から直接渡す）。
let s:v2_relations = ['ノート', '補足', '資料', '関連']
" グループ / 小グループ ノードへリンクする時も、既定は変わらず「ノート」。
" （以前は「索引」という言い換えを出していたが、素の「ノート」で統一する）
let s:v2_relations_attr = ['ノート', '補足', '資料', '関連']

" 関係ごとの向きの制約。0 = こっちにとって側のみ / 1 = そっちにとって側のみ / -1 = 制約なし
function! s:v2_relation_side(rel) abort
  if a:rel ==# 'group' | return 0 | endif
  if a:rel ==# '関連'     | return 1 | endif
  return -1
endfunction

" 数字で 1 項目選ぶ共通ピッカー。末尾は「入力」= 自由入力。'' = キャンセル（Esc/q）。
function! s:v2_pick(label, items) abort
  let l:menu = []
  let l:i = 1
  for l:t in a:items
    call add(l:menu, l:i . ' ' . l:t)
    let l:i += 1
  endfor
  call add(l:menu, l:i . ' 入力')
  echo a:label . '  ' . join(l:menu, '   ') . '    (Esc / q: キャンセル)'
  let l:c = getchar()
  redraw
  if type(l:c) == v:t_number && (l:c == 27 || l:c == 3)
    return ''
  endif
  let l:ch = type(l:c) == v:t_number ? nr2char(l:c) : l:c
  if l:ch ==? 'q' || l:ch !~# '^[0-9]$'
    return ''
  endif
  let l:n = str2nr(l:ch)
  if l:n >= 1 && l:n <= len(a:items)
    return a:items[l:n - 1]
  endif
  if l:n == len(a:items) + 1
    let l:v = ''
    try
      let l:v = trim(input(a:label . '（空でキャンセル）: '))
    catch /^Vim:Interrupt$/
      let l:v = ''
    endtry
    " input() の後すぐに別の echo/getchar を出すと「ENTERキーを押すか」の
    " 待ちが発生することがあるため、ここで一度画面をクリアしておく。
    redraw
    return l:v
  endif
  return ''
endfunction

" a:1 … 1 なら グループ / 小グループ ノードへリンクする時の変種
" （「ノート」の代わりに「索引」を出す）を使う。省略時は通常の一覧。
function! s:v2_pick_relation(...) abort
  let l:items = (a:0 > 0 && a:1) ? s:v2_relations_attr : s:v2_relations
  let l:r = s:v2_pick('relation', l:items)
  " 旧ピッカーの『なし』互換
  return l:r ==# 'なし' ? 'ノート' : l:r
endfunction

" 自由入力（ピッカーの選択肢に無い言葉）を選ぶ枠を「相手側にも書く」/
" 「相手側には書かない」の 2 つに分けたピッカー。固定の選択肢（ノート/補足/
" 資料/関連 等）を選んだ場合は {rel: ..., write: 1} を返す（write は使われない）。
" 自由入力なら選んだ枠に応じて write が 1/0 になる。キャンセルなら {} を返す。
"   a:1 … 1 なら グループ / 小グループ ノードへリンクする時の変種
"   a:2 … 1 なら「自分側にも書く/書かない」の文言（\ca/\at の逆モード用）。
"          省略時は「相手側」文言
function! s:v2_pick_relation2(...) abort
  let l:items = (a:0 > 0 && a:1) ? s:v2_relations_attr : s:v2_relations
  let l:self  = a:0 > 1 ? a:2 : 0
  let l:side  = l:self ? '自分側' : '相手側'

  let l:menu = []
  let l:i = 1
  for l:t in l:items
    call add(l:menu, l:i . ' ' . l:t)
    let l:i += 1
  endfor
  let l:write_idx = l:i
  call add(l:menu, l:i . ' 入力(' . l:side . 'にも書く)')
  let l:i += 1
  let l:nowrite_idx = l:i
  call add(l:menu, l:i . ' 入力(' . l:side . 'には書かない)')

  echo 'relation  ' . join(l:menu, '   ') . '    (Esc / q: キャンセル)'
  let l:c = getchar()
  redraw
  if type(l:c) == v:t_number && (l:c == 27 || l:c == 3)
    return {}
  endif
  let l:ch = type(l:c) == v:t_number ? nr2char(l:c) : l:c
  if l:ch ==? 'q' || l:ch !~# '^[0-9]$'
    return {}
  endif
  let l:n = str2nr(l:ch)
  if l:n >= 1 && l:n <= len(l:items)
    return {'rel': l:items[l:n - 1], 'write': 1}
  endif
  if l:n == l:write_idx || l:n == l:nowrite_idx
    let l:v = ''
    try
      let l:v = trim(input('relation（空でキャンセル）: '))
    catch /^Vim:Interrupt$/
      let l:v = ''
    endtry
    redraw
    if empty(l:v) | return {} | endif
    return {'rel': l:v, 'write': l:n == l:write_idx ? 1 : 0}
  endif
  return {}
endfunction

" sync がラベルをミラーせず自動生成する対象かどうか。`ノート`/`関連` に加え
" `索引` も対象外（グループ/小グループ 文脈での `ノート` の言い換えに過ぎず、
" 容器自身の側は sync 側の例外処理が実際に選んだ語をそのまま反映するため、
" ここで括弧付きの特別扱いをする必要が無い）。
function! s:v2_is_custom_relation(rel) abort
  return a:rel !=# 'ノート' && a:rel !=# '関連' && a:rel !=# '索引'
endfunction

" ピッカーの選択肢（自由入力ではなく数字で選べる既定の語）かどうか。
" これらは「相手にも書くか」を聞かず、常にもう一方の側へ書く
" （聞くのは自由入力で打った言葉だけ）。
function! s:v2_is_menu_relation(rel) abort
  return index(s:v2_relations, a:rel) >= 0 || index(s:v2_relations_attr, a:rel) >= 0
endfunction

" 「聞かれる側」に (ラベル) をその場で書くかどうかを聞く（自由入力はしない、
" 二択のみ）。a:self が真なら自分側（\ca/\at）、偽なら相手側（ca/at 等）が
" 聞かれる側。「いいえ」なら何も書かず sync の既定『ノート』に任せる。
function! s:v2_ask_write_same_label(rel, ...) abort
  let l:self = a:0 > 0 ? a:1 : 0
  let l:side = l:self ? '自分側' : '相手側'
  return s:v2_pick(l:side . 'にも「' . a:rel . '」と書く？', ['はい', 'いいえ（自動）']) ==# 'はい'
endfunction

" 属性ノードは グループ だけ（小グループはグループに統合して廃止）。
" 旧名（カテゴリー / キーワード / 小グループ）はすべて グループ へ読み替える。
" 既存ノートの front matter はそのままでも、機能としては新しい規則で動く。
function! s:v2_normalize_attr(v) abort
  if a:v ==# 'グループ' | return 'group' | endif
  if a:v ==# 'カテゴリー' | return 'group' | endif
  if a:v ==# 'キーワード' | return 'group' | endif
  if a:v ==# '小グループ' | return 'group' | endif
  return a:v
endfunction

" 任意の .md ファイル（現ノートからの相対パス）の front matter attribute 値。無ければ空文字
" （旧名 カテゴリー / キーワード は グループ / 小グループ へ読み替えて返す）
function! s:v2_target_attr(tgt) abort
  let l:path = yurii_pkm#resolve_link(a:tgt)
  if !filereadable(l:path) | return '' | endif
  let l:lines = readfile(l:path, '', 30)
  if empty(l:lines) || l:lines[0] !~# '^---\s*$' | return '' | endif
  for l:i in range(1, len(l:lines) - 1)
    if l:lines[l:i] =~# '^---\s*$' | break | endif
    let l:m = matchlist(l:lines[l:i], '^\s*\%(attribute\|属性\)\s*:\s*\(\S.\{-}\)\s*$')
    if !empty(l:m) | return s:v2_normalize_attr(l:m[1]) | endif
  endfor
  return ''
endfunction

" front matter 終端行と、本文側で末尾寄りの --- 2 本（上側開始 / 下側開始）を返す。
" 2 本無ければ EOF に補って返す。本文中の --- は末尾 2 本にならないので無視される。
let s:v2_up_mark   = '## Parent'
let s:v2_down_mark = '## Child'
" 旧見張り（新しい順: `##` なしの Parent/Child -> こっちにとって/そっちにとって
" -> している/されている）。まだ移行していないノートも読めるように残す。
" sync（note_format_v2.py）が保存時に新表記（## Parent / ## Child）へ書き換える。
let s:v2_up_marks_legacy   = ['Parent', '<!-- こっちにとって -->', '<!-- している -->']
let s:v2_down_marks_legacy = ['Child', '<!-- そっちにとって -->', '<!-- されている -->']

" Parent / Child の見張り行の行番号を返す。
" 見張りはノート作成時（テンプレート）にだけ入る。無ければ [0, 0] を返し、
" 呼び出し側が処理を中止する（後から見張りを追加することは決してしない）。
function! s:v2_boundaries() abort
  let l:up_m = 0 | let l:dn_m = 0
  for l:i in range(1, line('$'))
    let l:s = trim(getline(l:i))
    if l:s ==# s:v2_up_mark || index(s:v2_up_marks_legacy, l:s) >= 0     | let l:up_m = l:i | endif
    if l:s ==# s:v2_down_mark || index(s:v2_down_marks_legacy, l:s) >= 0 | let l:dn_m = l:i | endif
  endfor
  if l:up_m > 0 && l:dn_m > l:up_m
    return [l:up_m, l:dn_m]
  endif
  return [0, 0]
endfunction

" a:rel は末尾に `;` を含みうる（例: `きっかけ;` = sync に自動ミラーさせない
" 印。§4）。見出し行を作る時の実際の終端記号と、既存見出しを探す時の
" パターン（`;` 側の有無を問わず一致）をここで統一する。
function! s:v2_rel_header(rel) abort
  return a:rel =~# ';$' ? a:rel : a:rel . ':'
endfunction

function! s:v2_rel_header_pat(rel) abort
  let l:base = substitute(a:rel, ';$', '', '')
  return '^\V' . escape(l:base, '\') . '\m\s*[:;]'
endfunction

" s:v2_insert_link の行配列版（現在のバッファに限らず、任意ファイルの行に
" 対して同じ処理をするために使う）。target_dir は重複チェックの相対パス
" 解決基準（そのファイル自身のディレクトリ）。戻り値: {lines, ok, reason}
function! s:v2_insert_link_in_lines(lines, target_dir, rel, linktext, below) abort
  let l:lines = a:lines
  let [l:up_m, l:dn_m] = s:v2_boundaries_in_lines(l:lines)
  if l:up_m == 0
    return {'lines': l:lines, 'ok': 0, 'reason': 'no_marks'}
  endif
  let l:n = len(l:lines)
  if a:below
    let l:lo = l:dn_m
    let l:hi = l:n + 1
  else
    let l:lo = l:up_m
    let l:hi = l:dn_m
  endif

  let l:new_tgt = s:extract_target(a:linktext)
  if !empty(l:new_tgt)
    let l:new_fp = fnamemodify(yurii_pkm#resolve_link(l:new_tgt, a:target_dir), ':p')
    for l:i in range(l:lo + 1, min([l:hi - 1, l:n]))
      let l:old = s:extract_target(get(l:lines, l:i - 1, ''))
      if empty(l:old) | continue | endif
      if fnamemodify(yurii_pkm#resolve_link(l:old, a:target_dir), ':p') ==# l:new_fp
        return {'lines': l:lines, 'ok': 0, 'reason': 'dup'}
      endif
    endfor
  endif

  let l:hdr = 0
  for l:i in range(l:lo + 1, l:hi - 1)
    if get(l:lines, l:i - 1, '') =~# s:v2_rel_header_pat(a:rel)
      let l:hdr = l:i | break
    endif
  endfor

  if l:hdr == 0
    " 既定の関係『ノート』は見出しを書かず裸リンクで置く。
    let l:ins = (a:rel ==# 'ノート') ? [a:linktext] : [s:v2_rel_header(a:rel), a:linktext]
    call extend(l:lines, l:ins, l:hi - 1)
    return {'lines': l:lines, 'ok': 1}
  endif

  let l:inline = matchstr(get(l:lines, l:hdr - 1, ''), '[:;]\s*\zs.*$')
  if l:inline =~# '\S'
    let l:lines[l:hdr - 1] = s:v2_rel_header(a:rel)
    call extend(l:lines, [l:inline, a:linktext], l:hdr)
    return {'lines': l:lines, 'ok': 1}
  endif

  let l:end = l:hdr
  for l:i in range(l:hdr + 1, l:hi - 1)
    if get(l:lines, l:i - 1, '') =~# '^\s*\[[^]]*\]([^)]*)'
      let l:end = l:i
    else
      break
    endif
  endfor
  call insert(l:lines, a:linktext, l:end)
  return {'lines': l:lines, 'ok': 1}
endfunction

" ca/bc/cu/at でカスタムラベルを選んだ時、相手ファイルへその場でラベル付き
" バックリンクを直接書き込む。a:below は「自分から見てどちら側に足したか」
" （0=こっちにとって/1=そっちにとって）。相手からは向きが逆になるので
" 書き込みは !a:below 側へ行う。
function! s:v2_write_other_side_label(target_path, label, cur_path, cur_title, below) abort
  if !filereadable(a:target_path) | return 0 | endif
  let l:lines = readfile(a:target_path)
  let l:target_dir = fnamemodify(a:target_path, ':h')
  let l:linktext = s:make_link_from_dir(a:cur_path, a:cur_title, l:target_dir)
  let l:result = s:v2_insert_link_in_lines(l:lines, l:target_dir, a:label, l:linktext, !a:below)
  if !l:result.ok
    return l:result.reason ==# 'dup' ? 1 : 0
  endif
  call writefile(l:result.lines, a:target_path)
  return 1
endfunction

" a:below … 0 = 上側（こっちにとって、見張りの間）、1 = 下側（そっちにとって、最後の見張り以降）
function! s:v2_insert_link(rel, linktext, ...) abort
  let l:below = a:0 > 0 ? a:1 : 0
  let [l:up_m, l:dn_m] = s:v2_boundaries()
  if l:up_m == 0
    echohl WarningMsg
    echo 'yurii_PKM: このノートは v2 形式じゃない（見張りコメントなし）。:V2Migrate で変換して'
    echohl NONE
    return 0
  endif
  " 以降は必ず 1 を返す（末尾で return 1）
  if l:below
    let l:lo = l:dn_m
    let l:hi = line('$') + 1
  else
    let l:lo = l:up_m
    let l:hi = l:dn_m
  endif

  " 同じ相手が既にこの区間に居れば二重に足さない（c を2回押しても増えない）
  let l:new_tgt = s:extract_target(a:linktext)
  if !empty(l:new_tgt)
    let l:new_fp = fnamemodify(yurii_pkm#resolve_link(l:new_tgt, expand('%:p:h')), ':p')
    for l:i in range(l:lo + 1, min([l:hi - 1, line('$')]))
      let l:old = s:extract_target(getline(l:i))
      if empty(l:old) | continue | endif
      if fnamemodify(yurii_pkm#resolve_link(l:old, expand('%:p:h')), ':p') ==# l:new_fp
        echo 'yurii_PKM: すでに登録済み — ' . l:new_tgt
        return 0
      endif
    endfor
  endif

  " 該当区間の `関係:` / `関係;` ヘッダを探す
  let l:hdr = 0
  for l:i in range(l:lo + 1, l:hi - 1)
    if getline(l:i) =~# s:v2_rel_header_pat(a:rel)
      let l:hdr = l:i | break
    endif
  endfor

  if l:hdr == 0
    " 既定の関係『ノート』は見出しを書かず裸リンクで置く（sync の正規形に
    " 合わせる。`ノート:` を一旦挟まない）。それ以外はブロック形。
    let l:ins = (a:rel ==# 'ノート') ? [a:linktext] : [s:v2_rel_header(a:rel), a:linktext]
    if l:below
      call append(line('$'), l:ins)
    else
      call append(l:hi - 1, l:ins)
    endif
    return 1
  endif

  let l:inline = matchstr(getline(l:hdr), '[:;]\s*\zs.*$')
  if l:inline =~# '\S'
    call setline(l:hdr, s:v2_rel_header(a:rel))
    call append(l:hdr, [l:inline, a:linktext])
    return 1
  endif

  let l:end = l:hdr
  for l:i in range(l:hdr + 1, l:hi - 1)
    if getline(l:i) =~# '^\s*\[[^]]*\]([^)]*)'
      let l:end = l:i
    else
      break
    endif
  endfor
  call append(l:end, a:linktext)
  return 1
endfunction

function! s:v2_title_for(tgt) abort
  let l:root = s:get_pkm_root()
  let l:t = ''
  if !empty(l:root)
    let l:t = s:get_yaml_title(s:join_path(l:root, a:tgt))
  endif
  return l:t !=# '' ? l:t : fnamemodify(a:tgt, ':t:r')
endfunction

" クリップボード / 無名レジスタの `.md` ファイル名 or `[t](x.md)` を関係付きで取り込む。
" 複数行 / 複数リンクにも対応（1 件なら従来どおり質問なしで進む）。
"   a:1 … 取り込む対象（空ならレジスタから。複数行 / 複数リンクも可）
"   a:2 … 関係(relation)（省略時は数字で選択。複数件なら先に「一括 / 個別」を聞く）
"   a:3 … 1 なら --- より下（そっちにとって）へ。既定は上
"   a:4 … 1 なら逆モード（\ca/\at）。今開いているノート側を `(ラベル)` にし、
"          相手側には生のラベルをその場で（質問なしで）書く。通常モード
"          （ca/at）とは括弧が付く側が逆になるだけで、他のロジックは共通。
function! yurii_pkm#v2_add_link(...) abort
  let l:raw = a:0 > 0 && a:1 !=# '' ? a:1 : trim(getreg('+'))
  if l:raw ==# '' | let l:raw = trim(getreg('"')) | endif
  let l:below_default = a:0 > 2 ? a:3 : 0
  let l:reverse = a:0 > 3 ? a:4 : 0

  let l:targets = filter(s:extract_targets_from_clipboard(l:raw), 'v:val =~# ''\.md$''')
  if empty(l:targets)
    echohl WarningMsg | echo 'yurii_PKM: .md のファイル名 / リンクが見つからない' | echohl NONE
    return
  endif

  " 対象にグループ / 小グループ属性のファイルが含まれるか（先に判定しておき、
  " 関係ピッカーで「ノート」の代わりに「索引」を出すかどうかに使う）。
  " 現在のノート自身が グループ / 小グループ 属性の場合も同様に「索引」を出す
  " （zc/zp と同じ判定基準。自分が容器なら、相手が普通のノートでも「索引」）。
  let l:attr_targets = {}
  for l:t in l:targets
    if s:v2_target_attr(l:t) !=# '' | let l:attr_targets[l:t] = 1 | endif
  endfor
  let l:self_attr = !empty(s:v2_buf_attr())
  let l:all_attr = l:self_attr || (!empty(l:attr_targets) && len(l:attr_targets) == len(l:targets))

  " 関係: 複数件なら「一括で同じ関係」か「一つずつ選ぶ」かを先に聞く
  let l:rel_fixed = a:0 > 1 && a:2 !=# '' ? a:2 : ''
  let l:batch_rel = l:rel_fixed
  if empty(l:batch_rel)
    if len(l:targets) == 1
      let l:batch_rel = s:v2_pick_relation(l:all_attr)
      if l:batch_rel ==# '' | echo 'yurii_PKM: キャンセル' | return | endif
    else
      let l:mode = s:v2_pick('複数件の関係', ['一括で同じ関係', '一つずつ選ぶ'])
      if l:mode ==# '' | echo 'yurii_PKM: キャンセル' | return | endif
      if l:mode ==# '一括で同じ関係'
        let l:batch_rel = s:v2_pick_relation(l:all_attr)
        if l:batch_rel ==# '' | echo 'yurii_PKM: キャンセル' | return | endif
      endif
    endif
  endif

  " 表示名: 対象にグループ / 小グループ属性のファイルが含まれるなら、
  " その表示名の付け方を聞く（複数あれば「一つずつ入力」か「タイトルのまま」を先に選ぶ）。
  " ただし呼び出し側が関係を固定している（za など）ときは表示名を一切聞かず、
  " 相手のタイトルのまま追加する（複数対象でもピッカーを出さない）。
  let l:manual_name = !empty(l:attr_targets) && len(l:attr_targets) == 1
  if !empty(l:rel_fixed)
    let l:manual_name = 0
  elseif !empty(l:attr_targets) && len(l:attr_targets) > 1
    let l:nm = s:v2_pick('属性ノートの表示名', ['一つずつ入力', 'タイトルのまま'])
    if l:nm ==# '' | echo 'yurii_PKM: キャンセル' | return | endif
    let l:manual_name = (l:nm ==# '一つずつ入力')
  endif

  let l:cur_path  = expand('%:p')
  let l:cur_title = yurii_pkm#current_title()
  if l:cur_title ==# '' | let l:cur_title = fnamemodify(l:cur_path, ':t:r') | endif

  " まず各対象の関係・向き・表示名を決めるだけ決める（挿入はまだしない）。
  " こうしておくと、「相手側にも同じラベルを書くか」を全体で 1 回だけ
  " 聞ける（個々の関係が何であれ、答えは 1 つで済む）。
  let l:entries = []
  for l:tgt in l:targets
    let l:is_attr = has_key(l:attr_targets, l:tgt)
    let l:rel = !empty(l:batch_rel) ? l:batch_rel : s:v2_pick_relation(l:self_attr || l:is_attr)
    if l:rel ==# ''
      echo 'yurii_PKM: ' . l:tgt . ' はキャンセルしてスキップ'
      continue
    endif
    " 関係ごとの向きの制約（グループ=こっちにとって / 関連=対称）
    let l:side = s:v2_relation_side(l:rel)
    let l:below = l:side >= 0 ? l:side : l:below_default

    let l:default_title = s:v2_title_for(l:tgt)
    let l:title = l:default_title
    if l:is_attr && l:manual_name
      let l:input = trim(input('[' . l:tgt . '] 表示名: ', l:default_title))
      let l:title = empty(l:input) ? l:default_title : l:input
    endif

    call add(l:entries, {'tgt': l:tgt, 'rel': l:rel, 'below': l:below, 'title': l:title})
  endfor

  " 自由入力（ピッカーの選択肢に無い言葉）が 1 件でもあれば、「聞かれる側」
  " （通常モードなら相手側、逆モード \ca/\at なら自分側）に `(ラベル)` を
  " その場で書くかどうかを全体で 1 回だけ聞く。「いいえ」なら聞かれる側には
  " 何も書かず、次の sync が既定の『ノート』を生成する。ピッカーの選択肢
  " （索引/補足/資料 等）は聞かず、常にもう一方の側へ `(ラベル)` を書く
  " （聞くのは自由入力の言葉だけ）。「もう一方の側」（通常モードなら自分側、
  " 逆モードなら相手側）は常に、質問なしで生のラベルをその場で書く。
  let l:free_rels = {}
  for l:e in l:entries
    if s:v2_is_custom_relation(l:e.rel) && !s:v2_is_menu_relation(l:e.rel)
      let l:free_rels[l:e.rel] = 1
    endif
  endfor
  let l:write_asked = 0
  if len(l:free_rels) == 1
    let l:write_asked = s:v2_ask_write_same_label(keys(l:free_rels)[0], l:reverse)
  elseif len(l:free_rels) > 1
    let l:msg = l:reverse ? '自分側にもそれぞれ書く？' : '相手側にもそれぞれ書く？'
    let l:write_asked = s:v2_pick(l:msg, ['はい', 'いいえ（自動）']) ==# 'はい'
  endif

  let l:added = 0
  let l:other_written = 0
  for l:e in l:entries
    let l:is_custom = s:v2_is_custom_relation(l:e.rel)
    " ピッカーの選択肢（索引/補足/資料 等）は聞かず常に書く。自由入力の
    " 言葉だけ、上で聞いた結果（l:write_asked）に従う。
    let l:do_write = l:is_custom && (s:v2_is_menu_relation(l:e.rel) || l:write_asked)
    let l:tgt_path = yurii_pkm#resolve_link(l:e.tgt)
    if l:reverse
      " \ca/\at: 相手側は常に（質問なしで）生のラベルをその場で書く。
      " 自分側は聞かれる側: 書くなら (ラベル) をその場で書き、
      " 書かないなら何も書かず sync 任せ（既定の『ノート』になる）。
      " 書かない場合、相手側は `;` 終端で書く（sync の自動ミラー対象外に
      " するため。§4）。
      if l:is_custom
        let l:other_write_rel = l:do_write ? l:e.rel : l:e.rel . ';'
        call s:v2_write_other_side_label(l:tgt_path, l:other_write_rel, l:cur_path, l:cur_title, l:e.below)
        let l:other_written = 1
      endif
      if !l:is_custom || l:do_write
        let l:own_rel = l:is_custom ? '(' . l:e.rel . ')' : l:e.rel
        if s:v2_insert_link(l:own_rel, '[' . l:e.title . '](' . l:e.tgt . ')', l:e.below)
          let l:added += 1
          echo 'yurii_PKM: ' . l:own_rel . (l:e.below ? ' ↓ ' : ' ') . '+= ' . l:e.title
        endif
      else
        echo 'yurii_PKM: ' . l:e.rel . (l:e.below ? ' ↓ ' : ' ') . '(相手のみ) += ' . l:e.title
      endif
    else
      " ca/at/bc/cu: 自分側は常に生のラベルをその場で書く。相手側は
      " 聞かれる側: 書くなら (ラベル) をその場で書き、書かないなら何も
      " 書かず sync 任せ（既定の『ノート』になる）。書かない場合、自分側は
      " `;` 終端で書く（sync の自動ミラー対象外にするため。§4）。
      let l:own_write_rel = (l:is_custom && !l:do_write) ? l:e.rel . ';' : l:e.rel
      if s:v2_insert_link(l:own_write_rel, '[' . l:e.title . '](' . l:e.tgt . ')', l:e.below)
        let l:added += 1
        echo 'yurii_PKM: ' . l:own_write_rel . (l:e.below ? ' ↓ ' : ' ') . '+= ' . l:e.title
        if l:do_write
          call s:v2_write_other_side_label(l:tgt_path, '(' . l:e.rel . ')', l:cur_path, l:cur_title, l:e.below)
          let l:other_written = 1
        endif
      endif
    endif
  endfor
  if l:added > 0
    silent! write
  elseif l:other_written
    call s:run_update_one_for(l:cur_path)
  endif
endfunction

" --- ページを開きながら関連ノートを新規作成。
"   a:below … 1 = 現ノートの --- より下（子: 相手が上側に載る）
"             0 = 現ノートの --- より上（親: 相手の下側に載る）
"   a:1     … 関係(relation)（省略時は数字で選択）
" a:below … 0 = 現ノートの こっちにとって 側 / 1 = そっちにとって 側
" a:attr  … 空でなければ新ノートを `attribute: {a:attr}` で作る（グループ / 小グループ 等）
" a:1(可変) … 関係名（省略時は数字ピッカー）
function! s:v2_new_related(below, attr, ...) abort
  if s:pkm_format() !=# 'v2'
    echo 'yurii_PKM: v2 専用（g:yurii_pkm_format = ''v2''）' | return
  endif
  let l:cur = expand('%:p')
  if empty(l:cur)
    echohl WarningMsg | echo 'yurii_PKM: 名前付きバッファで実行して' | echohl NONE
    return
  endif
  " 現ノートが属性ノート（グループ / 小グループ）なら、関係ピッカーは
  " 「ノート」の代わりに「索引」を出す変種を使う（§2）。
  let l:cur_attr = s:v2_buf_attr()
  if a:0 > 0 && a:1 !=# ''
    let l:rel = a:1
    " a:2 で write を明示できる（zw が事前にピッカーで選んだ結果を渡す用）。
    " 省略時は 1（nn 等、固定関係を渡すだけの呼び出しに合わせる）。
    let l:write = a:0 > 1 ? a:2 : 1
  else
    let l:pick = s:v2_pick_relation2(!empty(l:cur_attr))
    if empty(l:pick) | echo 'yurii_PKM: キャンセル' | return | endif
    let l:rel   = l:pick.rel
    let l:write = l:pick.write
  endif
  " 関係ごとの向きの制約（関連=対称）。属性ノート（グループ / 小グループ）は
  " zw が c/p の選択どおりの a:below を渡してくるので、ここでは上書きしない
  " （上書きすると c/p の意味が反転する）。
  let l:side = !empty(a:attr) ? -1 : s:v2_relation_side(l:rel)
  let l:below = l:side >= 0 ? l:side : a:below

  " 現ノート（＝新ノートの相手）の情報
  let l:cur_name  = expand('%:t')
  let l:cur_title = yurii_pkm#current_title()
  if l:cur_title ==# '' | let l:cur_title = fnamemodify(l:cur, ':t:r') | endif
  " 現ノートが属性ノートなら、新ノート側のラベルを上書きする。
  " below=1（nc: backlink は新ノートの こっちにとって）: 相手（現ノート）が
  " グループ / 小グループ どちらの属性でも、値に関わらず常に グループ。
  " below=0（np: backlink は新ノートの そっちにとって）: 現ノート自身が
  " グループ の場合だけ上書き（サブ容器）。小グループは上書きしない。
  " 属性による強制が無く、かつ自由入力の言葉を選んだ場合、相手側にも書くかは
  " ピッカーの 5/6（入力枠が「書く」/「書かない」の 2 つに分かれている）で
  " 決まる（l:write。確認ダイアログは出さない）。ピッカーの選択肢（補足/資料
  " 等）は常に括弧付きで書く。書かない場合は新ノートへは何も書かず（sync が
  " 既定の『ノート』を生成する）、代わりに現ノート側を `;` 終端で書く
  " （sync の自動ミラー対象外にするため。ca/at と同じ規約。§4）。
  let l:forced_group = a:below ? !empty(l:cur_attr) : (l:cur_attr ==# 'group')
  let l:own_write_rel = l:rel
  if l:forced_group
    let l:back_rel = 'group'
  elseif s:v2_is_custom_relation(l:rel) && !s:v2_is_menu_relation(l:rel)
    if l:write
      let l:back_rel = '(' . l:rel . ')'
    else
      let l:back_rel = ''
      let l:own_write_rel = l:rel . ';'
    endif
  elseif s:v2_is_custom_relation(l:rel)
    let l:back_rel = '(' . l:rel . ')'
  else
    let l:back_rel = l:rel
  endif

  let l:dir = expand('%:p:h')
  let l:ts  = yurii_pkm#timestamp_filename()
  let l:file = s:join_path(l:dir, l:ts . '.md')

  let l:save_ai = &autoindent | let l:save_si = &smartindent
  setlocal noautoindent nosmartindent
  let l:ok = s:v2_insert_link(l:own_write_rel, '[' . l:ts . '](' . l:ts . '.md)', l:below)
  let &autoindent = l:save_ai | let &smartindent = l:save_si
  if !l:ok
    return  " 現ノートが v2 形式でない（見張りなし）
  endif

  " 新ノートを組み立てる。相手へのリンクを先に入れておく（sync が確認するだけ）。
  " zc: 相手は新ノートの こっちにとって 側 / zp: そっちにとって 側。
  " 常にブロック形（『ラベル:』の次行にリンク）。back_rel が空（書かない
  " を選んだ）なら新ノートには何も書かず、sync が既定の『ノート』を生成する。
  let l:backlink = empty(l:back_rel) ? [] :
        \ [l:back_rel . ':', '[' . l:cur_title . '](' . l:cur_name . ')']
  let l:fm = ['---', 'time: ' . yurii_pkm#timestamp_yaml(), 'title: ' . l:ts]
  if !empty(a:attr) | call add(l:fm, 'attribute: ' . a:attr) | endif
  call add(l:fm, '---')
  let l:up   = a:below ? l:backlink : []
  let l:down = a:below ? [] : l:backlink
  let l:lines = l:fm + ['', '# ' . l:ts, '', '', '', s:v2_up_mark]
        \ + l:up + [s:v2_down_mark] + l:down
  call writefile(l:lines, l:file)
  silent noautocmd write
  call s:run_update_one_for(l:cur)
  execute 'edit ' . fnameescape(l:file)
  " 本文入力位置（H1 の 2 行下）へ
  let l:h1 = search('^#\s', 'nw')
  if l:h1 > 0 | call cursor(l:h1 + 2, 1) | endif
  startinsert
endfunction

" 現在バッファの attribute 値（グループ / 小グループ 等）。無ければ空文字
" （旧名 カテゴリー / キーワード は グループ / 小グループ へ読み替えて返す）
function! s:v2_buf_attr() abort
  if getline(1) !~# '^---\s*$' | return '' | endif
  for l:i in range(2, min([25, line('$')]))
    if getline(l:i) =~# '^---\s*$' | break | endif
    let l:m = matchlist(getline(l:i), '^\s*\%(attribute\|属性\)\s*:\s*\(\S.\{-}\)\s*$')
    if !empty(l:m) | return s:v2_normalize_attr(l:m[1]) | endif
  endfor
  return ''
endfunction

" zc: 子ノート（リンクは現ノートの そっちにとって 側）
" zc/zp は zn に一本化して廃止。コマンド :NC / :NP からの互換のためだけに残す。
function! yurii_pkm#v2_new_child(...) abort
  call s:v2_new_interactive('')
endfunction

function! yurii_pkm#v2_new_parent(...) abort
  call s:v2_new_interactive('')
endfunction

" zw は廃止して zk（グループノート）に置き換え。互換のため名前だけ残す。
function! yurii_pkm#v2_new_attr() abort
  call s:v2_new_interactive('group')
endfunction

" pe: 現ノートを起点に 親/子/文中 を辿って 1 つの展開ファイルへ集約する。
" シンプル（深さを 1 つだけ指定、親/子/文中を区別せず平等に辿る）と
" 詳細（親・子・文中それぞれ独立の深さ。前回の詳細設定は
" ROOT/.pkm_expand_prefs.json に記録され、次回「保存済み設定を使う」で
" 再利用できる）を選ぶ。出力は ROOT/_tmp/T_<timestamp>.md（sync 管理外、
" 編集しても元ノートへは反映されない使い捨てスナップショット）。
function! yurii_pkm#v2_expand() abort
  let l:cur = expand('%:p')
  if empty(l:cur)
    echohl WarningMsg | echo 'yurii_PKM: 名前付きバッファで実行して' | echohl NONE
    return
  endif
  let l:root = s:get_pkm_root()
  if empty(l:root)
    echohl WarningMsg | echo 'yurii_PKM: PKM root が未設定' | echohl NONE
    return
  endif
  let l:py = get(g:, 'yurii_pkm_expand_v2_python', '')
  if empty(l:py) || !filereadable(l:py)
    echohl WarningMsg | echo 'yurii_PKM: expand_v2.py が見つからない: ' . l:py | echohl NONE
    return
  endif

  let l:mode = s:v2_pick('展開', ['シンプル', '詳細'])
  if l:mode ==# '' | echo 'yurii_PKM: キャンセル' | return | endif

  if l:mode ==# 'シンプル'
    let l:n = input('深さ（数字）: ', '1')
    if l:n !~# '^\d\+$' | echo 'yurii_PKM: キャンセル' | return | endif
    let l:args = [s:python_cmd(), l:py, 'simple', l:root, l:cur, l:n]
  else
    let l:prefs = s:v2_expand_prefs(l:root, l:py)
    let l:use_saved = 0
    if !empty(l:prefs)
      let l:pm = s:v2_pick('詳細設定', [
            \ '保存済み(子' . l:prefs.child . ' 親' . l:prefs.parent . ' 文中' . l:prefs.backlink . ')を使う',
            \ '新しく設定する'])
      if l:pm ==# '' | echo 'yurii_PKM: キャンセル' | return | endif
      let l:use_saved = (l:pm =~# '^保存済み')
    endif
    if l:use_saved
      let l:cd = l:prefs.child
      let l:pd = l:prefs.parent
      let l:bd = l:prefs.backlink
    else
      let l:cd = input('子の深さ: ', '1')
      let l:pd = input('親の深さ: ', '1')
      let l:bd = input('文中の深さ: ', '0')
      if l:cd !~# '^\d\+$' || l:pd !~# '^\d\+$' || l:bd !~# '^\d\+$'
        echo 'yurii_PKM: キャンセル' | return
      endif
    endif
    let l:args = [s:python_cmd(), l:py, 'detailed', l:root, l:cur, l:cd, l:pd, l:bd]
  endif

  let l:out = systemlist(join(map(copy(l:args), 'shellescape(v:val)'), ' '))
  if v:shell_error != 0 || empty(l:out)
    echohl WarningMsg | echo 'yurii_PKM: 展開に失敗: ' . join(l:out, ' ') | echohl NONE
    return
  endif
  let l:result_path = l:out[-1]
  if !filereadable(l:result_path)
    echohl WarningMsg | echo 'yurii_PKM: 展開ファイルが見つからない: ' . l:result_path | echohl NONE
    return
  endif
  execute 'edit ' . fnameescape(l:result_path)
endfunction

" 詳細モードの前回設定を取得する。無ければ空 dict
function! s:v2_expand_prefs(root, py) abort
  let l:args = [s:python_cmd(), a:py, 'get_prefs', a:root]
  let l:out = systemlist(join(map(copy(l:args), 'shellescape(v:val)'), ' '))
  if v:shell_error != 0 || empty(l:out) || trim(l:out[0]) ==# ''
    return {}
  endif
  let l:parts = split(trim(l:out[0]))
  if len(l:parts) != 3 | return {} | endif
  return {'child': l:parts[0], 'parent': l:parts[1], 'backlink': l:parts[2]}
endfunction

" カーソル直下ノート（zh）: 新ノートを作り、そのリンクをカーソル行の直下（本文）に置く。
" 関係セクションには入れない → 相手には バックリンク: として現れる。
function! yurii_pkm#v2_new_here() abort
  if s:pkm_format() !=# 'v2'
    echo 'yurii_PKM: v2 専用' | return
  endif
  let l:cur = expand('%:p')
  if empty(l:cur)
    echohl WarningMsg | echo 'yurii_PKM: 名前付きバッファで実行して' | echohl NONE
    return
  endif
  let l:dir = expand('%:p:h')
  let l:ts  = yurii_pkm#timestamp_filename()
  let l:file = s:join_path(l:dir, l:ts . '.md')
  call writefile(yurii_pkm#note_template(l:ts, 0), l:file)
  let l:save_ai = &autoindent | let l:save_si = &smartindent
  setlocal noautoindent nosmartindent
  call append(line('.'), '[' . l:ts . '](' . l:ts . '.md)')
  let &autoindent = l:save_ai | let &smartindent = l:save_si
  silent noautocmd write
  call s:run_update_one_for(l:cur)
  execute 'edit ' . fnameescape(l:file)
endfunction

" zn: ノート作成。リレーションは書かず、位置だけ h/Enter/o/p で選ぶ。
function! yurii_pkm#v2_new_plain() abort
  call s:v2_new_interactive('')
endfunction

" zk: グループノート作成（attribute: グループ）。位置は zn と同じ h/Enter/o/p。
function! yurii_pkm#v2_new_group() abort
  call s:v2_new_interactive('group')
endfunction

" zn / zk の共通本体。
"   a:attr が空なら普通のノート、'グループ' なら容器ノート（attribute: グループ）。
"   作成時にリレーション（ノート: など）は一切書かない。置くのは素のリンク 1 行で、
"   あとから手で グループ / きっかけ: などを書く。`:` / `;` は sync がそのまま扱う。
"   位置キー: h=カーソル直下 / Enter=Child末尾 / o=リンク無し(孤立) / p=Parent末尾。
function! s:v2_new_interactive(attr) abort
  if s:pkm_format() !=# 'v2'
    echo 'yurii_PKM: v2 専用' | return
  endif
  let l:cur = expand('%:p')
  if empty(l:cur)
    echohl WarningMsg | echo 'yurii_PKM: 名前付きバッファで実行して' | echohl NONE | return
  endif
  let l:dir = expand('%:p:h')
  let l:ts  = yurii_pkm#timestamp_filename()
  let l:file = s:join_path(l:dir, l:ts . '.md')

  echo 'h=カーソル直下 / o=リンク無し(孤立) / p=Parent / Enter=Child末尾  (Esc/q キャンセル)'
  let l:ch = nr2char(getchar())
  redraw
  if l:ch ==? 'q' || char2nr(l:ch) == 27 || char2nr(l:ch) == 3
    echo 'yurii_PKM: キャンセル' | return
  endif

  " 新ノートを先に作る（sync がリンク先を解決できるように）
  call writefile(yurii_pkm#note_template(l:ts, !empty(a:attr) ? 1 : 0), l:file)

  let l:link = '[' . l:ts . '](' . l:ts . '.md)'
  let l:added = 0
  let l:save_ai = &autoindent | let l:save_si = &smartindent
  setlocal noautoindent nosmartindent
  if l:ch ==? 'h'
    call append(line('.'), l:link)      " カーソル直下（本文）
    let l:added = 1
  elseif l:ch ==? 'p'
    let [l:up_m, l:dn_m] = s:v2_boundaries()
    if l:up_m > 0
      call append(l:dn_m - 1, l:link)   " Parent の末尾（## Child の直前）
      let l:added = 1
    endif
  elseif l:ch ==# "\<CR>" || l:ch ==# "\<NL>"
    call append(line('$'), l:link)      " Child の最後尾
    let l:added = 1
  endif
  " o … リンク無し（孤立）
  let &autoindent = l:save_ai | let &smartindent = l:save_si
  silent noautocmd write
  if l:added
    call s:run_update_one_for(l:cur)
  endif
  call yurii_pkm#push_history()
  execute 'edit ' . fnameescape(l:file)
  " 本文入力位置へ。zn は余白 2 行なので 2 行下、zk（グループ）は 1 行下。
  let l:h1 = search('^#\s', 'nw')
  if l:h1 > 0 | call cursor(l:h1 + (empty(a:attr) ? 2 : 1), 1) | endif
  startinsert
endfunction

" 旧形式（v1 の Parent:/Child: / 旧 `---`）を v2 へ明示変換。
"   :V2Migrate       … PKM ルート全体
"   :V2Migrate %     … 現在のファイルだけ
function! yurii_pkm#v2_migrate(...) abort
  if s:pkm_format() !=# 'v2'
    echo 'yurii_PKM: v2 のみ' | return
  endif
  let l:root = s:get_pkm_root()
  if empty(l:root) | echoerr 'yurii_PKM: PKM ルート未設定' | return | endif
  let l:args = [s:python_cmd(), g:yurii_pkm_python, 'migrate', l:root]
  if a:0 > 0 && a:1 !=# ''
    call add(l:args, a:1 ==# '%' ? expand('%:p') : a:1)
  endif
  echo system(join(map(copy(l:args), 'shellescape(v:val)'), ' '))
  silent! edit
endfunction

function! s:v2_link_dispatch() abort
  if s:pkm_format() ==# 'v2'
    call yurii_pkm#v2_add_link()
    return 1
  endif
  return 0
endfunction


function! s:make_link_from_dir(path, title, base_dir) abort
  let l:path = trim(a:path)
  if s:is_absolute_path(l:path)
    let l:file = s:relpath_from_dir(l:path, a:base_dir)
  else
    let l:file = s:markdown_relative_target(l:path)
  endif
  let l:name = fnamemodify(l:file, ':t')
  let l:text = empty(a:title) ? fnamemodify(l:name, ':r') : a:title
  return '[' . l:text . '](' . l:file . ')'
endfunction

function! yurii_pkm#make_link(path, title) abort
  return s:make_link_from_dir(a:path, a:title, expand('%:p:h'))
endfunction

function! s:parent_link_lines(parent_path, parent_title, base_dir) abort
  if empty(a:parent_path)
    return []
  endif
  return [s:make_link_from_dir(a:parent_path, a:parent_title, a:base_dir)]
endfunction

function! s:cwd_note_dir() abort
  let l:dir = fnamemodify(getcwd(), ':p')
  let l:trimmed = substitute(l:dir, '[\\/]\+$', '', '')
  return empty(l:trimmed) ? l:dir : l:trimmed
endfunction

function! s:join_path(dir, name) abort
  if a:dir =~# '[\\/]$'
    return a:dir . a:name
  endif
  return a:dir . s:sep() . a:name
endfunction

" ---------------------------------------------------------------------------
" Update link titles in current buffer (Vim-side, lightweight)
" ---------------------------------------------------------------------------

function! yurii_pkm#update_current_buffer() abort
  let l:in_branch = 0
  let l:in_back   = 0
  let l:after_sep = 0
  let l:in_fence  = 0
  let l:modified  = 0

  for l:i in range(1, line('$'))
    let l:line = getline(l:i)
    let l:trimmed = trim(l:line)

    if l:trimmed =~# '^```'
      let l:in_fence = !l:in_fence
    endif

    if !l:in_fence
      if s:is_section_header_text(l:trimmed, 'branch')
        let l:in_branch = 1 | let l:in_back = 0 | let l:after_sep = 0
        continue
      endif
      if s:is_section_header_text(l:trimmed, 'back')
        let l:in_branch = 0 | let l:in_back = 1 | let l:after_sep = 0
        continue
      endif
      if l:trimmed =~# '^_\{3,}\s*$'
        let l:after_sep = 1
        continue
      endif
    endif

    if l:after_sep || l:in_fence
      continue
    endif

    if (l:in_branch || l:in_back) && l:line =~# '\[[^\]]\+\]([^)]\+\.md)'
      let l:lm = matchlist(l:line, '^\(\[\([^\]]\+\)\](\([^)]\+\))\)\(.*\)$')
      if !empty(l:lm)
        let l:link_text = get(l:lm, 2, '')
        let l:target    = trim(get(l:lm, 3, ''))
        let l:suffix    = get(l:lm, 4, '')

        let l:target_stem = fnamemodify(fnamemodify(l:target, ':t'), ':r')
        if l:link_text !=# l:target_stem
          continue
        endif

        let l:filepath  = expand('%:p:h') . s:sep() . l:target
        if filereadable(l:filepath)
          let l:title = s:get_title(l:filepath)
          if !empty(l:title)
            let l:new_line = '[' . l:title . '](' . l:target . ')' . l:suffix
            if l:new_line !=# l:line
              call setline(l:i, l:new_line)
              let l:modified = 1
            endif
          endif
        endif
      endif
    endif
  endfor

  if l:modified
    echo 'yurii_PKM: link titles updated'
  endif
endfunction

" ---------------------------------------------------------------------------
" UpdateMD / UpdateAll
" ---------------------------------------------------------------------------

function! yurii_pkm#update_md(arg) abort
  let l:root = empty(a:arg) ? yurii_pkm#ensure_root_and_index() : fnamemodify(expand(a:arg), ':p')
  if empty(l:root)
    return
  endif
  if !empty(a:arg)
    let g:yurii_pkm_root = l:root
    if !isdirectory(l:root)
      call mkdir(l:root, 'p')
    endif
    call s:save_persisted_root(l:root)
    call s:setup_persistent_undo_for_root(l:root)
  endif
  call yurii_pkm#check_missing_prefix_in_current_dir()
  let l:out = s:run_sync([g:yurii_pkm_python, 'update', l:root])
  if v:shell_error
    echoerr substitute(l:out, '\n\+$', '', '')
    return
  endif
  echo substitute(l:out, '\n\+$', '', '')
  call s:reload_current()
endfunction

function! yurii_pkm#update_all(arg) abort
  call yurii_pkm#update_md(a:arg)
endfunction

" 現在バッファをディスクから再読み込み（未変更の場合のみ、カーソル位置保持）
function! s:reload_current() abort
  set autoread
  if has('timers')
    " timer 経由で少し遅らせることで、job完了直後でも確実に反映される
    call timer_start(120, function('s:reload_timer_cb'))
  else
    call s:do_reload()
  endif
endfunction

function! s:reload_timer_cb(timer) abort
  call s:do_reload()
endfunction

function! s:do_reload() abort
  " 全バッファの外部変更を検出
  checktime
  " 現在バッファが未保存でなければ再読み込み（カーソル位置保持）
  let l:cur = expand('%:p')
  if !empty(l:cur) && filereadable(l:cur) && !&modified
    let l:pos = getpos('.')
    let l:view = winsaveview()
    " E823（undoファイル不一致）を抑制しつつ再読み込み
    silent! execute 'edit ' . fnameescape(l:cur)
    call winrestview(l:view)
    call setpos('.', l:pos)
  endif
endfunction

" ---------------------------------------------------------------------------
" Auto-sync: BufWritePost で update_one を非同期実行
"
"   - 保存後に動くので編集を妨げない
"   - job_start が使えれば完全非同期、なければ system() でフォールバック
"   - 完了後 checktime で Vim バッファを更新
" ---------------------------------------------------------------------------

function! yurii_pkm#autosync_on_save() abort
  if !filereadable(g:yurii_pkm_python)
    return
  endif

  " PKM root 配下のファイルのみ対象
  let l:file = expand('%:p')
  let l:root = s:get_pkm_root()
  if empty(l:root) || !filereadable(s:index_path(l:root))
    return
  endif
  if !s:is_root_note_path(l:file)
    return
  endif

  let l:py   = s:python_cmd()
  let l:args = [l:py, g:yurii_pkm_python, 'update_one', l:file, l:root]

  if has('job') && has('channel')
    " 非同期実行
    let l:cmd = join(map(copy(l:args), 'shellescape(v:val)'), ' ')
    call job_start(['/bin/sh', '-c', l:cmd], {
          \ 'exit_cb': function('s:autosync_done'),
          \ 'out_io':  'null',
          \ 'err_io':  'null',
          \ })
  else
    " 同期フォールバック
    let l:cmd = join(map(copy(l:args), 'shellescape(v:val)'), ' ')
    let l:out = system(l:cmd)
    if !v:shell_error
      checktime
    endif
  endif
endfunction

function! s:autosync_done(job, status) abort
  " job完了後にバッファを外部変更に合わせる
  call s:reload_current()
endfunction

" 任意のファイルパスに対して update_one を起動するヘルパー
function! s:update_one_command(target_fp, ...) abort
  let l:force = a:0 > 0 ? a:1 : 0
  if !l:force && !g:yurii_pkm_autosync | return '' | endif
  if !filereadable(g:yurii_pkm_python) | return '' | endif
  let l:root = s:get_pkm_root()
  if empty(l:root) || !filereadable(s:index_path(l:root))
    return ''
  endif
  if !s:is_root_note_path(a:target_fp)
    return ''
  endif
  let l:py = s:python_cmd()
  return l:py . ' ' . shellescape(g:yurii_pkm_python)
        \ . ' update_one ' . shellescape(a:target_fp)
        \ . ' ' . shellescape(l:root)
endfunction

function! s:reparent_down_children_for_sync(new_parent_fp, old_parent_fp) abort
  if !g:yurii_pkm_autosync | return | endif
  if !filereadable(g:yurii_pkm_python) | return | endif
  let l:root = s:get_pkm_root()
  if empty(l:root) || !filereadable(s:index_path(l:root))
    return
  endif
  let l:cmd = s:python_cmd() . ' ' . shellescape(g:yurii_pkm_python)
        \ . ' reparent_down_children ' . shellescape(a:new_parent_fp)
        \ . ' ' . shellescape(a:old_parent_fp)
        \ . ' ' . shellescape(l:root)
  let l:out = system(l:cmd)
  if v:shell_error
    echoerr substitute(l:out, '\n\+$', '', '')
    return
  endif
  checktime
endfunction

function! s:run_update_one_for(target_fp) abort
  let l:cmd = s:update_one_command(a:target_fp)
  if empty(l:cmd) | return | endif
  if has('job') && has('channel')
    call job_start(['/bin/sh', '-c', l:cmd], {
          \ 'exit_cb': function('s:update_one_done', [a:target_fp]),
          \ 'out_io':  'null',
          \ 'err_io':  'null',
          \ })
  else
    call system(l:cmd)
    checktime
  endif
endfunction

function! s:run_update_one_for_sync(target_fp, ...) abort
  let l:force = a:0 > 0 ? a:1 : 0
  let l:cmd = s:update_one_command(a:target_fp, l:force)
  if empty(l:cmd) | return | endif
  let l:out = system(l:cmd)
  if v:shell_error
    echoerr substitute(l:out, '\n\+$', '', '')
    return
  endif
  checktime
endfunction

function! s:write_current_and_sync_now() abort
  if !&modified | return | endif
  let l:file = expand('%:p')
  if empty(l:file)
    silent write
    return
  endif
  silent write
  call s:run_update_one_for_sync(l:file, 1)
endfunction

function! yurii_pkm#save_before_normal_jump(keys) abort
  if &buftype ==# '' && &modifiable && &modified
    let l:file = expand('%:p')
    if empty(l:file)
      echohl ErrorMsg | echom 'yurii_PKM: file name is empty; cannot auto-save before jump' | echohl None
      return
    endif
    try
      silent update
    catch
      echohl ErrorMsg | echom 'yurii_PKM: auto-save before jump failed: ' . v:exception | echohl None
      return
    endtry
    if s:is_markdown_file(l:file)
      call s:run_update_one_for_sync(l:file)
    endif
  endif
  execute 'normal! ' . a:keys
endfunction

function! s:update_one_done(target_fp, job, status) abort
  if expand('%:p') ==# a:target_fp
    call s:reload_current()
  else
    checktime
  endif
endfunction

" タイトル変更時は、旧タイトルと一致するリンク文字列だけ新タイトルへ置換する
function! s:run_retitle_links_for_title_change(target_fp, old_title, new_title) abort
  if a:old_title ==# a:new_title
    return
  endif
  if !filereadable(g:yurii_pkm_python)
    return
  endif
  let l:root = s:get_pkm_root()
  if empty(l:root) || !filereadable(s:index_path(l:root))
    return
  endif

  let l:py  = s:python_cmd()
  let l:cmd = l:py . ' ' . shellescape(g:yurii_pkm_python)
        \    . ' retitle_links ' . shellescape(a:target_fp)
        \    . ' ' . shellescape(l:root)
        \    . ' ' . shellescape(a:old_title)
        \    . ' ' . shellescape(a:new_title)

  if has('job') && has('channel')
    call job_start(['/bin/sh', '-c', l:cmd], {
          \ 'exit_cb': function('s:title_change_update_done'),
          \ 'out_io':  'null',
          \ 'err_io':  'null',
          \ })
  else
    call system(l:cmd)
    checktime
  endif
endfunction

function! s:title_change_update_done(job, status) abort
  call s:reload_current()
endfunction

" ---------------------------------------------------------------------------
" rename_link_text
" ---------------------------------------------------------------------------

function! yurii_pkm#rename_link_text_with_default(default) abort
  let l:link = yurii_pkm#get_link_under_cursor()
  if empty(l:link) || empty(get(l:link, 'target', ''))
    echo 'No link under cursor'
    return
  endif

  let l:new_text = input('new link text: ', a:default)
  if empty(l:new_text)
    echo 'Cancelled'
    return
  endif

  let l:line = getline('.')
  let l:start = l:link.startcol - 1
  let l:raw_end = l:start + strlen(l:link.raw)
  let l:new_raw = '[' . l:new_text . '](' . l:link.target . ')'
  call setline('.', strpart(l:line, 0, l:start) . l:new_raw . strpart(l:line, l:raw_end))
  call cursor(line('.'), l:start + 2)
endfunction

function! yurii_pkm#rename_link_text(args) abort
  let l:link = yurii_pkm#get_link_under_cursor()
  if empty(l:link) || empty(get(l:link, 'target', ''))
    echo 'No link under cursor'
    return
  endif
  let l:default = a:args ==# '' ? l:link.text : a:args
  call yurii_pkm#rename_link_text_with_default(l:default)
endfunction

" ---------------------------------------------------------------------------
" rename_title (:NT)
" ---------------------------------------------------------------------------

function! yurii_pkm#rename_title_with_default(default) abort
  let l:old_title = yurii_pkm#current_title()
  let l:title = input('new title: ', a:default)

  if empty(l:title)
    echo 'Cancelled'
    return
  endif

  let l:lines = getline(1, '$')
  let l:yaml_start = -1
  let l:yaml_end   = -1
  for l:i in range(len(l:lines))
    if l:lines[l:i] ==# '---'
      if l:yaml_start < 0
        let l:yaml_start = l:i
      else
        let l:yaml_end = l:i
        break
      endif
    endif
  endfor

  if l:yaml_start == 0 && l:yaml_end > 0
    let l:done = 0
    for l:i in range(l:yaml_start + 1, l:yaml_end - 1)
      if l:lines[l:i] =~# '^title:\s*'
        let l:lines[l:i] = 'title: ' . l:title
        let l:done = 1
        break
      endif
    endfor
    if !l:done
      call insert(l:lines, 'title: ' . l:title, l:yaml_start + 1)
    endif
  else
    let l:header = ['---', 'time: ' . yurii_pkm#timestamp_yaml(),
          \ 'title: ' . l:title, '---', '']
    let l:lines = l:header + l:lines
  endif

  " H1 も更新
  let l:found_h1 = 0
  for l:i in range(len(l:lines))
    if l:lines[l:i] =~# '^#\s\+'
      let l:lines[l:i] = '# ' . l:title
      let l:found_h1 = 1
      break
    endif
  endfor
  if !l:found_h1
    call add(l:lines, '# ' . l:title)
  endif

  call setline(1, l:lines)
  if len(l:lines) < line('$')
    execute (len(l:lines) + 1) . ',$delete _'
  endif
  write
  call yurii_pkm#clear_title_cache()
  call s:run_retitle_links_for_title_change(expand('%:p'), l:old_title, l:title)
endfunction

function! yurii_pkm#rename_title(args) abort
  let l:default = a:args ==# '' ? yurii_pkm#current_title() : a:args
  call yurii_pkm#rename_title_with_default(l:default)
endfunction

" ---------------------------------------------------------------------------
" create_note (internal)
" ---------------------------------------------------------------------------

function! yurii_pkm#create_note(prefix, title, open_after, insert_mode) abort
  let l:root = yurii_pkm#ensure_root_and_index()
  if empty(l:root)
    return {}
  endif
  let l:dir = expand('%:p:h')
  if empty(l:dir)
    let l:dir = l:root
  endif
  let l:fname = a:prefix . '_' . yurii_pkm#timestamp_filename() . '.md'
  let l:file  = l:dir . s:sep() . l:fname
  if filereadable(l:file)
    echoerr 'File already exists: ' . l:file
    return {}
  endif

  let l:parent_file  = expand('%:p')
  let l:parent_title = yurii_pkm#current_title()

  if a:insert_mode ==# 'branch' && s:structural_link_append_line() <= 0
    echoerr 'yurii_PKM: Child: section not found'
    return {}
  endif

  let l:tmpl = yurii_pkm#note_template(a:title, a:prefix)
  if filereadable(l:parent_file)
    let l:parent_link = s:make_link_from_dir(l:parent_file, l:parent_title, l:dir)
    let l:up_idx = s:find_section_index_in_lines(l:tmpl, 'up')
    if l:up_idx >= 0
      call insert(l:tmpl, l:parent_link, l:up_idx + 1)
    else
      call insert(l:tmpl, l:parent_link, len(l:tmpl) - 1)
    endif
  endif
  call writefile(l:tmpl, l:file)

  let l:link = yurii_pkm#make_link(l:file, a:title)
  let l:save_ai = &autoindent
  let l:save_si = &smartindent
  setlocal noautoindent nosmartindent
  if a:insert_mode ==# 'branch'
    let l:ins = s:structural_link_append_line()
    call append(l:ins, l:link)
    silent write
    call s:run_update_one_for_sync(expand('%:p'))
  elseif a:insert_mode ==# 'cursor'
    call append(line('.'), l:link)
    silent write
    call s:run_update_one_for_sync(expand('%:p'))
  endif
  let &autoindent = l:save_ai
  let &smartindent = l:save_si

  if a:open_after
    call yurii_pkm#push_history()
    execute 'edit ' . fnameescape(l:file)
    let &autoindent = l:save_ai
    let &smartindent = l:save_si

    startinsert
    call cursor(s:new_note_insert_line(), 9)
  endif

  return {'path': l:file, 'link': l:link}
endfunction


" ---------------------------------------------------------------------------
" :NC - New Child (常に C プレフィックス、タイトルのみ入力)
" ---------------------------------------------------------------------------

function! yurii_pkm#new_child(args) abort
  try
    let l:title = input('title: ', a:args)
  catch /^Vim:Interrupt$/
    echo 'Cancelled'
    return
  endtry
  if empty(l:title)
    let l:title = yurii_pkm#timestamp_filename()
  endif
  call yurii_pkm#create_note('C', l:title, 1, 'branch')
endfunction

" ---------------------------------------------------------------------------
" :NF / :NA - 現在ファイルと同ディレクトリに F_ / A_ ノートを作成し
"             現在ファイルの 本文末尾に追加する
" ---------------------------------------------------------------------------

function! yurii_pkm#new_here_typed(prefix) abort
  try
    let l:title = input('title: ')
  catch /^Vim:Interrupt$/
    echo 'Cancelled'
    return
  endtry
  if empty(l:title)
    let l:title = yurii_pkm#timestamp_filename()
  endif
  call yurii_pkm#create_note(a:prefix, l:title, 1, 'branch')
endfunction

" ---------------------------------------------------------------------------
" タイトル入力なし、o/b/h選択あり (nf / mm / nk 共通内部実装, Enter=ChildLast)

" ---------------------------------------------------------------------------


function! s:trim_blank_edges(lines) abort
  let l:out = copy(a:lines)
  while !empty(l:out) && trim(l:out[0]) ==# ''
    call remove(l:out, 0)
  endwhile
  while !empty(l:out) && trim(l:out[-1]) ==# ''
    call remove(l:out, -1)
  endwhile
  return l:out
endfunction

function! s:new_note_no_title(prefix) abort
  if s:pkm_format() ==# 'v2'
    call yurii_pkm#v2_new_child()
    return
  endif
  let l:parent_line  = line('.')
  let l:parent_path  = expand('%:p')
  let l:parent_dir   = expand('%:p:h')
  let l:parent_title = yurii_pkm#current_title()
  let l:filetype = toupper(a:prefix)
  let l:is_k = (l:filetype ==# 'K')
  let l:timestamp = yurii_pkm#timestamp_filename()
  let l:title = l:timestamp

  if l:is_k
    try
      let l:title = input('title: ')
    catch /^Vim:Interrupt$/
      echo 'Cancelled'
      return
    endtry
    if empty(l:title)
      let l:title = l:timestamp
    endif
  endif

  echon 'mode: (O)rphan (B)ack (H)=cursor Enter=ChildLast: '

  let l:char = getchar()
  redraw

  " Esc or Ctrl-C でキャンセル
  if l:char == 27 || l:char == 3
    echo 'Cancelled'
    return
  endif
  let l:mode = nr2char(l:char)

  let l:insert_at_cursor = 0
  let l:insert_at_down_end = 0
  let l:no_parent_link   = 0
  let l:reverse_link     = 0

  if l:mode =~? '^o$'
    let l:no_parent_link = 1
  elseif l:mode =~? '^b$'
    let l:reverse_link = 1
  elseif l:mode =~? '^h$'
    let l:insert_at_cursor = 1
  else
    let l:insert_at_down_end = 1
  endif

  let l:no_prefix_name = (l:filetype ==# 'N')
  let l:fname = l:is_k
        \ ? (l:timestamp . '.md')
        \ : (l:no_prefix_name ? (l:title . '.md') : (a:prefix . '_' . l:title . '.md'))
  let l:dir   = s:cwd_note_dir()
  let l:file  = s:join_path(l:dir, l:fname)
  let l:link  = s:make_link_from_dir(l:file, l:title, l:parent_dir)

  if !l:no_parent_link && !l:reverse_link && !l:insert_at_cursor && s:structural_link_append_line() <= 0
    echoerr 'yurii_PKM: Child: section not found'
    return
  endif

  if !l:no_parent_link && !l:reverse_link
    let l:save_ai = &autoindent
    let l:save_si = &smartindent
    setlocal noautoindent nosmartindent
    if l:insert_at_cursor
      if !s:link_already_present_in_branch(l:link)
        call append(l:parent_line, l:link)
      endif
    elseif l:insert_at_down_end
      call s:append_structural_link_to_buffer(l:link)
    else
      if a:prefix ==? 'N'
        let l:ins = s:structural_link_prepend_line()
        if !s:link_already_present_in_branch(l:link)
          call append(l:ins, l:link)
        endif
      else
        call s:append_structural_link_to_buffer(l:link)
      endif
    endif
    let &autoindent = l:save_ai
    let &smartindent = l:save_si
    silent noautocmd write
  endif

  let l:parent_link_lines = s:parent_link_lines(l:parent_path, l:parent_title, l:dir)

  if l:reverse_link
    if l:is_k
      let l:content = s:k_note_template(l:title)
      let l:cursor_line = 7
    else
      " b モード: 新ノートの Child に現在ノートへのリンクを入れる
      " # title / (空) / Parent / Child / [親リンク] / Back / [index]
      let l:content = [
            \ '---',
            \ 'time: ' . yurii_pkm#timestamp_yaml(),
            \ 'title: ' . l:title,
            \ '---',
            \ '',
            \ '# ' . l:title,
            \ '',
            \ '',
            \ '',
            \ s:canonical_section_title('up'),
            \ s:canonical_section_title('down'),
          \ ] + l:parent_link_lines + [
            \ s:canonical_section_title('backlink'),
            \ '[Index](index.md)' ]
    endif
    if !l:is_k
      let l:cursor_line = 8
    endif
  elseif l:is_k
    " nk の h/Enter/o モード: 見出しのみ作成
    let l:content = s:k_note_template(l:title)
    let l:cursor_line = 7
  else
    " mm/nf の h/Enter/o モード: 従来どおり
    let l:content = [
          \ '---',
          \ 'time: ' . yurii_pkm#timestamp_yaml(),
          \ 'title: ' . l:title,
          \ '---',
          \ '',
          \ '# ' . l:title,
          \ '',
          \ '',
          \ '',
          \ s:canonical_section_title('up'),
        \ ] + l:parent_link_lines + [
          \ s:canonical_section_title('down'),
          \ s:canonical_section_title('backlink'),
          \ '[Index](index.md)' ]
    let l:cursor_line = 8
  endif

  call writefile(l:content, l:file)

  " 通常モード: 新ノート作成前はリンク先が未存在のため、作成後に親の本文リンクを同期する
  " mm/nf/nk の体感速度を優先し、重い update_one は非同期で走らせる。
  if !l:no_parent_link && !l:reverse_link
    call s:run_update_one_for(expand('%:p'))
  endif

  " bモード: 新ノートの Child を元に Parent/BackLink を同期
  if l:reverse_link
    call s:run_update_one_for(l:file)
  endif

  if &modified
    try
      silent noautocmd write
    catch
      echohl ErrorMsg
      echom 'Error: could not save current buffer; new note was created but not opened: ' . l:fname
      echohl None
      return
    endtry
  endif

  call yurii_pkm#push_history()
  execute 'edit ' . fnameescape(l:file)

  startinsert
  call cursor(l:cursor_line, 9)
endfunction

" ---------------------------------------------------------------------------
" ビジュアル選択範囲を新ノートに切り出す (mm / nf / nk のビジュアル版)
"
" 動作:
"   - 選択範囲のテキストを取得して削除（元ファイルから cut）
"   - 新ノートファイルに YAML + # title + 空行 + 切り出しテキスト を書き込む
"   - bモードのときは選択テキストの代わりにリンクだけ残す（本文なし）
"   - 画面（カーソル位置・スクロール）は元のまま動かさない
" ---------------------------------------------------------------------------

function! s:visual_new_note(prefix, mode, ...) abort
  " ビジュアル選択の範囲を取得（'< と '> マーク）
  let l:vstart = line("'<")
  let l:vend   = line("'>")
  if l:vstart <= 0 || l:vend <= 0 || l:vstart > l:vend
    echo 'No visual selection'
    return
  endif

  let l:sel_lines = getline(l:vstart, l:vend)

  let l:parent_path  = expand('%:p')
  let l:parent_dir   = expand('%:p:h')
  let l:parent_title = yurii_pkm#current_title()
  let l:dir          = s:cwd_note_dir()

  let l:timestamp = yurii_pkm#timestamp_filename()
  let l:title = (a:0 >= 1 && !empty(a:1)) ? a:1 : l:timestamp
  let l:filetype = toupper(a:prefix)
  let l:no_prefix_name = (l:filetype ==# 'N')
  let l:fname = (l:filetype ==# 'K')
        \ ? (l:timestamp . '.md')
        \ : (l:no_prefix_name ? (l:title . '.md') : (a:prefix . '_' . l:title . '.md'))
  let l:file  = s:join_path(l:dir, l:fname)
  let l:parent_link_lines = s:parent_link_lines(l:parent_path, l:parent_title, l:dir)
  let l:link_to_new      = s:make_link_from_dir(l:file, l:title, l:parent_dir)

  let l:is_b = (a:mode ==? 'b')
  let l:is_k = (a:prefix ==? 'K')

  " 新ファイルの内容を組み立てる
  if l:is_b
    " bモード: 選択テキストは新ファイルに移す、Back セクションに親リンク
    if l:is_k
      let l:content = s:k_note_template_with_down(l:title, l:sel_lines)
    else
      let l:content = [
            \ '---',
            \ 'time: ' . yurii_pkm#timestamp_yaml(),
            \ 'title: ' . l:title,
            \ '---',
            \ '',
            \ '# ' . l:title,
            \ '',
            \ '',
            \ '',
            \ s:canonical_section_title('up'),
          \ ] + l:parent_link_lines + [
            \ s:canonical_section_title('down'),
            \ s:canonical_section_title('backlink'),
            \ '[Index](index.md)' ]
    endif
    if !l:is_k
      " 選択テキストを本文（Back の直前）に挿入
      let l:back_idx = s:find_section_index_in_lines(l:content, 'back')
      " Back の前に空行 + 選択テキストを差し込む
      let l:insert_pos = l:back_idx
      call extend(l:content, l:sel_lines, l:insert_pos)
    endif
  else
    " o / Enter モード: 本文に選択テキストを配置
    if l:is_k
      let l:content = s:k_note_template_with_down(l:title, l:sel_lines)
    else
      let l:content = [
            \ '---',
            \ 'time: ' . yurii_pkm#timestamp_yaml(),
            \ 'title: ' . l:title,
            \ '---',
            \ '',
            \ '# ' . l:title,
            \ '' ]
      call extend(l:content, l:sel_lines)
      call add(l:content, '')
      call add(l:content, '')
      call add(l:content, '')
      call add(l:content, s:canonical_section_title('up'))
      call extend(l:content, l:parent_link_lines)
      call add(l:content, s:canonical_section_title('down'))
      call add(l:content, s:canonical_section_title('backlink'))
      call add(l:content, '[Index](index.md)')
    endif
  endif

  call writefile(l:content, l:file)

  " ---- 元ファイルの選択範囲を置き換える ----
  " スクロール位置・カーソルを保存
  let l:save_view = winsaveview()
  let l:save_pos  = getpos('.')

  let l:save_ai = &autoindent
  let l:save_si = &smartindent
  setlocal noautoindent nosmartindent

  " 選択範囲をリンク1行に置き換える（全モード共通）
  execute l:vstart . ',' . l:vend . 'delete _'
  call append(l:vstart - 1, l:link_to_new)
  " カーソルはリンク行の次行（元の選択終端の次）
  let l:cursor_line = l:vstart + 1

  if l:is_b
    " bモード: 親の Back セクション直後にも逆リンクを追記
    let l:parent_fp = l:parent_path
    if filereadable(l:parent_fp)
      let l:plines = readfile(l:parent_fp)
      let l:back_idx2 = -1
      for l:i in range(0, len(l:plines) - 1)
        if s:is_section_header_text(l:plines[l:i], 'back')
          let l:back_idx2 = l:i
          break
        endif
      endfor
      if index(l:plines, l:link_to_new) < 0
        if l:back_idx2 < 0
          call add(l:plines, '')
          call add(l:plines, s:canonical_section_title('backlink'))
          call add(l:plines, '[Index](index.md)')
          let l:back_idx2 = len(l:plines) - 2
        endif
        call insert(l:plines, l:link_to_new, l:back_idx2 + 1)
        call writefile(l:plines, l:parent_fp)
        call s:run_update_one_for(l:parent_fp)
      endif
    endif
  endif

  let &autoindent = l:save_ai
  let &smartindent = l:save_si

  " スクロール位置は保持、カーソルはリンク行の次行へ
  call winrestview(l:save_view)
  let l:cursor_line = min([l:cursor_line, line('$')])
  call cursor(l:cursor_line, 1)

  silent noautocmd write
  call s:reparent_down_children_for_sync(l:file, l:parent_path)
  call s:run_update_one_for(expand('%:p'))
  call s:run_update_one_for(l:file)

  redraw | echon 'Created: ' . l:fname
endfunction

" ビジュアル選択から nf / mm / nk を呼ぶエントリポイント
function! yurii_pkm#visual_new_quick_no_title() abort
  echo 'prefix (a-z): '
  let l:char = getchar()
  redraw
  if l:char == 27 || l:char == 3
    echo 'Cancelled'
    return
  endif
  let l:ch = nr2char(l:char)
  if l:ch !~# '^[a-zA-Z]$'
    echo 'Cancelled'
    return
  endif
  call s:visual_select_mode(toupper(l:ch))
endfunction

function! yurii_pkm#visual_new_prefix_note(prefix) abort
  call s:visual_select_mode(a:prefix)
endfunction

function! s:visual_select_mode(prefix) abort
  let l:title = ''
  if a:prefix ==? 'K'
    try
      let l:title = input('title: ')
    catch /^Vim:Interrupt$/
      echo 'Cancelled'
      return
    endtry
  endif

  echon 'mode: (O)rphan (B)ack (H)=cursor Enter=ChildLast: '

  let l:char = getchar()
  redraw
  if l:char == 27 || l:char == 3
    echo 'Cancelled'
    return
  endif
  let l:mode = nr2char(l:char)
  if a:prefix ==? 'K'
    call s:visual_new_note(a:prefix, l:mode, l:title)
  else
    call s:visual_new_note(a:prefix, l:mode)
  endif
endfunction

" nf用: prefix入力 → o/b/h選択（Enter=ChildLast）

function! s:new_k_note_with_title() abort
  let l:title = input('title: ')
  if empty(l:title)
    echo 'Cancelled'
    return
  endif

  let l:fname = yurii_pkm#timestamp_filename() . '.md'
  let l:dir   = expand('%:p:h')
  let l:file  = l:dir . s:sep() . l:fname
  let l:link  = yurii_pkm#make_link(l:fname, l:title)

  let l:ins = s:structural_link_append_line()
  if l:ins <= 0
    echoerr 'yurii_PKM: Child: section not found'
    return
  endif
  let l:save_ai = &autoindent
  let l:save_si = &smartindent
  setlocal noautoindent nosmartindent
  call append(l:ins, l:link)
  let &autoindent = l:save_ai
  let &smartindent = l:save_si

  let l:content = s:k_note_template(l:title)
  call writefile(l:content, l:file)

  silent noautocmd write
  call s:run_update_one_for(expand('%:p'))

  call cursor(l:ins + 1, 1)
  redraw | echon 'Created: ' . l:fname
endfunction

function! yurii_pkm#new_quick_no_title() abort
  echo 'prefix (a-z): '
  let l:char = getchar()
  redraw
  if l:char == 27 || l:char == 3
    echo 'Cancelled'
    return
  endif
  let l:ch = nr2char(l:char)
  if l:ch !~# '^[a-zA-Z]$'
    echo 'Cancelled'
    return
  endif
  call s:new_note_no_title(toupper(l:ch))
endfunction

" mm / nk用: prefix固定 → o/b/h選択（Enter=ChildLast）

function! yurii_pkm#new_prefix_note(prefix) abort
  call s:new_note_no_title(a:prefix)
endfunction

" ---------------------------------------------------------------------------
" :NQ - Quick new child (旧 QuickNewChildWithMode に忠実)
"   1. プレフィックス1文字入力（即時確定）
"   2. タイトル入力
"   3. モード選択: (O)rphan / (B)ack / (H)=cursor / Enter=ChildLast

" ---------------------------------------------------------------------------

function! yurii_pkm#new_quick(args) abort
  if s:pkm_format() ==# 'v2'
    call yurii_pkm#v2_new_child()
    return
  endif
  let l:parent_bufnr = bufnr('%')
  let l:parent_line = line('.')
  let l:parent_file  = expand('%:t')
  let l:parent_title = yurii_pkm#current_title()

  echo 'prefix (a-z): '
  let l:raw = getchar()
  redraw
  if l:raw == 27 || l:raw == 3
    echo 'Cancelled'
    return
  endif
  let l:char = nr2char(l:raw)
  if l:char !~# '^[a-zA-Z]$'
    echo 'Cancelled'
    return
  endif
  let l:prefix = toupper(l:char)

  let l:title = input('title: ', a:args)

  echon "\nmode: (O)rphan (B)ack (H)=cursor Enter=ChildLast: "

  let l:raw2 = getchar()
  redraw
  if l:raw2 == 27 || l:raw2 == 3
    echo 'Cancelled'
    return
  endif
  let l:mode = nr2char(l:raw2)

  let l:insert_at_cursor = 0
  let l:insert_at_down_end = 0
  let l:no_parent_link   = 0
  let l:reverse_link     = 0

  if l:mode =~? '^o$'
    let l:no_parent_link = 1
  elseif l:mode =~? '^b$'
    let l:reverse_link = 1
  elseif l:mode =~? '^h$'
    let l:insert_at_cursor = 1
  else
    let l:insert_at_down_end = 1
  endif

  if empty(l:title)
    let l:title = yurii_pkm#timestamp_filename()
  endif

  let l:fname = l:prefix . '_' . yurii_pkm#timestamp_filename() . '.md'
  let l:dir   = expand('%:p:h')
  let l:file  = l:dir . s:sep() . l:fname
  let l:link = yurii_pkm#make_link(l:fname, l:title)

  if !l:no_parent_link && !l:reverse_link && !l:insert_at_cursor && s:structural_link_append_line() <= 0
    echoerr 'yurii_PKM: Child: section not found'
    return
  endif

  if !l:no_parent_link && !l:reverse_link
    let l:save_ai = &autoindent
    let l:save_si = &smartindent
    setlocal noautoindent nosmartindent
    if l:insert_at_cursor
      call append(l:parent_line, l:link)
    elseif l:insert_at_down_end
      let l:ins = s:structural_link_append_line()
      call append(l:ins, l:link)
    else
      let l:ins = s:structural_link_append_line()
      call append(l:ins, l:link)
    endif
    let &autoindent = l:save_ai
    let &smartindent = l:save_si
    silent noautocmd write
  endif

  let l:parent_link_lines = s:parent_link_lines(l:parent_file, l:parent_title, l:dir)
  let l:is_k = (l:prefix ==? 'K')

  if l:reverse_link
    if l:is_k
      let l:content = s:k_note_template(l:title)
      let l:cursor_line = 7
    else
      let l:content = [
            \ '---',
            \ 'time: ' . yurii_pkm#timestamp_yaml(),
            \ 'title: ' . l:title,
            \ '---',
            \ '',
            \ '# ' . l:title,
            \ '',
            \ '',
            \ '',
            \ s:canonical_section_title('up'),
          \ ] + l:parent_link_lines + [
            \ s:canonical_section_title('down'),
            \ s:canonical_section_title('backlink'),
            \ '[Index](index.md)' ]
    endif
    if !l:is_k
      let l:cursor_line = 8
    endif
  elseif l:is_k
    let l:content = s:k_note_template(l:title)
    let l:cursor_line = 7
  else
    let l:content = [
          \ '---',
          \ 'time: ' . yurii_pkm#timestamp_yaml(),
          \ 'title: ' . l:title,
          \ '---',
          \ '',
          \ '# ' . l:title,
          \ '',
          \ '',
          \ '',
          \ s:canonical_section_title('up'),
        \ ] + l:parent_link_lines + [
          \ s:canonical_section_title('down'),
          \ s:canonical_section_title('backlink'),
          \ '[Index](index.md)' ]
    let l:cursor_line = 8
  endif

  call writefile(l:content, l:file)

  " 通常モード: 新ノート作成前はリンク先が未存在のため、作成後に親の本文リンクを同期する
  " mm/nf/nk の体感速度を優先し、重い update_one は非同期で走らせる。
  if !l:no_parent_link && !l:reverse_link
    call s:run_update_one_for(expand('%:p'))
  endif

  " bモード: 親ファイルの Back セクション直後に新ノートへのリンクを追記してsync
  if l:reverse_link
    " ディスクとバッファの不一致を防ぐため先に保存
    if &modified
      silent noautocmd write
    endif
    let l:new_link = yurii_pkm#make_link(l:fname, l:title)
    let l:parent_fp = l:dir . s:sep() . l:parent_file
    if filereadable(l:parent_fp)
      let l:plines = readfile(l:parent_fp)
      let l:back_idx = -1
      for l:i in range(0, len(l:plines) - 1)
        if s:is_section_header_text(l:plines[l:i], 'back')
          let l:back_idx = l:i
          break
        endif
      endfor
      if index(l:plines, l:new_link) < 0
        if l:back_idx < 0
          call add(l:plines, '')
          call add(l:plines, s:canonical_section_title('backlink'))
          call add(l:plines, '[Index](index.md)')
          let l:back_idx = len(l:plines) - 2
        endif
        call insert(l:plines, l:new_link, l:back_idx + 1)
        call writefile(l:plines, l:parent_fp)
        call s:run_update_one_for(l:parent_fp)
      endif
    endif
  endif

  if &modified
    try
      silent noautocmd write
    catch
      echohl ErrorMsg
      echom 'Error: could not save current buffer; new note was created but not opened: ' . l:fname
      echohl None
      return
    endtry
  endif

  call yurii_pkm#push_history()
  execute 'edit ' . fnameescape(l:file)

  startinsert
  call cursor(l:cursor_line, 9)
endfunction


" ---------------------------------------------------------------------------
" :CA - Create Atomic note (本文末尾に追加、新ファイルを開く)
" ---------------------------------------------------------------------------

function! yurii_pkm#create_atomic(args) abort
  let l:prefix = g:yurii_pkm_default_atomic_prefix
  let l:prefix = toupper(input('prefix [' . l:prefix . ']: ', l:prefix))
  if empty(l:prefix) | let l:prefix = g:yurii_pkm_default_atomic_prefix | endif
  let l:title = input('title: ', a:args)
  if empty(l:title) | echo 'Cancelled' | return | endif
  call yurii_pkm#create_note(l:prefix, l:title, 1, 'branch')
endfunction


" ---------------------------------------------------------------------------
" :BC - Add from clipboard before Back
" ---------------------------------------------------------------------------

function! yurii_pkm#add_from_clipboard(...) abort
  if s:pkm_format() ==# 'v2'
    call yurii_pkm#v2_add_link(a:0 > 0 ? a:1 : '')
    return
  endif
  let l:clipboard = s:clipboard_text()
  if empty(l:clipboard)
    echo 'Error: clipboard is empty'
    return
  endif

  let l:insert_at_cursor = 0
  for l:arg in a:000
    if l:arg ==# 'here'
      let l:insert_at_cursor = 1
    endif
  endfor

  let l:links = []
  for l:raw in split(l:clipboard, "\n")
    let l:target = s:extract_target(l:raw)
    if empty(l:target)
      continue
    endif
    let l:path = yurii_pkm#resolve_link(l:target)
    if !filereadable(l:path)
      echo 'Warning: not found: ' . l:target
      continue
    endif
    let l:link = s:link_from_target(l:target)
    if !empty(l:link)
      call add(l:links, l:link)
    endif
  endfor

  if empty(l:links)
    echo 'Error: no valid links in clipboard'
    return
  endif

  if l:insert_at_cursor
    let l:ins = line('.')
    for l:lk in reverse(copy(l:links))
      call append(l:ins, l:lk)
    endfor
  else
    let l:ins = s:structural_link_append_line()
    if l:ins <= 0
      echo 'Error: child section not found'
      return
    endif
    for l:lk in l:links
      call append(l:ins, l:lk)
      let l:ins += 1
    endfor
  endif
  call s:realtime_sync_apply()
  silent write
  echo 'Added ' . len(l:links) . ' link(s)'
endfunction

function! yurii_pkm#paste_clipboard_link_here() abort
  let l:clipboard = s:clipboard_text()
  if empty(l:clipboard)
    echo 'Error: clipboard is empty'
    return
  endif

  let l:links = []
  for l:raw in split(l:clipboard, "\n")
    let l:target = s:extract_target(l:raw)
    if empty(l:target)
      continue
    endif
    " md ファイルは存在チェックあり、非md（.svc 等）は存在チェックなしでリンク化
    if s:is_markdown_target(l:target)
      let l:path = yurii_pkm#resolve_link(l:target)
      if !filereadable(l:path)
        echo 'Warning: not found: ' . l:target
        continue
      endif
    endif
    let l:link = s:link_from_target(l:target)
    if !empty(l:link)
      call add(l:links, l:link)
    endif
  endfor

  if empty(l:links)
    echo 'Error: no valid links in clipboard'
    return
  endif

  let l:ins = line('.')
  for l:lk in reverse(copy(l:links))
    call append(l:ins, l:lk)
  endfor
  call s:write_current_and_sync_now()
endfunction

function! yurii_pkm#add_clipboard_to_branch() abort
  if s:pkm_format() ==# 'v2'
    call yurii_pkm#v2_add_link()
    return
  endif
  let l:clipboard = s:clipboard_text()
  if empty(l:clipboard)
    echo 'Error: clipboard is empty'
    return
  endif

  let l:links = []
  for l:raw in split(l:clipboard, "\n")
    let l:target = s:extract_target(l:raw)
    if empty(l:target)
      continue
    endif
    let l:path = yurii_pkm#resolve_link(l:target)
    if !filereadable(l:path)
      echo 'Warning: not found: ' . l:target
      continue
    endif
    let l:link = s:link_from_target(l:target)
    if !empty(l:link)
      call add(l:links, l:link)
    endif
  endfor

  if empty(l:links)
    echo 'Error: no valid links in clipboard'
    return
  endif

  let l:added = 0
  for l:lk in l:links
    if s:append_link_to_buffer_section('up', l:lk)
      let l:added += 1
    endif
  endfor
  call s:realtime_sync_apply()
  silent write
  echo 'Parent added ' . l:added . ' link(s)'
endfunction


" za: ca と同じ そっちにとって 側だが、関係は常に既定の「ノート」固定
" （ピッカーも「相手にも書くか」の質問も出さない）。
function! yurii_pkm#add_clipboard_before_up_note() abort
  if s:pkm_format() ==# 'v2'
    call yurii_pkm#v2_add_link('', 'ノート', 1)
    return
  endif
  call yurii_pkm#add_clipboard_before_up()
endfunction

" \ca: ca と同じ そっちにとって 側だが、括弧が付く側が逆。今開いているノート
" 側を `(ラベル)` にし、相手側にはその場で生のラベルを書く（質問なし）。
function! yurii_pkm#add_clipboard_before_up_reverse() abort
  if s:pkm_format() ==# 'v2'
    call yurii_pkm#v2_add_link('', '', 1, 1)
    return
  endif
  call yurii_pkm#add_clipboard_before_up()
endfunction

function! yurii_pkm#add_clipboard_before_up() abort
  if s:pkm_format() ==# 'v2'
    call yurii_pkm#v2_add_link('', '', 1)  " ca: そっちにとって 側へ
    return
  endif
  let l:current_file = expand('%:p')
  let l:current_title = yurii_pkm#current_title()

  let l:clipboard = s:clipboard_text()
  if empty(l:clipboard)
    echo 'Error: clipboard is empty'
    return
  endif

  let l:links = []
  let l:targets = []
  for l:raw in split(l:clipboard, "\n")
    let l:target = s:extract_target(l:raw)
    if empty(l:target)
      continue
    endif
    let l:path = yurii_pkm#resolve_link(l:target)
    if !filereadable(l:path)
      echo 'Warning: not found: ' . l:target
      continue
    endif
    let l:link = s:link_from_clipboard_raw(l:raw)
    if !empty(l:link)
      call add(l:links, l:link)
      call add(l:targets, l:target)
    endif
  endfor

  if empty(l:links)
    echo 'Error: no valid links in clipboard'
    return
  endif

  let l:down_added = 0
  let l:up_added = 0
  for l:i in range(0, len(l:links) - 1)
    let l:link = l:links[l:i]
    let l:target_path = yurii_pkm#resolve_link(l:targets[l:i])

    if s:append_link_to_buffer_section('down', l:link)
      let l:down_added += 1
    endif

    let l:target_lines = readfile(l:target_path)
    let l:current_link = s:make_link_from_dir(
          \ l:current_file, l:current_title, fnamemodify(l:target_path, ':h'))
    let l:up_result = s:add_link_to_lines_section(l:target_lines, 'up', l:current_link)
    if l:up_result.added
      call writefile(l:up_result.lines, l:target_path)
      let l:up_added += 1
    endif
  endfor
  silent write
  echo 'ca: Child added ' . l:down_added . ', reciprocal Parent added ' . l:up_added
endfunction

function! yurii_pkm#add_clipboard_to_top() abort
  let l:clipboard = s:clipboard_text()
  if empty(l:clipboard)
    echo 'Error: clipboard is empty'
    return
  endif

  let l:links = []
  for l:raw in split(l:clipboard, "\n")
    let l:target = s:extract_target(l:raw)
    if empty(l:target)
      continue
    endif
    let l:path = yurii_pkm#resolve_link(l:target)
    if !filereadable(l:path)
      echo 'Warning: not found: ' . l:target
      continue
    endif
    let l:link = s:link_from_target(l:target)
    if !empty(l:link)
      call add(l:links, l:link)
    endif
  endfor

  if empty(l:links)
    echo 'Error: no valid links in clipboard'
    return
  endif

  let l:ins = s:body_top_insert_line()
  for l:lk in l:links
    call append(l:ins, l:lk)
    let l:ins += 1
  endfor
  silent write
endfunction

function! yurii_pkm#linkify_filename_under_cursor() abort
  let l:word = expand('<cfile>')
  if empty(l:word)
    echo 'Error: no filename under cursor'
    return
  endif
  let l:path = yurii_pkm#resolve_link(l:word)
  if !filereadable(l:path)
    echo 'Error: not found: ' . l:word
    return
  endif
  let l:link = s:link_from_target(l:word)
  if empty(l:link)
    echo 'Error: failed to build link'
    return
  endif
  let l:line = getline('.')
  let l:start = col('.')
  let l:idx = match(l:line, '\V' . escape(l:word, '\'))
  if l:idx < 0
    echo 'Error: filename text not found on line'
    return
  endif
  let l:newline = strpart(l:line, 0, l:idx) . l:link . strpart(l:line, l:idx + strlen(l:word))
  call setline('.', l:newline)
endfunction

function! s:replace_visual_selection_with_link(link, is_linewise, sline, eline, scol, ecol, lines) abort
  if a:is_linewise
    call setline(a:sline, a:link)
    if a:eline > a:sline
      execute (a:sline + 1) . ',' . a:eline . 'delete _'
    endif
  elseif len(a:lines) == 1
    let l:line = a:lines[0]
    let l:start_char = charidx(l:line, a:scol - 1)
    let l:end_char = charidx(l:line, a:ecol - 1) + 1
    let l:newline = strcharpart(l:line, 0, l:start_char) . a:link . strcharpart(l:line, l:end_char)
    call setline(a:sline, l:newline)
  else
    let l:first_start_char = charidx(a:lines[0], a:scol - 1)
    let l:last_end_char = charidx(a:lines[-1], a:ecol - 1) + 1
    let l:prefix = strcharpart(a:lines[0], 0, l:first_start_char)
    let l:suffix = strcharpart(a:lines[-1], l:last_end_char)
    call setline(a:sline, l:prefix . a:link . l:suffix)
    if a:eline > a:sline
      execute (a:sline + 1) . ',' . a:eline . 'delete _'
    endif
  endif
endfunction

function! yurii_pkm#linkify_selection_new_note() abort range

  let l:vmode = visualmode()
  let l:is_linewise = (l:vmode ==# 'V')

  let l:sline = line("'<")
  let l:eline = line("'>")
  let l:scol  = col("'<")
  let l:ecol  = col("'>")

  if l:sline <= 0 || l:eline <= 0
    echo 'No visual selection'
    return
  endif

  if l:sline > l:eline || (l:sline == l:eline && l:scol > l:ecol)
    let [l:sline, l:eline] = [l:eline, l:sline]
    let [l:scol, l:ecol] = [l:ecol, l:scol]
  endif

  let l:lines = getline(l:sline, l:eline)
  if empty(l:lines)
    echo 'No visual selection'
    return
  endif

  if l:is_linewise
    let l:selected = join(l:lines, "\n")
  elseif len(l:lines) == 1
    let l:start_char = charidx(l:lines[0], l:scol - 1)
    let l:end_char = charidx(l:lines[0], l:ecol - 1) + 1
    let l:selected = strcharpart(l:lines[0], l:start_char, l:end_char - l:start_char)
  else
    let l:selected_lines = copy(l:lines)
    let l:first_start_char = charidx(l:selected_lines[0], l:scol - 1)
    let l:last_end_char = charidx(l:selected_lines[-1], l:ecol - 1) + 1
    let l:selected_lines[0] = strcharpart(l:selected_lines[0], l:first_start_char)
    let l:selected_lines[-1] = strcharpart(l:selected_lines[-1], 0, l:last_end_char)
    let l:selected = join(l:selected_lines, "\n")
  endif

  let l:text = trim(substitute(l:selected, '\n\+', ' ', 'g'))
  if empty(l:text)
    echo 'No visual selection'
    return
  endif

  " 既存ファイル名が選択されている場合はそのままリンク化する
  " - 非md: [filename.ext](filename.ext)
  " - md: タイトル(取得できなければ拡張子なしファイル名)をリンク文字列に使う
  if s:is_filename_target(l:text)
    let l:link = s:link_from_target(l:text)
    call s:replace_visual_selection_with_link(l:link, l:is_linewise, l:sline, l:eline, l:scol, l:ecol, l:lines)
    return
  endif

  let l:target = yurii_pkm#timestamp_filename() . '.md'
  let l:new_file = expand('%:p:h') . s:sep() . l:target
  let l:parent_file = expand('%:p')
  let l:parent_title = yurii_pkm#current_title()
  let l:parent_link_lines = s:parent_link_lines(l:parent_file, l:parent_title, expand('%:p:h'))

  if !filereadable(l:new_file)
    if s:pkm_format() ==# 'v2'
      let l:new_content = [
            \ '---',
            \ 'time: ' . yurii_pkm#timestamp_yaml(),
            \ 'title: ' . l:text,
            \ '---',
            \ '',
            \ '# ' . l:text,
            \ '',
            \ '',
            \ '',
            \ s:v2_up_mark,
            \ ]
      if !empty(l:parent_link_lines)
        call add(l:new_content, 'ノート:')
        call extend(l:new_content, l:parent_link_lines)
      endif
      call add(l:new_content, s:v2_down_mark)
    else
      let l:new_content = [
            \ '---',
            \ 'time: ' . yurii_pkm#timestamp_yaml(),
            \ 'title: ' . l:text,
            \ '---',
            \ '',
            \ '# ' . l:text,
            \ '',
            \ '',
            \ '',
            \ s:canonical_section_title('up'),
            \ ] + l:parent_link_lines + [
            \ s:canonical_section_title('down'),
            \ s:canonical_section_title('backlink'),
            \ '[Index](index.md)'
            \ ]
    endif
    call writefile(l:new_content, l:new_file)

  endif

  let l:link = '[' . l:text . '](' . l:target . ')'
  call s:replace_visual_selection_with_link(l:link, l:is_linewise, l:sline, l:eline, l:scol, l:ecol, l:lines)
endfunction

" Backward compatibility: :LinkifySelection から呼ばれる既存関数名
function! yurii_pkm#linkify_selection() abort range
  return yurii_pkm#linkify_selection_new_note()
endfunction

function! yurii_pkm#linkify_selection_from_clipboard() abort range
  let l:vmode = visualmode()
  let l:is_linewise = (l:vmode ==# 'V')

  let l:sline = line("'<")
  let l:eline = line("'>")
  let l:scol  = col("'<")
  let l:ecol  = col("'>")


  if l:sline <= 0 || l:eline <= 0
    echo 'No visual selection'
    return
  endif

  if l:sline > l:eline || (l:sline == l:eline && l:scol > l:ecol)
    let [l:sline, l:eline] = [l:eline, l:sline]
    let [l:scol, l:ecol] = [l:ecol, l:scol]
  endif

  let l:lines = getline(l:sline, l:eline)
  if empty(l:lines)
    echo 'No visual selection'
    return
  endif

  if l:is_linewise
    let l:selected = join(l:lines, "\n")
  elseif len(l:lines) == 1
    let l:start_char = charidx(l:lines[0], l:scol - 1)
    let l:end_char = charidx(l:lines[0], l:ecol - 1) + 1
    let l:selected = strcharpart(l:lines[0], l:start_char, l:end_char - l:start_char)
  else
    let l:selected_lines = copy(l:lines)
    let l:first_start_char = charidx(l:selected_lines[0], l:scol - 1)
    let l:last_end_char = charidx(l:selected_lines[-1], l:ecol - 1) + 1
    let l:selected_lines[0] = strcharpart(l:selected_lines[0], l:first_start_char)
    let l:selected_lines[-1] = strcharpart(l:selected_lines[-1], 0, l:last_end_char)
    let l:selected = join(l:selected_lines, "\n")
  endif

  let l:text = trim(substitute(l:selected, '\n\+', ' ', 'g'))
  if empty(l:text)
    echo 'No visual selection'
    return
  endif

  let l:clipboard = s:clipboard_text()
  if empty(l:clipboard)
    return
  endif

  let l:targets = s:extract_targets_from_clipboard(l:clipboard)
  if empty(l:targets)
    return
  endif

  let l:target = ''
  for l:item in l:targets
    if s:is_filename_target(l:item)
      let l:target = l:item
      break
    endif
  endfor
  if empty(l:target)
    return
  endif

  if s:is_markdown_target(l:target)
    let l:path = yurii_pkm#resolve_link(l:target)
    if !filereadable(l:path)
      return
    endif
  endif

  let l:display_target = s:display_target_from_current_dir(l:target)
  let l:link = '[' . l:text . '](' . l:display_target . ')'
  call s:replace_visual_selection_with_link(l:link, l:is_linewise, l:sline, l:eline, l:scol, l:ecol, l:lines)
  call s:write_current_and_sync_now()
endfunction


" ---------------------------------------------------------------------------
" :YN - Yank Note name
" ---------------------------------------------------------------------------
" ---------------------------------------------------------------------------
" :YN - Yank Note name (拡張子なし)
" ---------------------------------------------------------------------------

function! yurii_pkm#yank_name() abort
  let l:name = expand('%:t')
  let @+ = l:name
  let @" = l:name
  echo 'Yanked: ' . l:name
endfunction

" ---------------------------------------------------------------------------
" gp helper: システムクリップボード優先で、末尾改行を落として行下に追加
" ---------------------------------------------------------------------------

function! yurii_pkm#paste_charwise() abort
  let l:text = @+
  if empty(l:text)
    let l:text = @"
  endif
  " 末尾の改行を除去してキャラクター単位に変換
  let l:text = substitute(l:text, '\n\+$', '', '')
  let l:lines = split(l:text, "\n", 1)
  call append(line('.'), l:lines)
endfunction

" ---------------------------------------------------------------------------
" :AT2 - Add To clipboard target (逆リンク)
" ---------------------------------------------------------------------------

" \at: at と同じ こっちにとって 側だが、括弧が付く側が逆。今開いているノート
" 側を `(ラベル)` にし、相手側にはその場で生のラベルを書く（質問なし）。
function! yurii_pkm#at_add_reverse() abort
  if s:pkm_format() ==# 'v2'
    call yurii_pkm#v2_add_link('', '', 0, 1)
    return
  endif
  call yurii_pkm#at_add()
endfunction

function! yurii_pkm#at_add() abort
  if s:pkm_format() ==# 'v2'
    call yurii_pkm#v2_add_link('', '', 0)  " at: こっちにとって 側へ（相方は sync）
    return
  endif
  let l:current_file  = expand('%:p')
  let l:current_title = yurii_pkm#current_title()

  let l:cb = s:clipboard_text()
  if empty(l:cb)
    echo 'Error: clipboard empty'
    return
  endif

  let l:targets = s:extract_targets_from_clipboard(l:cb)
  if empty(l:targets)
    echo 'Error: no valid link target in clipboard'
    return
  endif

  let l:down_added = 0
  let l:up_added = 0
  let l:already = 0
  let l:missing = 0

  for l:target in l:targets
    let l:target_fp = yurii_pkm#resolve_link(l:target)
    if !filereadable(l:target_fp)
      let l:missing += 1
      echom 'Warning: not found: ' . l:target
      continue
    endif
    if fnamemodify(l:target_fp, ':t') ==# 'index.md'
      continue
    endif

    let l:target_link = s:link_from_target(l:target)
    if !empty(l:target_link) && s:append_link_to_buffer_section('up', l:target_link)
      let l:up_added += 1
    endif

    let l:lines = readfile(l:target_fp)
    let l:new_link = s:make_link_from_dir(
          \ l:current_file, l:current_title, fnamemodify(l:target_fp, ':h'))
    let l:down_result = s:add_link_to_lines_section(l:lines, 'down', l:new_link)
    if l:down_result.added
      call writefile(l:down_result.lines, l:target_fp)
      let l:down_added += 1
    else
      let l:already += 1
    endif
  endfor

  silent write
  echo 'AT: Child added ' . l:down_added . ', Parent added ' . l:up_added . ', already ' . l:already . ', missing ' . l:missing
endfunction


" ---------------------------------------------------------------------------
" SortYomi (Child セクション yomi ソート) - Python 経由
" ---------------------------------------------------------------------------

function! yurii_pkm#open_index() abort
  let l:root = yurii_pkm#ensure_root_and_index()
  if empty(l:root)
    return
  endif
  execute 'cd ' . fnameescape(l:root)
  let l:index = s:index_path(l:root)
  if filereadable(l:index)
    if s:consume_index_created_flag()
      call s:open_index_with_delay(l:index)
    else
      call yurii_pkm#push_history()
      execute 'edit ' . fnameescape(l:index)
    endif
  else
    echo 'index.md not found in ' . l:root
  endif
endfunction

function! yurii_pkm#sort_yomi() abort
  " sort_yomi.py が同ディレクトリにあれば呼び出す
  let l:py_dir = fnamemodify(g:yurii_pkm_python, ':h')
  let l:sort_script = l:py_dir . s:sep() . 'sort_yomi.py'
  if !filereadable(l:sort_script)
    echohl ErrorMsg
    echo 'sort_yomi.py not found at: ' . l:sort_script
    echohl None
    return
  endif
  if &modified | write | endif
  let l:result = system(s:python_cmd() . ' ' . shellescape(l:sort_script) .
        \ ' ' . shellescape(expand('%:p')))
  echo l:result
  edit!
endfunction

function! s:extract_time_digits(text) abort
  let l:digits = substitute(a:text, '\D', '', 'g')
  if strlen(l:digits) >= 14
    return strpart(l:digits, 0, 14)
  endif
  return ''
endfunction

function! s:link_time_key(line) abort
  let l:m = matchlist(a:line, '\v\[[^\]]+\]\(([^)]+)\)')
  let l:target = get(l:m, 1, '')
  if empty(l:target)
    return '00000000000000'
  endif

  let l:path = yurii_pkm#resolve_link(l:target)
  if filereadable(l:path)
    let l:head = readfile(l:path, '', 40)
    let l:in_yaml = 0
    for l:line in l:head
      if l:line =~# '^---\s*$'
        if l:in_yaml
          break
        endif
        let l:in_yaml = 1
        continue
      endif
      if l:in_yaml && l:line =~? '^time:\s*'
        let l:key = s:extract_time_digits(matchstr(l:line, ':\s*\zs.*'))
        if !empty(l:key)
          return l:key
        endif
      endif
    endfor
    let l:mtime = getftime(l:path)
    if l:mtime > 0
      return strftime('%Y%m%d%H%M%S', l:mtime)
    endif
  endif

  let l:stem = fnamemodify(l:target, ':t:r')
  let l:from_name = matchstr(l:stem, '\d\{12,14}')
  if strlen(l:from_name) == 12
    return '20' . l:from_name
  elseif strlen(l:from_name) >= 14
    return strpart(l:from_name, 0, 14)
  endif
  return '00000000000000'
endfunction

function! s:sort_time_compare(a, b) abort
  let l:ka = get(a:a, 'key', '00000000000000')
  let l:kb = get(a:b, 'key', '00000000000000')
  if l:ka ==# l:kb
    return a:a.idx - a:b.idx
  endif
  return l:ka <# l:kb ? -1 : 1
endfunction

function! yurii_pkm#sort_time(...) abort
  let l:descending = a:0 >= 1 ? a:1 : 0
  let l:line1 = a:0 >= 2 ? a:2 : 0
  let l:line2 = a:0 >= 3 ? a:3 : 0
  let l:has_range = a:0 >= 4 ? a:4 : 0

  if l:has_range > 0 && l:line1 > 0 && l:line2 >= l:line1
    let l:start = l:line1
    let l:end = l:line2
    let l:scope = 'selected range'
  else
    let l:down = s:find_section_line('down')
    if l:down <= 0
      echo 'Child section not found'
      return
    endif
    let l:back = s:find_section_line('back')
    let l:start = l:down + 1
    let l:end = l:back > l:down ? l:back - 1 : line('$')
    let l:scope = 'Child links'
  endif

  if l:end < l:start
    echo 'No links to sort'
    return
  endif

  let l:entries = []
  for lnum in range(l:start, l:end)
    let l:line = getline(lnum)
    if l:line =~# s:link_pat
      call add(l:entries, {
            \ 'lnum': lnum,
            \ 'line': l:line,
            \ 'key': s:link_time_key(l:line),
            \ 'idx': len(l:entries),
            \ })
    endif
  endfor

  if len(l:entries) <= 1
    echo 'No links to sort'
    return
  endif

  call sort(l:entries, 's:sort_time_compare')
  if l:descending
    call reverse(l:entries)
  endif

  let l:i = 0
  for lnum in range(l:start, l:end)
    if getline(lnum) =~# s:link_pat
      call setline(lnum, l:entries[l:i].line)
      let l:i += 1
    endif
  endfor

  echo l:scope . ' sorted by time' . (l:descending ? ' (desc)' : ' (asc)')
endfunction

" ---------------------------------------------------------------------------
" :RP - Rename Prefix
"   現在のファイルのプレフィクスを変更し、PKMルート配下の全リンクを更新する
" ---------------------------------------------------------------------------

function! yurii_pkm#rename_prefix() abort
  let l:lines = getline(1, '$')
  let l:cur_type = ''
  let l:yaml_start = -1
  let l:yaml_end = -1
  for l:i in range(0, len(l:lines) - 1)
    if l:lines[l:i] ==# '---'
      if l:yaml_start < 0
        let l:yaml_start = l:i
      else
        let l:yaml_end = l:i
        break
      endif
    endif
  endfor
  if l:yaml_start == 0 && l:yaml_end > 0
    for l:i in range(l:yaml_start + 1, l:yaml_end - 1)
      if l:lines[l:i] =~? '^filetype:\s*'
        let l:cur_type = toupper(trim(substitute(l:lines[l:i], '^filetype:\s*', '', 'i')))
        break
      endif
    endfor
  endif
  if empty(l:cur_type)
    let l:cur_type = 'N'
  endif

  " 新プレフィクスを1文字即時入力
  echon 'filetype [' . l:cur_type . '] → '
  let l:char = nr2char(getchar())
  redraw
  if l:char !~# '^[a-zA-Z]$'
    echo 'Cancelled'
    return
  endif
  let l:new_type = toupper(l:char)
  if l:new_type ==# l:cur_type
    echo 'Filetype unchanged'
    return
  endif

  " 未保存の変更があれば保存
  if l:yaml_start == 0 && l:yaml_end > 0
    let l:done = 0
    for l:i in range(l:yaml_start + 1, l:yaml_end - 1)
      if l:lines[l:i] =~? '^filetype:\s*'
        let l:lines[l:i] = 'filetype: ' . l:new_type
        let l:done = 1
        break
      endif
    endfor
    if !l:done
      call insert(l:lines, 'filetype: ' . l:new_type, l:yaml_start + 1)
    endif
  else
    call insert(l:lines, '---', 0)
    call insert(l:lines, 'filetype: ' . l:new_type, 1)
    call insert(l:lines, '---', 2)
  endif
  call setline(1, l:lines)
  if len(l:lines) < line('$')
    execute (len(l:lines) + 1) . ',$delete _'
  endif
  silent write
  echo 'Filetype changed: ' . l:cur_type . ' → ' . l:new_type
endfunction



function! yurii_pkm#expand_s_under_cursor(...) abort
  let l:source_path = expand('%:p')
  if empty(l:source_path) || !filereadable(l:source_path)
    echoerr 'expand_s: current file is not readable'
    return
  endif

  let l:depth_arg = a:0 ? trim(a:1) : ''
  if empty(l:depth_arg)
    let l:depth = get(g:, 'yurii_pkm_expand_default_depth', 1)
  else
    let l:depth = str2nr(l:depth_arg)
  endif
  if l:depth < 0
    echoerr 'expand_s: depth must be >= 0'
    return
  endif

  let l:expand_py = g:yurii_pkm_expand_s_python
  if !filereadable(l:expand_py)
    echoerr 'expand_s.py not found: ' . l:expand_py
    return
  endif

  let l:root = yurii_pkm#ensure_root_and_index()
  if empty(l:root)
    return
  endif

  let l:py  = s:python_cmd()
  let l:cmd = l:py . ' ' . shellescape(l:expand_py)
        \ . ' expand_any ' . shellescape(l:source_path)
        \ . ' ' . shellescape(l:root)
        \ . ' ' . shellescape(string(l:depth))

  let l:out = system(l:cmd)
  if v:shell_error
    echoerr 'expand_s error: ' . substitute(l:out, '\n\+$', '', '')
    return
  endif

  let l:t_path = substitute(l:out, '\n\+$', '', '')
  if !filereadable(l:t_path)
    echoerr 'expand_s: T note not created: ' . l:t_path
    return
  endif

  let l:t_fname = fnamemodify(l:t_path, ':t')
  execute 'edit ' . fnameescape(l:t_path)

  echo 'Expanded: ' . l:t_fname . ' (depth=' . l:depth . ')'
endfunction


" ---------------------------------------------------------------------------
" Markdown table helpers (vimwiki-like)
" ---------------------------------------------------------------------------

function! s:is_table_line(line) abort
  return a:line =~# '\v^\s*\|.*\|\s*$'
endfunction

function! s:is_table_separator(line) abort
  return a:line =~# '\v^\s*\|\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|\s*$'
endfunction

function! s:table_block_range(lnum) abort
  if a:lnum < 1 || a:lnum > line('$') || !s:is_table_line(getline(a:lnum))
    return [0, 0]
  endif
  let l:start = a:lnum
  while l:start > 1 && s:is_table_line(getline(l:start - 1))
    let l:start -= 1
  endwhile
  let l:end = a:lnum
  while l:end < line('$') && s:is_table_line(getline(l:end + 1))
    let l:end += 1
  endwhile
  return [l:start, l:end]
endfunction

function! s:parse_table_line(line) abort
  let l:indent = matchstr(a:line, '^\s*')
  let l:core = substitute(a:line, '^\s*|\s*', '', '')
  let l:core = substitute(l:core, '\s*|\s*$', '', '')
  let l:cells = split(l:core, '|', 1)
  call map(l:cells, 'trim(v:val)')
  if empty(l:cells)
    let l:cells = ['']
  endif
  return {
        \ 'indent': l:indent,
        \ 'cells': l:cells,
        \ 'sep': s:is_table_separator(a:line)
        \ }
endfunction

function! s:table_col_count(start_lnum, end_lnum) abort
  let l:max_cols = 0
  for l:lnum in range(a:start_lnum, a:end_lnum)
    let l:parsed = s:parse_table_line(getline(l:lnum))
    let l:max_cols = max([l:max_cols, len(l:parsed.cells)])
  endfor
  return l:max_cols
endfunction

function! s:table_separator_token(width, align) abort
  let l:w = max([3, a:width])
  if a:align ==# 'right'
    return repeat('-', l:w - 1) . ':'
  elseif a:align ==# 'center'
    return ':' . repeat('-', max([1, l:w - 2])) . ':'
  elseif a:align ==# 'left'
    return ':' . repeat('-', l:w - 1)
  endif
  return repeat('-', l:w)
endfunction

function! s:table_align_block(start_lnum, end_lnum) abort
  let [l:new_lines, l:cols] = s:table_align_lines(getline(a:start_lnum, a:end_lnum))
  if l:cols <= 0
    return 0
  endif
  call setline(a:start_lnum, l:new_lines)
  return l:cols
endfunction

function! s:table_pipe_positions(line) abort
  let l:positions = []
  let l:start = 0
  while 1
    let l:idx = stridx(a:line, '|', l:start)
    if l:idx < 0
      break
    endif
    call add(l:positions, l:idx)
    let l:start = l:idx + 1
  endwhile
  return l:positions
endfunction

function! s:table_cell_index_from_col(line, colnum) abort
  let l:pipes = s:table_pipe_positions(a:line)
  if len(l:pipes) < 2
    return 1
  endif
  let l:cur = max([0, a:colnum - 1])
  for l:i in range(0, len(l:pipes) - 2)
    if l:cur <= l:pipes[l:i + 1]
      return l:i + 1
    endif
  endfor
  return len(l:pipes) - 1
endfunction

function! s:table_cell_startcol(line, cell_index) abort
  let l:pipes = s:table_pipe_positions(a:line)
  if len(l:pipes) < a:cell_index + 1 || a:cell_index < 1
    return 1
  endif
  let l:start0 = l:pipes[a:cell_index - 1] + 2
  if l:start0 > l:pipes[a:cell_index]
    let l:start0 = l:pipes[a:cell_index - 1] + 1
  endif
  return l:start0 + 1
endfunction

function! s:table_blank_row(cols, indent) abort
  return a:indent . '|' . join(repeat(['   '], a:cols), '|') . '|'
endfunction

function! s:table_headers(start_lnum, end_lnum, cols) abort
  let l:headers = []
  if a:start_lnum < a:end_lnum && s:is_table_separator(getline(a:start_lnum + 1))
    let l:parsed = s:parse_table_line(getline(a:start_lnum))
    while len(l:parsed.cells) < a:cols
      call add(l:parsed.cells, '')
    endwhile
    for l:i in range(0, a:cols - 1)
      let l:label = trim(l:parsed.cells[l:i])
      call add(l:headers, empty(l:label) ? ('Col ' . (l:i + 1)) : l:label)
    endfor
    return l:headers
  endif

  for l:i in range(1, a:cols)
    call add(l:headers, 'Col ' . l:i)
  endfor
  return l:headers
endfunction

function! s:table_align_lines(lines) abort
  if empty(a:lines)
    return [[], 0]
  endif

  let l:cols = 0
  for l:line in a:lines
    let l:parsed = s:parse_table_line(l:line)
    let l:cols = max([l:cols, len(l:parsed.cells)])
  endfor
  if l:cols <= 0
    return [copy(a:lines), 0]
  endif

  let l:widths = repeat([3], l:cols)
  let l:aligns = repeat(['plain'], l:cols)

  for l:line in a:lines
    let l:parsed = s:parse_table_line(l:line)
    while len(l:parsed.cells) < l:cols
      call add(l:parsed.cells, '')
    endwhile

    if l:parsed.sep
      for l:i in range(0, l:cols - 1)
        let l:token = trim(l:parsed.cells[l:i])
        if l:token =~# '^:-\+$'
          let l:aligns[l:i] = 'left'
        elseif l:token =~# '^:-\+:$'
          let l:aligns[l:i] = 'center'
        elseif l:token =~# '^\-\+:$'
          let l:aligns[l:i] = 'right'
        endif
        let l:plain = substitute(l:token, ':', '', 'g')
        let l:widths[l:i] = max([l:widths[l:i], strdisplaywidth(l:plain)])
      endfor
    else
      for l:i in range(0, l:cols - 1)
        let l:widths[l:i] = max([l:widths[l:i], strdisplaywidth(l:parsed.cells[l:i])])
      endfor
    endif
  endfor

  let l:new_lines = []
  for l:line in a:lines
    let l:parsed = s:parse_table_line(l:line)
    while len(l:parsed.cells) < l:cols
      call add(l:parsed.cells, '')
    endwhile

    let l:parts = []
    for l:i in range(0, l:cols - 1)
      if l:parsed.sep
        let l:token = s:table_separator_token(l:widths[l:i], l:aligns[l:i])
        call add(l:parts, ' ' . l:token . ' ')
      else
        let l:cell = l:parsed.cells[l:i]
        let l:pad = l:widths[l:i] - strdisplaywidth(l:cell)
        call add(l:parts, ' ' . l:cell . repeat(' ', l:pad) . ' ')
      endif
    endfor
    call add(l:new_lines, l:parsed.indent . '|' . join(l:parts, '|') . '|')
  endfor

  return [l:new_lines, l:cols]
endfunction

function! s:find_prev_table_data_line(start_lnum, first_lnum) abort
  let l:lnum = a:start_lnum
  while l:lnum >= a:first_lnum
    if s:is_table_line(getline(l:lnum)) && !s:is_table_separator(getline(l:lnum))
      return l:lnum
    endif
    let l:lnum -= 1
  endwhile
  return 0
endfunction

function! s:find_next_table_data_line(start_lnum, last_lnum) abort
  let l:lnum = a:start_lnum
  while l:lnum <= a:last_lnum
    if s:is_table_line(getline(l:lnum)) && !s:is_table_separator(getline(l:lnum))
      return l:lnum
    endif
    let l:lnum += 1
  endwhile
  return 0
endfunction

function! yurii_pkm#table_align_current() abort
  let [l:start, l:end] = s:table_block_range(line('.'))
  if l:start == 0
    echo 'Not on a table'
    return
  endif
  call s:table_align_block(l:start, l:end)
endfunction

function! yurii_pkm#table_new(args) abort
  let l:cols = 3
  let l:body_rows = 1
  let l:parts = split(trim(a:args))
  if len(l:parts) >= 1 && l:parts[0] =~# '^\d\+$'
    let l:cols = max([1, str2nr(l:parts[0])])
  endif
  if len(l:parts) >= 2 && l:parts[1] =~# '^\d\+$'
    let l:body_rows = max([1, str2nr(l:parts[1])])
  endif

  let l:indent = matchstr(getline('.'), '^\s*')
  let l:table_lines = [
        \ l:indent . '|' . join(repeat(['   '], l:cols), '|') . '|',
        \ l:indent . '|' . join(repeat([' --- '], l:cols), '|') . '|'
        \ ]
  for l:_ in range(1, l:body_rows)
    call add(l:table_lines, l:indent . '|' . join(repeat(['   '], l:cols), '|') . '|')
  endfor

  let l:start_lnum = line('.')
  if empty(trim(getline('.')))
    " 空行を削除してからテーブルを挿入（setline+リストは以降の行を上書きするためNG）
    call deletebufline('%', l:start_lnum)
    call append(l:start_lnum - 1, l:table_lines)
  else
    call append(l:start_lnum, l:table_lines)
    let l:start_lnum += 1
  endif

  let l:end_lnum = l:start_lnum + len(l:table_lines) - 1
  call s:table_align_block(l:start_lnum, l:end_lnum)
  call cursor(l:start_lnum, s:table_cell_startcol(getline(l:start_lnum), 1))
  startinsert
endfunction


function! s:feedkeys_insert(keys) abort
  call feedkeys("\<C-g>u" . a:keys, 'in')
endfunction

function! yurii_pkm#table_tab_action() abort
  if &l:filetype !=# 'markdown' && &l:filetype !=# 'vimwiki'
    call s:feedkeys_insert("\<Tab>")
    return
  endif
  let l:cur_lnum = line('.')
  let l:cur_line = getline(l:cur_lnum)
  if !s:is_table_line(l:cur_line)
    call s:feedkeys_insert("\<Tab>")
    return
  endif

  let l:cur_cell = s:table_cell_index_from_col(l:cur_line, col('.'))
  let [l:start, l:end] = s:table_block_range(l:cur_lnum)
  let l:parsed = s:parse_table_line(l:cur_line)
  let l:cols = len(l:parsed.cells)
  if l:cols <= 0
    call s:feedkeys_insert("\<Tab>")
    return
  endif

  if l:cur_cell < l:cols
    call cursor(l:cur_lnum, s:table_cell_startcol(getline(l:cur_lnum), l:cur_cell + 1))
    return
  endif

  let l:next_data = s:find_next_table_data_line(l:cur_lnum + 1, l:end)
  if l:next_data > 0
    call cursor(l:next_data, s:table_cell_startcol(getline(l:next_data), 1))
    return
  endif

  let l:insert_after = l:cur_lnum
  if l:insert_after < l:end && s:is_table_separator(getline(l:insert_after + 1))
    let l:insert_after += 1
  endif
  let l:indent = matchstr(getline(l:cur_lnum), '^\s*')
  call append(l:insert_after, s:table_blank_row(l:cols, l:indent))
  let l:new_lnum = l:insert_after + 1
  call s:table_align_block(l:start, l:end + 1)
  call cursor(l:new_lnum, s:table_cell_startcol(getline(l:new_lnum), 1))
endfunction

function! yurii_pkm#table_stab_action() abort
  if &l:filetype !=# 'markdown' && &l:filetype !=# 'vimwiki'
    call s:feedkeys_insert("\<C-d>")
    return
  endif
  let l:cur_lnum = line('.')
  let l:cur_line = getline(l:cur_lnum)
  if !s:is_table_line(l:cur_line)
    call s:feedkeys_insert("\<C-d>")
    return
  endif

  let l:cur_cell = s:table_cell_index_from_col(l:cur_line, col('.'))
  let [l:start, l:end] = s:table_block_range(l:cur_lnum)
  let l:parsed = s:parse_table_line(l:cur_line)
  let l:cols = len(l:parsed.cells)
  if l:cols <= 0
    return
  endif

  if l:cur_cell > 1
    call cursor(l:cur_lnum, s:table_cell_startcol(getline(l:cur_lnum), l:cur_cell - 1))
    return
  endif

  let l:prev_data = s:find_prev_table_data_line(l:cur_lnum - 1, l:start)
  if l:prev_data > 0
    call cursor(l:prev_data, s:table_cell_startcol(getline(l:prev_data), l:cols))
  endif
endfunction

function! yurii_pkm#table_cr_action() abort
  if &l:filetype !=# 'markdown' && &l:filetype !=# 'vimwiki'
    call s:feedkeys_insert("\<CR>")
    return
  endif
  let l:cur_lnum = line('.')
  let l:cur_line = getline(l:cur_lnum)
  if !s:is_table_line(l:cur_line)
    call s:feedkeys_insert("\<CR>")
    return
  endif

  let l:cur_cell = s:table_cell_index_from_col(l:cur_line, col('.'))
  let [l:start, l:end] = s:table_block_range(l:cur_lnum)
  let l:parsed = s:parse_table_line(l:cur_line)
  let l:cols = len(l:parsed.cells)
  if l:cols <= 0
    call s:feedkeys_insert("\<CR>")
    return
  endif

  let l:target_cell = min([max([1, l:cur_cell]), l:cols])
  let l:next_data = s:find_next_table_data_line(l:cur_lnum + 1, l:end)
  if l:next_data > 0
    call cursor(l:next_data, s:table_cell_startcol(getline(l:next_data), l:target_cell))
    return
  endif

  let l:insert_after = l:cur_lnum
  if l:cur_lnum < l:end && s:is_table_separator(getline(l:cur_lnum + 1))
    let l:insert_after = l:cur_lnum + 1
  endif

  let l:indent = matchstr(getline(l:cur_lnum), '^\s*')
  call append(l:insert_after, s:table_blank_row(l:cols, l:indent))
  let l:new_lnum = l:insert_after + 1
  call s:table_align_block(l:start, l:end + 1)
  call cursor(l:new_lnum, s:table_cell_startcol(getline(l:new_lnum), l:target_cell))
endfunction
function! yurii_pkm#table_tab() abort
  if &l:filetype !=# 'markdown' && &l:filetype !=# 'vimwiki'
    return "\<Tab>"
  endif
  let l:cur_lnum = line('.')
  let l:cur_line = getline(l:cur_lnum)
  if !s:is_table_line(l:cur_line)
    return "\<Tab>"
  endif

  let l:cur_cell = s:table_cell_index_from_col(l:cur_line, col('.'))
  let [l:start, l:end] = s:table_block_range(l:cur_lnum)
  let l:cols = s:table_align_block(l:start, l:end)
  if l:cols <= 0
    return "\<Tab>"
  endif

  if l:cur_cell < l:cols
    call cursor(l:cur_lnum, s:table_cell_startcol(getline(l:cur_lnum), l:cur_cell + 1))
    return ''
  endif

  let l:next_data = s:find_next_table_data_line(l:cur_lnum + 1, l:end)
  if l:next_data > 0
    call cursor(l:next_data, s:table_cell_startcol(getline(l:next_data), 1))
    return ''
  endif

  let l:insert_after = l:cur_lnum
  if l:insert_after < l:end && s:is_table_separator(getline(l:insert_after + 1))
    let l:insert_after += 1
  endif
  let l:indent = matchstr(getline(l:cur_lnum), '^\s*')
  call append(l:insert_after, s:table_blank_row(l:cols, l:indent))
  let l:new_lnum = l:insert_after + 1
  call s:table_align_block(l:start, l:end + 1)
  call cursor(l:new_lnum, s:table_cell_startcol(getline(l:new_lnum), 1))
  return ''
endfunction

function! yurii_pkm#table_stab() abort
  if &l:filetype !=# 'markdown' && &l:filetype !=# 'vimwiki'
    return "\<S-Tab>"
  endif
  let l:cur_lnum = line('.')
  let l:cur_line = getline(l:cur_lnum)
  if !s:is_table_line(l:cur_line)
    return "\<S-Tab>"
  endif

  let l:cur_cell = s:table_cell_index_from_col(l:cur_line, col('.'))
  let [l:start, l:end] = s:table_block_range(l:cur_lnum)
  let l:cols = s:table_align_block(l:start, l:end)
  if l:cols <= 0
    return "\<S-Tab>"
  endif

  if l:cur_cell > 1
    call cursor(l:cur_lnum, s:table_cell_startcol(getline(l:cur_lnum), l:cur_cell - 1))
    return ''
  endif

  let l:prev_data = s:find_prev_table_data_line(l:cur_lnum - 1, l:start)
  if l:prev_data > 0
    call cursor(l:prev_data, s:table_cell_startcol(getline(l:prev_data), l:cols))
    return ''
  endif
  return ''
endfunction

function! yurii_pkm#table_cr() abort
  if &l:filetype !=# 'markdown' && &l:filetype !=# 'vimwiki'
    return "\<CR>"
  endif
  let l:cur_lnum = line('.')
  let l:cur_line = getline(l:cur_lnum)
  if !s:is_table_line(l:cur_line)
    return "\<CR>"
  endif

  let [l:start, l:end] = s:table_block_range(l:cur_lnum)
  let l:cols = s:table_align_block(l:start, l:end)
  if l:cols <= 0
    return "\<CR>"
  endif

  let l:insert_after = l:cur_lnum
  if s:is_table_separator(getline(l:cur_lnum))
    let l:insert_after = l:cur_lnum
  elseif l:cur_lnum < l:end && s:is_table_separator(getline(l:cur_lnum + 1))
    let l:insert_after = l:cur_lnum + 1
  endif

  let l:indent = matchstr(getline(l:cur_lnum), '^\s*')
  call append(l:insert_after, s:table_blank_row(l:cols, l:indent))
  let l:new_lnum = l:insert_after + 1
  call s:table_align_block(l:start, l:end + 1)
  call cursor(l:new_lnum, s:table_cell_startcol(getline(l:new_lnum), 1))
  return ''
endfunction

function! s:table_row_editor_lines(headers, cells) abort
  let l:lines = [
        \ '# TableRowEdit: 各項目の次の行を書き換えて :write で反映',
        \ '# q で閉じる / ZZ で保存して閉じる',
        \ ''
        \ ]
  for l:i in range(0, len(a:cells) - 1)
    call add(l:lines, '[' . (l:i + 1) . '] ' . a:headers[l:i])
    call add(l:lines, a:cells[l:i])
    call add(l:lines, '')
  endfor
  return l:lines
endfunction

function! yurii_pkm#table_row_edit() abort
  let l:cur_lnum = line('.')
  let [l:start, l:end] = s:table_block_range(l:cur_lnum)
  if l:start == 0
    echo 'Not on a table'
    return
  endif
  if s:is_table_separator(getline(l:cur_lnum))
    echo 'Separator row cannot be edited here'
    return
  endif

  let l:cols = s:table_align_block(l:start, l:end)
  let l:parsed = s:parse_table_line(getline(l:cur_lnum))
  while len(l:parsed.cells) < l:cols
    call add(l:parsed.cells, '')
  endwhile
  let l:headers = s:table_headers(l:start, l:end, l:cols)

  let l:origin_win = win_getid()
  vertical botright new
  let l:editor_buf = bufnr('%')
  call setline(1, s:table_row_editor_lines(l:headers, l:parsed.cells))

  let b:yurii_table_editor = 1
  let b:yurii_table_src_bufnr = bufnr('#') > 0 ? bufnr('#') : bufnr(winbufnr(l:origin_win))
  let b:yurii_table_src_bufnr = winbufnr(l:origin_win)
  let b:yurii_table_src_lnum = l:cur_lnum
  let b:yurii_table_src_start = l:start
  let b:yurii_table_src_end = l:end
  let b:yurii_table_cols = l:cols
  let b:yurii_table_headers = copy(l:headers)

  setlocal buftype=acwrite
  setlocal bufhidden=wipe
  setlocal noswapfile
  setlocal nobuflisted
  setlocal filetype=markdown
  setlocal wrap
  setlocal linebreak
  setlocal breakindent
  setlocal nonumber
  setlocal norelativenumber
  setlocal foldcolumn=0
  setlocal signcolumn=no
  setlocal textwidth=0
  setlocal modifiable

  execute 'autocmd! BufWriteCmd <buffer> call yurii_pkm#table_row_editor_apply()'
  nnoremap <silent><buffer> q  <Cmd>bd!<CR>
  nnoremap <silent><buffer> ZZ <Cmd>write<Bar>bd!<CR>

  call cursor(4, 1)
endfunction

function! yurii_pkm#table_row_editor_apply() abort
  if !exists('b:yurii_table_editor') || !b:yurii_table_editor
    return
  endif

  let l:cols = get(b:, 'yurii_table_cols', 0)
  let l:headers = get(b:, 'yurii_table_headers', [])
  if l:cols <= 0 || len(l:headers) != l:cols
    echoerr 'TableRowEdit: invalid editor state'
    return
  endif

  let l:new_cells = []
  let l:base = 4
  for l:i in range(0, l:cols - 1)
    let l:value_lnum = l:base + (l:i * 3) + 1
    call add(l:new_cells, trim(getline(l:value_lnum)))
  endfor

  let l:src_buf = b:yurii_table_src_bufnr
  let l:src_start = b:yurii_table_src_start
  let l:src_end = b:yurii_table_src_end
  let l:src_lnum = b:yurii_table_src_lnum

  if !bufexists(l:src_buf)
    echoerr 'TableRowEdit: source buffer not found'
    return
  endif

  let l:block_lines = getbufline(l:src_buf, l:src_start, l:src_end)
  if empty(l:block_lines)
    echoerr 'TableRowEdit: source table not found'
    return
  endif

  let l:row_idx = l:src_lnum - l:src_start
  if l:row_idx < 0 || l:row_idx >= len(l:block_lines)
    echoerr 'TableRowEdit: source row is out of range'
    return
  endif

  let l:src_parsed = s:parse_table_line(l:block_lines[l:row_idx])
  let l:block_lines[l:row_idx] = l:src_parsed.indent . '| ' . join(l:new_cells, ' | ') . ' |'

  let [l:aligned, l:cols2] = s:table_align_lines(l:block_lines)
  if l:cols2 <= 0
    echoerr 'TableRowEdit: failed to align table'
    return
  endif

  call setbufline(l:src_buf, l:src_start, l:aligned)
  setlocal nomodified
  echo 'Table row updated'
endfunction


function! s:csv_escape_field(field) abort
  let l:field = a:field
  let l:needs_quote = l:field =~# '[",\n]'
  let l:field = substitute(l:field, '"', '""', 'g')
  return l:needs_quote ? '"' . l:field . '"' : l:field
endfunction

function! s:csv_join_fields(fields) abort
  let l:out = []
  for l:field in a:fields
    call add(l:out, s:csv_escape_field(l:field))
  endfor
  return join(l:out, ',')
endfunction

function! s:csv_parse_line(line) abort
  let l:fields = []
  let l:field = ''
  let l:in_quotes = 0
  let l:i = 0
  while l:i < strlen(a:line)
    let l:ch = strpart(a:line, l:i, 1)
    if l:in_quotes
      if l:ch ==# '"'
        if l:i + 1 < strlen(a:line) && strpart(a:line, l:i + 1, 1) ==# '"'
          let l:field .= '"'
          let l:i += 1
        else
          let l:in_quotes = 0
        endif
      else
        let l:field .= l:ch
      endif
    else
      if l:ch ==# ','
        call add(l:fields, l:field)
        let l:field = ''
      elseif l:ch ==# '"'
        let l:in_quotes = 1
      else
        let l:field .= l:ch
      endif
    endif
    let l:i += 1
  endwhile
  call add(l:fields, l:field)
  return l:fields
endfunction

function! s:csv_block_range(lnum) abort
  if a:lnum < 1 || a:lnum > line('$') || empty(trim(getline(a:lnum)))
    return [0, 0]
  endif
  let l:start = a:lnum
  let l:end = a:lnum
  while l:start > 1 && !empty(trim(getline(l:start - 1)))
    let l:start -= 1
  endwhile
  while l:end < line('$') && !empty(trim(getline(l:end + 1)))
    let l:end += 1
  endwhile
  return [l:start, l:end]
endfunction

function! s:table_lines_to_csv(lines) abort
  let l:csv = []
  for l:line in a:lines
    let l:parsed = s:parse_table_line(l:line)
    if l:parsed.sep
      continue
    endif
    call add(l:csv, s:csv_join_fields(l:parsed.cells))
  endfor
  return l:csv
endfunction

function! s:csv_lines_to_table(lines, indent) abort
  let l:rows = []
  let l:maxcols = 0
  for l:line in a:lines
    if empty(trim(l:line))
      continue
    endif
    let l:fields = s:csv_parse_line(l:line)
    let l:maxcols = max([l:maxcols, len(l:fields)])
    call add(l:rows, l:fields)
  endfor
  if empty(l:rows)
    return []
  endif
  let l:maxcols = max([1, l:maxcols])
  let l:table = []
  for l:ridx in range(0, len(l:rows) - 1)
    while len(l:rows[l:ridx]) < l:maxcols
      call add(l:rows[l:ridx], '')
    endwhile
    call add(l:table, a:indent . '| ' . join(l:rows[l:ridx], ' | ') . ' |')
    if l:ridx == 0
      call add(l:table, a:indent . '|' . join(repeat([' --- '], l:maxcols), '|') . '|')
    endif
  endfor
  let [l:aligned, l:cols] = s:table_align_lines(l:table)
  return l:aligned
endfunction

function! s:append_current_file_branch_link(link) abort
  let l:ins = s:structural_link_append_line()
  if l:ins <= 0
    return 0
  endif
  let l:save_ai = &l:autoindent
  let l:save_si = &l:smartindent
  setlocal noautoindent nosmartindent
  call append(l:ins, a:link)
  let &l:autoindent = l:save_ai
  let &l:smartindent = l:save_si
  return 1
endfunction

function! s:next_t_csv_path(base_dir, idx_hint) abort
  let l:ts = strftime('%y%m%d%H%M%S')
  let l:idx = a:idx_hint > 0 ? a:idx_hint : 1
  let l:path = a:base_dir . '/T_' . l:ts . '_' . l:idx . '.csv'
  while filereadable(l:path)
    let l:idx += 1
    let l:path = a:base_dir . '/T_' . l:ts . '_' . l:idx . '.csv'
  endwhile
  return l:path
endfunction

function! s:csv_branch_link(csv_path) abort
  let l:name = fnamemodify(a:csv_path, ':t')
  return '[' . fnamemodify(l:name, ':r') . '](' . l:name . ')'
endfunction

function! yurii_pkm#csv_new() abort
  let l:src_name = expand('%:p')
  let l:base_dir = empty(l:src_name) ? getcwd() : fnamemodify(l:src_name, ':p:h')
  let l:csv_path = s:next_t_csv_path(l:base_dir, 1)
  call writefile([], l:csv_path)
  call s:append_current_file_branch_link(s:csv_branch_link(l:csv_path))
  silent! write
  execute 'edit ' . fnameescape(l:csv_path)
endfunction

function! yurii_pkm#table_to_csv() abort
  let [l:start, l:end] = s:table_block_range(line('.'))
  if l:start == 0
    echo 'Not on a table'
    return
  endif
  let l:src_name = expand('%:p')
  let l:base_dir = empty(l:src_name) ? getcwd() : fnamemodify(l:src_name, ':p:h')
  let l:csv_lines = s:table_lines_to_csv(getline(l:start, l:end))
  let l:csv_path = s:next_t_csv_path(l:base_dir, l:start)
  call writefile(l:csv_lines, l:csv_path)
  call deletebufline('%', l:start, l:end)
  call s:append_current_file_branch_link(s:csv_branch_link(l:csv_path))
  silent! write
  execute 'edit ' . fnameescape(l:csv_path)
endfunction

function! yurii_pkm#csv_to_table() abort
  return yurii_pkm#csv_to_table_current()
endfunction

function! yurii_pkm#table_to_csv_current() abort
  let [l:start, l:end] = s:table_block_range(line('.'))
  if l:start == 0
    echo 'Not on a table'
    return
  endif
  let l:csv = s:table_lines_to_csv(getline(l:start, l:end))
  call setline(l:start, l:csv)
  if l:end > l:start + len(l:csv) - 1
    execute (l:start + len(l:csv)) . ',' . l:end . 'delete _'
  endif
  echo 'Converted table to CSV'
endfunction

function! yurii_pkm#csv_to_table_current() abort
  let [l:start, l:end] = s:csv_block_range(line('.'))
  if l:start == 0
    echo 'Not on CSV lines'
    return
  endif
  let l:indent = matchstr(getline(l:start), '^\s*')
  let l:table = s:csv_lines_to_table(getline(l:start, l:end), l:indent)
  if empty(l:table)
    echo 'CSV block is empty'
    return
  endif
  call setline(l:start, l:table)
  if l:end > l:start + len(l:table) - 1
    execute (l:start + len(l:table)) . ',' . l:end . 'delete _'
  endif
  echo 'Converted CSV to table'
endfunction

function! s:table_csv_temp_path(src_buf, start) abort
  let l:src_name = bufname(a:src_buf)
  let l:base_dir = empty(l:src_name) ? getcwd() : fnamemodify(l:src_name, ':p:h')
  let l:stamp = strftime('%y%m%d%H%M%S')
  return l:base_dir . '/T_' . l:stamp . '_' . a:start . '.csv'
endfunction

function! s:table_csv_apply_to_source(csv_lines, src_buf, src_start, src_end, indent) abort
  if a:src_buf < 0 || a:src_start <= 0 || a:src_end < a:src_start || !bufexists(a:src_buf)
    echoerr 'TableCsvEdit: source buffer not found'
    return 0
  endif

  call bufload(a:src_buf)

  let l:table = s:csv_lines_to_table(a:csv_lines, a:indent)
  if empty(l:table)
    echoerr 'TableCsvEdit: CSV is empty'
    return 0
  endif

  call setbufline(a:src_buf, a:src_start, l:table)
  let l:new_end = a:src_start + len(l:table) - 1
  if a:src_end > l:new_end
    call deletebufline(a:src_buf, l:new_end + 1, a:src_end)
  endif
  call setbufvar(a:src_buf, '&modified', 1)
  return l:new_end
endfunction


function! yurii_pkm#table_csv_editor_cleanup(...) abort
  return
endfunction

function! yurii_pkm#table_csv_edit() abort
  let l:cur_lnum = line('.')
  let [l:start, l:end] = s:table_block_range(l:cur_lnum)
  if l:start == 0
    echo 'Not on a table'
    return
  endif

  let l:src_buf = bufnr('%')
  let l:src_indent = matchstr(getline(l:start), '^\s*')
  let l:csv_lines = s:table_lines_to_csv(getline(l:start, l:end))
  let l:csv_path = s:table_csv_temp_path(l:src_buf, l:start)
  call writefile(l:csv_lines, l:csv_path)

  execute 'edit ' . fnameescape(l:csv_path)

  let b:yurii_table_csv_editor = 1
  let b:yurii_table_src_bufnr = l:src_buf
  let b:yurii_table_src_start = l:start
  let b:yurii_table_src_end = l:end
  let b:yurii_table_src_indent = l:src_indent
  let b:yurii_table_csv_path = l:csv_path

  setlocal filetype=csv
  setlocal nowrap
  setlocal nonumber
  setlocal norelativenumber
  setlocal foldcolumn=0
  setlocal signcolumn=no
  setlocal textwidth=0

  augroup yurii_table_csv_editor
    autocmd! * <buffer>
  augroup END
  nnoremap <silent><buffer> q  <Cmd>bd!<CR>
  echo 'TableCsvEdit: editing ' . fnamemodify(l:csv_path, ':t') . ' (use :TableCsvApplySaved to apply)'
endfunction

function! yurii_pkm#table_csv_editor_apply(...) abort
  if a:0 >= 1
    let l:buf = a:1
  else
    let l:buf = bufnr('%')
    " カレントバッファがCSVエディタでなければ、全バッファから探す
    if !getbufvar(l:buf, 'yurii_table_csv_editor', 0)
      let l:buf = -1
      for l:b in range(1, bufnr('$'))
        if bufexists(l:b) && getbufvar(l:b, 'yurii_table_csv_editor', 0)
          let l:buf = l:b
          break
        endif
      endfor
    endif
  endif
  if l:buf < 0 || !getbufvar(l:buf, 'yurii_table_csv_editor', 0)
    echoerr 'TableCsvEdit: not a TableCsvEdit CSV buffer'
    return
  endif

  let l:src_buf = getbufvar(l:buf, 'yurii_table_src_bufnr', -1)
  let l:src_start = getbufvar(l:buf, 'yurii_table_src_start', 0)
  let l:src_end = getbufvar(l:buf, 'yurii_table_src_end', 0)
  let l:indent = getbufvar(l:buf, 'yurii_table_src_indent', '')
  let l:src_win = bufwinid(l:src_buf)

  if bufloaded(l:buf)
    let l:csv_lines = getbufline(l:buf, 1, '$')
  else
    let l:csv_path = getbufvar(l:buf, 'yurii_table_csv_path', bufname(l:buf))
    if empty(l:csv_path) || !filereadable(l:csv_path)
      echoerr 'TableCsvEdit: CSV file not found'
      return
    endif
    let l:csv_lines = readfile(l:csv_path)
  endif

  let l:new_end = s:table_csv_apply_to_source(l:csv_lines, l:src_buf, l:src_start, l:src_end, l:indent)
  if l:new_end <= 0
    return
  endif

  call setbufvar(l:buf, 'yurii_table_src_end', l:new_end)

  if l:src_win > 0
    call win_gotoid(l:src_win)
  else
    execute 'keepalt buffer ' . l:src_buf
  endif
  call cursor(l:src_start, 1)

  if bufnr('%') == l:src_buf
    silent! write
  endif

  echo 'CSV changes applied to table'
endfunction

function! yurii_pkm#table_csv_editor_apply_saved(...) abort
  let l:buf = a:0 >= 1 ? a:1 : bufnr('%')
  call yurii_pkm#table_csv_editor_apply(l:buf)
endfunction


" ---------------------------------------------------------------------------
" テーブル行・列の追加・削除
" ---------------------------------------------------------------------------

" カーソル行をテーブルから削除（ヘッダ行・セパレータ行は削除不可）
function! yurii_pkm#table_del_row() abort
  let l:lnum = line('.')
  if !s:is_table_line(getline(l:lnum))
    echo 'Not on a table row'
    return
  endif
  if s:is_table_separator(getline(l:lnum))
    echo 'Cannot delete separator row'
    return
  endif
  let [l:start, l:end] = s:table_block_range(l:lnum)
  if l:lnum == l:start
    echo 'Cannot delete header row'
    return
  endif
  let l:data_rows = 0
  for l:i in range(l:start, l:end)
    if !s:is_table_separator(getline(l:i)) && l:i != l:start
      let l:data_rows += 1
    endif
  endfor
  if l:data_rows <= 1
    echo 'Cannot delete the last data row'
    return
  endif
  execute l:lnum . 'delete _'
  call s:table_align_block(l:start, l:end - 1)
endfunction

" カーソル列をテーブルから削除
function! yurii_pkm#table_del_col() abort
  let l:lnum = line('.')
  if !s:is_table_line(getline(l:lnum))
    echo 'Not on a table column'
    return
  endif
  let [l:start, l:end] = s:table_block_range(l:lnum)
  let l:cols = s:table_col_count(l:start, l:end)
  if l:cols <= 1
    echo 'Cannot delete the last column'
    return
  endif
  let l:col_idx = s:table_cell_index_from_col(getline(l:lnum), col('.'))
  if l:col_idx < 0 || l:col_idx >= l:cols
    echo 'Cursor is not inside a cell'
    return
  endif
  for l:i in range(l:start, l:end)
    let l:parsed = s:parse_table_line(getline(l:i))
    if len(l:parsed.cells) <= l:col_idx
      continue
    endif
    call remove(l:parsed.cells, l:col_idx)
    if l:parsed.sep
      let l:new_cells = map(copy(l:parsed.cells), '"---"')
      call setline(l:i, l:parsed.indent . '| ' . join(l:new_cells, ' | ') . ' |')
    else
      call setline(l:i, l:parsed.indent . '| ' . join(l:parsed.cells, ' | ') . ' |')
    endif
  endfor
  call s:table_align_block(l:start, l:end)
endfunction

" カーソル行の下に空行を追加
function! yurii_pkm#table_add_row() abort
  let l:lnum = line('.')
  if !s:is_table_line(getline(l:lnum))
    echo 'Not on a table row'
    return
  endif
  let [l:start, l:end] = s:table_block_range(l:lnum)
  let l:cols = s:table_col_count(l:start, l:end)
  let l:indent = matchstr(getline(l:start), '^\s*')
  let l:insert_after = l:lnum
  if l:insert_after < l:end && s:is_table_separator(getline(l:insert_after + 1))
    let l:insert_after += 1
  endif
  call append(l:insert_after, s:table_blank_row(l:cols, l:indent))
  call s:table_align_block(l:start, l:end + 1)
  call cursor(l:insert_after + 1, s:table_cell_startcol(getline(l:insert_after + 1), 1))
endfunction

" カーソル列の右に空列を追加
function! yurii_pkm#table_add_col() abort
  let l:lnum = line('.')
  if !s:is_table_line(getline(l:lnum))
    echo 'Not on a table column'
    return
  endif
  let [l:start, l:end] = s:table_block_range(l:lnum)
  let l:cols = s:table_col_count(l:start, l:end)
  let l:col_idx = s:table_cell_index_from_col(getline(l:lnum), col('.'))
  if l:col_idx < 0
    let l:col_idx = l:cols - 1
  endif
  let l:insert_at = l:col_idx + 1
  for l:i in range(l:start, l:end)
    let l:parsed = s:parse_table_line(getline(l:i))
    let l:pos = min([l:insert_at, len(l:parsed.cells)])
    if l:parsed.sep
      call insert(l:parsed.cells, '---', l:pos)
      let l:new_cells = map(copy(l:parsed.cells), '"---"')
      call setline(l:i, l:parsed.indent . '| ' . join(l:new_cells, ' | ') . ' |')
    else
      call insert(l:parsed.cells, '', l:pos)
      call setline(l:i, l:parsed.indent . '| ' . join(l:parsed.cells, ' | ') . ' |')
    endif
  endfor
  call s:table_align_block(l:start, l:end)
endfunction

" ---------------------------------------------------------------------------
" CopyStack Mode  (スタック選択コピー)
" ---------------------------------------------------------------------------
" 使い方:
"   :CopyStack  モード開始 / 2回目でコミット（クリップボードに書いて終了）
"   y           ノーマル: 現在行をスタックに追加
"               ビジュアル: 選択範囲をスタックに追加
" ---------------------------------------------------------------------------

let s:stack_copy_mode  = 0
let s:stack_copy_lines = []
let s:stack_copy_stl_save = ''
let s:stack_copy_wbr_save = ''

function! s:stack_copy_statusline_on() abort
  let s:stack_copy_stl_save = &l:statusline
  if exists('+winbar')
    let s:stack_copy_wbr_save = &l:winbar
  else
    let s:stack_copy_wbr_save = ''
  endif
  setlocal statusline=%#WarningMsg#\ [CopyStack]\ %*%f\ %m%=%l/%L
  if exists('+winbar')
    let &l:winbar = '%#WarningMsg# [CopyStack] y:追加  d:切り取り  :CopyStack:確定/終了 %#Normal#'
  endif
endfunction

function! s:stack_copy_statusline_off() abort
  if s:stack_copy_stl_save ==# ''
    setlocal statusline&
  else
    let &l:statusline = s:stack_copy_stl_save
  endif
  if exists('+winbar')
    if s:stack_copy_wbr_save ==# ''
      setlocal winbar&
    else
      let &l:winbar = s:stack_copy_wbr_save
    endif
  endif
  let s:stack_copy_stl_save = ''
  let s:stack_copy_wbr_save = ''
endfunction

function! s:stack_copy_finish(copy_to_clipboard) abort
  if a:copy_to_clipboard && !empty(s:stack_copy_lines)
    let l:text = join(s:stack_copy_lines, "\n")
    let @+ = l:text
    let @" = l:text
    
  else
    
  endif
  silent! nunmap <buffer> y
  silent! xunmap <buffer> y
  silent! nunmap <buffer> d
  silent! xunmap <buffer> d
  call s:stack_copy_statusline_off()
  let s:stack_copy_mode  = 0
  let s:stack_copy_lines = []
endfunction

function! yurii_pkm#stack_copy_toggle() abort
  if !s:stack_copy_mode
    let s:stack_copy_mode  = 1
    let s:stack_copy_lines = []
    nnoremap <buffer> <silent> <nowait> y :<C-u>call yurii_pkm#stack_copy_yank_line()<CR>
    xnoremap <buffer> <silent> <nowait> y :<C-u>call yurii_pkm#stack_copy_yank_visual()<CR>
    nnoremap <buffer> <silent> <nowait> d :<C-u>call yurii_pkm#stack_copy_delete_line()<CR>
    xnoremap <buffer> <silent> <nowait> d :<C-u>call yurii_pkm#stack_copy_delete_visual()<CR>
    call s:stack_copy_statusline_on()
    
  else
    call s:stack_copy_finish(!empty(s:stack_copy_lines))
  endif
endfunction

function! yurii_pkm#stack_copy_yank_line() abort
  let l:line = getline('.')
  call add(s:stack_copy_lines, l:line)
  
endfunction

function! yurii_pkm#stack_copy_yank_visual() abort range
  let l:s = line("'<")
  let l:e = line("'>")
  for l:i in range(l:s, l:e)
    call add(s:stack_copy_lines, getline(l:i))
  endfor
  
endfunction

function! yurii_pkm#stack_copy_delete_line() abort
  let l:line = getline('.')
  call add(s:stack_copy_lines, l:line)
  execute 'delete _'
  
endfunction

function! yurii_pkm#stack_copy_delete_visual() abort range
  let l:s = line("'<")
  let l:e = line("'>")
  for l:i in range(l:s, l:e)
    call add(s:stack_copy_lines, getline(l:i))
  endfor
  execute "normal! <Esc>"
  execute "'<,'>delete _"
  
endfunction

function! s:toggle_checkbox_in_line(lnum) abort
  let l:line = getline(a:lnum)
  let l:start = 0
  let l:best = []
  while 1
    let l:m = matchstrpos(l:line, '\[[ xX]\]', l:start)
    if empty(l:m) || l:m[1] < 0
      break
    endif
    if a:lnum == line('.') && col('.') - 1 >= l:m[1] && col('.') - 1 <= l:m[2] - 1
      let l:best = l:m
      break
    endif
    if empty(l:best)
      let l:best = l:m
    endif
    let l:start = l:m[2]
  endwhile
  if empty(l:best)
    return 0
  endif
  let l:mark = strpart(l:best[0], 1, 1)
  let l:new = (l:mark =~# '[xX]') ? '[ ]' : '[x]'
  let l:newline = strpart(l:line, 0, l:best[1]) . l:new . strpart(l:line, l:best[2])
  call setline(a:lnum, l:newline)
  return 1
endfunction

function! yurii_pkm#toggle_checkbox(first, last, has_range) abort range
  if a:has_range
    for l:lnum in range(a:first, a:last)
      call s:toggle_checkbox_in_line(l:lnum)
    endfor
    return
  endif
  if !s:toggle_checkbox_in_line(line('.'))
    echo 'No checkbox ([ ] / [x]) on this line'
  endif
endfunction

" ---------------------------------------------------------------------------
" Image gallery: open current Markdown note as a browser thumbnail grid
" ---------------------------------------------------------------------------

function! s:python_executable() abort
  if executable('python3')
    return 'python3'
  endif
  return 'python'
endfunction


function! s:line_has_image_link(line) abort
  let l:image_ext = '\%(avif\|bmp\|gif\|jpe\?g\|png\|svg\|webp\)'
  return a:line =~# '!\[[^\]]*\]([^)]\+)'
        \ || a:line =~? '\[[^\]]*\]([^)]*\.' . l:image_ext . '\%([#?][^)]*\)\?)'
        \ || a:line =~? '!?\[\[[^]|]\+\.' . l:image_ext . '\%([#?][^]|]\)*\%(|[^]]*\)\?\]\]'
        \ || (a:line =~? '<img' && a:line =~? 'src\s*=')
endfunction

function! s:buffer_has_image_link() abort
  for l:line in getline(1, '$')
    if s:line_has_image_link(l:line)
      return 1
    endif
  endfor
  return 0
endfunction

function! s:index_root_from_path(path) abort
  let l:path = fnamemodify(expand(a:path), ':p')
  let l:dir = isdirectory(l:path) ? l:path : fnamemodify(l:path, ':h')
  while !empty(l:dir)
    if filereadable(l:dir . s:sep() . 'index.md')
      return l:dir
    endif
    let l:parent = fnamemodify(l:dir, ':h')
    if l:parent ==# l:dir
      break
    endif
    let l:dir = l:parent
  endwhile
  return ''
endfunction

function! s:gallery_root() abort
  let l:root = fnamemodify(expand(get(g:, 'yurii_pkm_root', '')), ':p')
  if !empty(l:root) && isdirectory(l:root)
    return l:root
  endif
  return s:index_root_from_path(expand('%:p'))
endfunction

function! s:run_gallery_command(args, label) abort
  let l:py = get(g:, 'yurii_pkm_gallery_python', '')
  if empty(l:py) || !filereadable(l:py)
    echoerr 'yurii_PKM: gallery.py not found: ' . l:py
    return
  endif
  let l:port = get(g:, 'yurii_pkm_gallery_port', 8765)
  let l:cmd = [s:python_executable(), l:py] + a:args + ['--port', string(l:port)]

  if exists('*jobstart')
    call jobstart(l:cmd, {'detach': v:true})
    echom 'yurii_PKM: opening gallery for ' . a:label
    return
  endif
  if exists('*job_start')
    call job_start(l:cmd, {'out_io': 'null', 'err_io': 'null'})
    echom 'yurii_PKM: opening gallery for ' . a:label
    return
  endif

  let l:result = system(join(map(copy(l:cmd), 'shellescape(v:val)'), ' '))
  if v:shell_error
    echohl ErrorMsg | echom 'yurii_PKM Gallery failed: ' . l:result | echohl None
  else
    echom 'yurii_PKM: opening gallery for ' . a:label
  endif
endfunction

function! yurii_pkm#open_folder_gallery(...) abort
  let l:target = a:0 >= 1 && !empty(a:1) ? a:1 : s:gallery_root()
  if empty(l:target)
    let l:target = expand('%:p')
  endif
  if empty(l:target)
    let l:target = getcwd()
  endif
  let l:path = fnamemodify(expand(l:target), ':p')
  let l:dir = isdirectory(l:path) ? l:path : fnamemodify(l:path, ':h')
  if empty(l:dir) || !isdirectory(l:dir)
    echoerr 'yurii_PKM: folder not found: ' . l:dir
    return
  endif
  call s:run_gallery_command(['--open-folder', l:dir], fnamemodify(l:dir, ':t'))
endfunction

function! yurii_pkm#open_gallery(...) abort
  let l:file = a:0 >= 1 && !empty(a:1) ? a:1 : expand('%:p')
  if empty(l:file)
    echoerr 'yurii_PKM: Gallery requires a Markdown file'
    return
  endif
  let l:file = fnamemodify(expand(l:file), ':p')
  if !filereadable(l:file)
    echoerr 'yurii_PKM: file not found: ' . l:file
    return
  endif
  if l:file !~? '\.md$'
    echoerr 'yurii_PKM: Gallery can only open Markdown files'
    return
  endif
  if get(g:, 'yurii_pkm_auto_save_on_command', 1) && expand('%:p') ==# l:file && &modified
    silent write
  endif
  let l:args = ['--open', l:file]
  let l:root = s:gallery_root()
  if !empty(l:root)
    call extend(l:args, ['--root', l:root])
  endif
  call s:run_gallery_command(l:args, fnamemodify(l:file, ':t'))
endfunction


function! yurii_pkm#open_gallery_smart() abort
  if s:is_markdown_file(expand('%:p')) && s:buffer_has_image_link()
    call yurii_pkm#open_gallery()
  else
    call yurii_pkm#open_folder_gallery()
  endif
endfunction
