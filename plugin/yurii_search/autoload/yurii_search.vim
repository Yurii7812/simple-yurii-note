" autoload/yurii_search.vim
" ファイル単位のキーワード AND 検索。ネイティブのポップアップ。
" 一度に 10 件だけ表示し、下に「残り N 件」を出す。
" ヒット語は一覧・プレビュー（ポップアップ内）だけで強調する。
" 開いた先のバッファには一切ハイライトを残さない（最初のヒット行へ寄せるだけ）。
"
" 入力モード（既定）:
"   打つ            … 絞り込み（タイトル+本文、全角スペースも区切り）
"   <C-j>/<C-k>     … 1 ページ送り / 戻し
"   ↑ / ↓          … カーソル 1 件移動
"   <Tab>          … 選択モードへ
"   <CR>           … カーソル行を開く
" 選択モード（<Tab> で切替）:
"   h / l          … 10 件（区間）ずつ移動
"   j / k          … 1 件ずつ移動
"   g              … 先頭へ
"   1-9 / 0        … その番号の行へ（0 = 10 件目）。同じ数字をもう一度で開く
"   <CR>           … カーソル行を開く
" 共通:
"   <Esc>/<C-c>    … 閉じる
"   <BS>           … 1 文字消す

let s:cands = []      " [{p,t,b}]
let s:query = ''
let s:hits  = []      " s:cands の index
let s:sel   = 0       " s:hits 内の位置
let s:top   = 0       " 表示の先頭（s:hits 内）
let s:win   = -1
let s:pvwin = -1
let s:rows  = 15
let s:mode  = 'input'   " 'input' = 打つと絞り込み / 'pick' = 数字で行を開く
" ポップアップ内のヒット強調用。reverse なら配色を問わず必ず見える。
function! yurii_search#ensure_hl_group() abort
  highlight default YuriiSearchMatch term=reverse cterm=reverse gui=reverse
  if empty(prop_type_get('yuriiSearchMatch'))
    call prop_type_add('yuriiSearchMatch', {'highlight': 'YuriiSearchMatch', 'combine': v:true})
  endif
endfunction
call yurii_search#ensure_hl_group()
augroup yurii_search_hl
  autocmd!
  autocmd ColorScheme * call yurii_search#ensure_hl_group()
augroup END

" 現在の検索語（全角スペースも区切り）
function! s:terms() abort
  return filter(split(substitute(s:query, '　', ' ', 'g'), ' '), 'v:val !=# ""')
endfunction

" popup_settext は「全部文字列」か「全部 Dict」でないと弾く。混在を正す。
function! s:settext(winid, lines) abort
  if a:winid < 0 | return | endif
  if empty(filter(copy(a:lines), 'type(v:val) == v:t_dict'))
    call popup_settext(a:winid, a:lines)
  else
    call popup_settext(a:winid, map(copy(a:lines),
          \ 'type(v:val) == v:t_dict ? v:val : {"text": v:val}'))
  endif
endfunction

" a:text 内の各語の出現位置を text-property のリストにする。
" a:prefix_len … 行頭に既に付けた接頭辞のバイト数（番号など）。
function! s:hit_props(text, prefix_len, terms) abort
  let l:props = []
  for l:t in a:terms
    let l:tl = strlen(l:t)
    if l:tl == 0 | continue | endif
    let l:from = 0
    while 1
      let l:idx = stridx(a:text, l:t, l:from)
      if l:idx < 0 | break | endif
      call add(l:props, {'col': a:prefix_len + l:idx + 1, 'length': l:tl,
            \ 'type': 'yuriiSearchMatch'})
      let l:from = l:idx + l:tl
    endwhile
  endfor
  return l:props
endfunction

" gs は yurii_PKM の統一ナビゲータ（global スコープ）に寄せた。
" 一覧・プレビュー・キー体系が <Space> と同じになり、ヒットから l でそのまま
" 潜れる。旧ポップアップに戻したい時だけ g:yurii_search_legacy = 1。
function! yurii_search#run(...) abort
  if !get(g:, 'yurii_search_legacy', 0) && exists('*yurii_pkm#note_navigator')
    call yurii_pkm#note_navigator('global')
    return
  endif
  return call('yurii_search#run_legacy', a:000)
endfunction

function! yurii_search#run_legacy(...) abort
  let l:idx = get(g:, 'yurii_search_index', '')
  if empty(l:idx) || !filereadable(l:idx)
    " python ヘルパーが無ければ旧 TUI
    call s:tui_run()
    return
  endif
  let l:root = get(g:, 'yurii_pkm_root', '')
  if empty(l:root) || !isdirectory(l:root)
    let l:root = getcwd()
  endif
  let l:raw = systemlist('python3 ' . shellescape(l:idx) . ' ' . shellescape(l:root))
  let s:cands = []
  for l:ln in l:raw
    let l:f = split(l:ln, "\t", 1)
    if len(l:f) >= 2
      call add(s:cands, {'p': l:f[0], 't': l:f[1], 'b': get(l:f, 2, '')})
    endif
  endfor
  if empty(s:cands)
    echo 'yurii_search: ノートが見つかりません（' . l:root . '）'
    return
  endif

  let s:query = a:0 > 0 ? a:1 : ''
  let s:mode = 'input'
  let s:sel = 0
  let s:top = 0
  call s:refilter()

  let s:rows = 10
  let l:h = s:rows + 5          " query + hr + 10行 + hr + 件数/文脈 + ヒント
  let l:w = min([float2nr(&columns * 0.42), 70])
  let l:pv = min([float2nr(&columns * 0.42), 80])
  let l:col = max([(&columns - (l:w + 3 + l:pv)) / 2, 2])
  let l:line = max([(&lines - l:h) / 2, 1])

  let s:win = popup_create([], {
        \ 'line': l:line, 'col': l:col,
        \ 'minwidth': l:w, 'maxwidth': l:w,
        \ 'minheight': l:h, 'maxheight': l:h,
        \ 'border': [], 'borderchars': ['─','│','─','│','╭','╮','╯','╰'],
        \ 'borderhighlight': ['Comment'], 'padding': [0,1,0,1],
        \ 'title': ' 検索 ', 'zindex': 300,
        \ 'mapping': 0, 'filter': function('s:key'), 'callback': function('s:done'),
        \ })
  let s:pvwin = popup_create([], {
        \ 'line': l:line, 'col': l:col + l:w + 3,
        \ 'minwidth': l:pv, 'maxwidth': l:pv,
        \ 'minheight': l:h, 'maxheight': l:h,
        \ 'border': [], 'borderchars': ['─','│','─','│','╭','╮','╯','╰'],
        \ 'borderhighlight': ['Comment'], 'padding': [0,1,0,1],
        \ 'title': ' プレビュー ', 'zindex': 299,
        \ })
  call s:render()
endfunction

" --- フィルタ ---------------------------------------------------------------
function! s:refilter() abort
  let l:q = substitute(s:query, '　', ' ', 'g')
  let l:terms = filter(split(l:q, ' '), 'v:val !=# ""')
  let s:hits = []
  let l:i = 0
  for l:c in s:cands
    let l:hay = l:c.t . ' ' . l:c.b
    let l:ok = 1
    for l:t in l:terms
      if stridx(l:hay, l:t) < 0
        let l:ok = 0 | break
      endif
    endfor
    if l:ok | call add(s:hits, l:i) | endif
    let l:i += 1
  endfor
  if s:sel >= len(s:hits) | let s:sel = max([0, len(s:hits) - 1]) | endif
  if s:sel < s:top | let s:top = s:sel | endif
  if s:sel >= s:top + s:rows | let s:top = s:sel - s:rows + 1 | endif
  if s:top < 0 | let s:top = 0 | endif
endfunction

" --- 描画 -----------------------------------------------------------------
function! s:render() abort
  if s:win < 0 | return | endif
  let l:tag = (s:mode ==# 'pick') ? '[選択] ' : ''
  let l:bar = repeat('─', 58)
  let l:terms = s:terms()
  let l:lines = [l:tag . '> ' . s:query . '▏', l:bar]
  if empty(s:hits)
    call add(l:lines, '  (該当なし)')
    " 10 行ぶん高さを埋める
    call extend(l:lines, repeat([''], s:rows - 1))
  else
    let l:end = min([s:top + s:rows, len(s:hits)])
    let l:n = 1
    for l:vi in range(s:top, l:end - 1)
      let l:c = s:cands[s:hits[l:vi]]
      let l:num = (l:n <= 9) ? l:n : (l:n == 10 ? 0 : ' ')
      let l:mark = (l:vi == s:sel) ? '▶' : ' '
      let l:pfx = printf('%s%s ', l:mark, l:num)
      let l:props = s:hit_props(l:c.t, strlen(l:pfx), l:terms)
      call add(l:lines, empty(l:props)
            \ ? l:pfx . l:c.t
            \ : {'text': l:pfx . l:c.t, 'props': l:props})
      let l:n += 1
    endfor
    call extend(l:lines, repeat([''], s:rows - (l:end - s:top)))
  endif
  " 上下に何件あるか
  let l:above = s:top
  let l:below = max([0, len(s:hits) - (s:top + s:rows)])
  let l:ctx = (l:above > 0 ? '↑ 上 ' . l:above . ' 件   ' : '')
        \ . (l:below > 0 ? '残り ' . l:below . ' 件' : '')
  let l:hint = (s:mode ==# 'pick')
        \ ? 'hl ページ  jk 1件  数字=見る 同数字=開く  ⇥ 入力  ⎋ 閉じる'
        \ : '打つ=絞込  ⇥ 選択へ  ^J^K ページ  ↑↓ 1件  ⏎ 開く  ⎋ 閉じる'
  call add(l:lines, l:bar)
  call add(l:lines, printf('%d/%d  %s', empty(s:hits) ? 0 : s:sel + 1, len(s:hits),
        \ empty(l:ctx) ? l:hint : l:ctx))
  call add(l:lines, l:hint)
  call s:settext(s:win, l:lines)
  call popup_setoptions(s:win, {'title': s:mode ==# 'pick' ? ' 選択 ' : ' 検索 '})
  call s:preview()
endfunction

function! s:preview() abort
  if s:pvwin < 0 | return | endif
  if empty(s:hits)
    call popup_settext(s:pvwin, ['(なし)'])
    return
  endif
  let l:c = s:cands[s:hits[s:sel]]
  let l:q = substitute(s:query, '　', ' ', 'g')
  let l:terms = filter(split(l:q, ' '), 'v:val !=# ""')
  let l:body = readfile(l:c.p, '', 400)
  if empty(l:terms)
    call popup_settext(s:pvwin, l:body[0:300])
    return
  endif
  " ヒット行 ± 前後 2 行
  let l:show = []
  let l:i = 0
  for l:ln in l:body
    for l:t in l:terms
      if stridx(l:ln, l:t) >= 0
        for l:j in range(max([0, l:i - 2]), min([len(l:body) - 1, l:i + 2]))
          if index(l:show, l:j) < 0 | call add(l:show, l:j) | endif
        endfor
        break
      endif
    endfor
    let l:i += 1
  endfor
  call sort(l:show, 'n')
  if empty(l:show)
    call popup_settext(s:pvwin, l:body[0:300])
    return
  endif
  let l:out = []
  let l:prev = -2
  for l:j in l:show
    if l:j > l:prev + 1 && !empty(l:out) | call add(l:out, '  ⋯') | endif
    let l:pfx = printf('%4d ', l:j + 1)
    let l:props = s:hit_props(l:body[l:j], strlen(l:pfx), l:terms)
    call add(l:out, empty(l:props)
          \ ? l:pfx . l:body[l:j]
          \ : {'text': l:pfx . l:body[l:j], 'props': l:props})
    let l:prev = l:j
  endfor
  call s:settext(s:pvwin, l:out)
endfunction

" --- キー処理 -----------------------------------------------------------------
function! s:key(winid, key) abort
  if a:key ==# "\<Esc>" || a:key ==# "\<C-c>"
    call popup_close(a:winid, -1)
    return 1
  elseif a:key ==# "\<CR>"
    call popup_close(a:winid, empty(s:hits) ? -1 : s:hits[s:sel])
    return 1
  elseif a:key ==# "\<C-j>" || a:key ==# "\<C-f>" || a:key ==# "\<PageDown>"
    " 1 ページ送り（表示範囲ごと進める）
    if s:top + s:rows < len(s:hits)
      let s:top += s:rows
    endif
    let s:sel = s:top
  elseif a:key ==# "\<C-k>" || a:key ==# "\<C-b>" || a:key ==# "\<PageUp>"
    let s:top = max([s:top - s:rows, 0])
    let s:sel = s:top
  elseif a:key ==# "\<Down>"
    let s:sel = min([s:sel + 1, max([0, len(s:hits) - 1])])
  elseif a:key ==# "\<Up>"
    let s:sel = max([s:sel - 1, 0])
  elseif a:key ==# "\<Tab>"
    let s:mode = (s:mode ==# 'pick') ? 'input' : 'pick'
  elseif a:key ==# "\<BS>" || a:key ==# "\<C-h>"
    let s:query = strcharpart(s:query, 0, strchars(s:query) - 1)
    let s:sel = 0 | let s:top = 0
  elseif a:key ==# "\<C-w>" || a:key ==# "\<C-u>"
    let s:query = '' | let s:sel = 0 | let s:top = 0
  elseif s:mode ==# 'pick' && a:key =~# '^[0-9]$'
    " 選択モード: 数字 1 回目=その行へ（プレビュー）、同じ数字 2 回目=開く
    let l:row = (a:key ==# '0') ? 10 : str2nr(a:key)
    let l:target = s:top + l:row - 1
    if l:target >= 0 && l:target < len(s:hits)
      if s:sel == l:target
        call popup_close(a:winid, s:hits[l:target])
        return 1
      endif
      let s:sel = l:target
    endif
  elseif s:mode ==# 'pick' && (a:key ==# 'l' || a:key ==# 'h')
    " 選択モード: h/l で 10 件（区間）ずつ移動
    if a:key ==# 'l'
      if s:top + s:rows < len(s:hits)
        let s:top += s:rows
      endif
    else
      let s:top = max([s:top - s:rows, 0])
    endif
    let s:sel = s:top
  elseif s:mode ==# 'pick' && (a:key ==# 'j' || a:key ==# 'k' || a:key ==# 'g')
    " 選択モード: j/k で 1 件ずつ
    if a:key ==# 'j'
      let s:sel = min([s:sel + 1, max([0, len(s:hits) - 1])])
    elseif a:key ==# 'k'
      let s:sel = max([s:sel - 1, 0])
    else
      let s:sel = 0
    endif
  elseif s:mode ==# 'input' && strchars(a:key) == 1 && a:key !~# '[[:cntrl:]]'
    " 入力モード: 文字（数字含む）を検索語へ
    let s:query .= a:key
    let s:sel = 0 | let s:top = 0
  else
    return 1
  endif
  call s:refilter()
  call s:render()
  return 1
endfunction

function! s:done(winid, result) abort
  let s:win = -1
  if s:pvwin >= 0
    call popup_close(s:pvwin)
    let s:pvwin = -1
  endif
  if type(a:result) != v:t_number || a:result < 0 || a:result >= len(s:cands)
    return
  endif
  let l:terms = s:terms()
  execute 'edit ' . fnameescape(s:cands[a:result].p)
  " ハイライトはしない（ポップアップ内だけ）。最初のヒット行へ寄せるだけ。
  if empty(l:terms) | return | endif
  let l:fallback = 0
  for l:lnum in range(1, line('$'))
    let l:ln = getline(l:lnum)
    let l:all = 1
    for l:t in l:terms
      if stridx(l:ln, l:t) < 0 | let l:all = 0 | break | endif
    endfor
    if l:all
      call cursor(l:lnum, 1)
      execute 'normal! zvzz'
      return
    endif
    if l:fallback == 0
      for l:t in l:terms
        if stridx(l:ln, l:t) >= 0 | let l:fallback = l:lnum | break | endif
      endfor
    endif
  endfor
  if l:fallback > 0
    call cursor(l:fallback, 1)
    execute 'normal! zvzz'
  endif
endfunction

" --- 旧 curses TUI（python ヘルパーが無い時のみ）----------------------------
function! s:tui_run() abort
  let l:script = get(g:, 'yurii_search_tui', '')
  if !filereadable(l:script)
    echoerr 'notes_index.py も fsearch_tui.py も見つかりません'
    return
  endif
  let l:tmpfile = tempname()
  let l:cmd = 'python3 ' . shellescape(l:script) . ' ' . shellescape(getcwd())
        \ . ' ' . shellescape(l:tmpfile)
  call term_start(['/bin/bash', '-c', l:cmd], {
        \ 'term_finish': 'close',
        \ 'exit_cb': function('s:tui_done', [l:tmpfile]),
        \ })
endfunction

function! s:tui_done(tmpfile, job, status) abort
  if !filereadable(a:tmpfile) | return | endif
  let l:sel = trim(join(readfile(a:tmpfile), ''))
  call delete(a:tmpfile)
  if l:sel != '' | execute 'edit ' . fnameescape(l:sel) | endif
endfunction
