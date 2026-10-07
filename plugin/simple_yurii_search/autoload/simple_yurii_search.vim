" autoload/simple_yurii_search.vim
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
function! simple_yurii_search#ensure_hl_group() abort
  highlight default SimpleSearchMatch term=reverse cterm=reverse gui=reverse
  if empty(prop_type_get('yuriiSearchMatch'))
    call prop_type_add('yuriiSearchMatch', {'highlight': 'SimpleSearchMatch', 'combine': v:true})
  endif
endfunction
call simple_yurii_search#ensure_hl_group()
augroup simple_yurii_search_hl
  autocmd!
  autocmd ColorScheme * call simple_yurii_search#ensure_hl_group()
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

" gs / :FSearch … 全ノートを fzf で一覧（タイトル表示・タイトル＋本文で検索）。
" 旧ポップアップ（note_navigator）はもう呼ばない。fzf 前提（フォールバック無し）。
" run_legacy / g:simple_yurii_search_legacy は互換のため残置（既定経路ではない）。
function! simple_yurii_search#run(...) abort
  call simple_yurii_search#search_global()
endfunction

" ===========================================================================
" fzf バックエンド
"   - gs        … vault を全文検索（note_search.py。タイトル優先・表示はタイトル＋抜粋）
"   - <Space>   … 今のノートのリンク先を検索（タイトル優先＋本文）→ Enter で開く
"   - \L         … 全文検索（タイトル優先・表示はタイトル）→ Enter でリンク挿入
"   検索・並び・強調は python、fzf は --disabled で表示に徹する（change:reload）。
"   fzf / fzf.vim が無い環境ではフォールバックせず明示的にエラーにする。
" ===========================================================================

function! s:fzf_ok() abort
  if !exists('*fzf#run')
    echoerr 'simple_yurii_search: fzf.vim が見つかりません（プラグインを入れてください）'
    return 0
  endif
  if !executable('fzf')
    echoerr 'simple_yurii_search: fzf コマンドが見つかりません（~/.local/bin などに導入してください）'
    return 0
  endif
  return 1
endfunction

function! s:root() abort
  let l:root = get(g:, 'simple_yurii_note_root', '')
  if !empty(l:root) && isdirectory(expand(l:root))
    return fnamemodify(expand(l:root), ':p')
  endif
  return fnamemodify(getcwd(), ':p')
endfunction

" 全ノートを [{p,t,b}] で返す。notes_index.py が無ければ glob＋ファイル名で代替。
function! s:build_notes(root) abort
  let l:notes = []
  let l:idx = get(g:, 'simple_yurii_search_index', '')
  if !empty(l:idx) && filereadable(l:idx) && executable('python3')
    for l:ln in systemlist('python3 ' . shellescape(l:idx) . ' ' . shellescape(a:root))
      let l:f = split(l:ln, "\t", 1)
      if len(l:f) >= 2
        call add(l:notes, {'p': l:f[0], 't': l:f[1], 'b': get(l:f, 2, '')})
      endif
    endfor
  endif
  if empty(l:notes)
    for l:p in split(globpath(a:root, '**/*.md'), "\n")
      if l:p =~# '[\\/]\.undo[\\/]' | continue | endif
      call add(l:notes, {'p': l:p, 't': fnamemodify(l:p, ':t:r'), 'b': ''})
    endfor
  endif
  return l:notes
endfunction

" 今のバッファに表示されている Markdown リンクだけを [{p,t}] で返す。
function! s:current_buffer_links() abort
  let l:entries = []
  let l:seen = {}
  let l:base = expand('%:p:h')
  let l:pat = '\v\[([^\]]+)\]\(([^)]+)\)'
  for l:ln in getline(1, '$')
    let l:start = 0
    while 1
      let l:m = matchstrpos(l:ln, l:pat, l:start)
      if l:m[1] < 0 | break | endif
      let l:start = l:m[2]
      let l:parts = matchlist(l:m[0], l:pat)
      let l:text = get(l:parts, 1, '')
      let l:target = get(l:parts, 2, '')
      if empty(l:target) || l:target =~? '^\(https\?\|mailto\|file\):'
        continue
      endif
      let l:path = simple_yurii_note#resolve_link(l:target, l:base)
      if empty(l:path) || has_key(l:seen, l:path)
        continue
      endif
      let l:seen[l:path] = 1
      call add(l:entries, {'p': l:path,
            \ 't': empty(l:text) ? fnamemodify(l:path, ':t:r') : l:text})
    endwhile
  endfor
  return l:entries
endfunction

" <Space> とフォールバック用の fzf オプション。
" 検索バーは gs（note_search.py 経路）と同じ**下**に置く（--layout=reverse を付けない）。
" 注意: --nth は --with-nth の変換後に効くので、検索対象＝表示対象に揃える。
"   <Space> … --with-nth=2（タイトルだけ表示＝タイトル検索）/ 出力はパス
function! s:fzf_options(with, accept, prompt) abort
  return '--delimiter="\t" --with-nth=' . a:with . ' --accept-nth=' . a:accept
        \ . ' --height=90% --prompt=' . shellescape(a:prompt)
        \ . ' --color=hl:red:bold,hl+:red:bold'
        \ . ' --preview "sed -n ''1,200p'' -- {1}" --preview-window=right:50%'
endfunction

function! s:fzf_run(entries, Sink, options) abort
  call fzf#run(fzf#wrap({
        \ 'source': a:entries,
        \ 'sink': a:Sink,
        \ 'options': a:options,
        \ }))
endfunction

function! s:open_selected(line) abort
  let l:path = get(split(a:line, "\t", 1), 0, '')
  if empty(l:path) || !filereadable(l:path) | return | endif
  execute 'edit ' . fnameescape(l:path)
endfunction

" 右ペイン用のハイライトスクリプト（クエリ語を ANSI 強調）を返す。
function! s:preview_script() abort
  let l:p = get(g:, 'simple_yurii_search_preview', '')
  return (!empty(l:p) && filereadable(l:p)) ? l:p : ''
endfunction

" \L の確定処理。fzf.vim の sink* 形式（先頭は押したキー）で [パス:タイトル,...] を受ける。
function! s:link_sink(lines) abort
  if len(a:lines) < 2 | return | endif
  if exists('s:insert_buf') && bufnr('%') != s:insert_buf
    execute 'buffer ' . s:insert_buf
  endif
  if exists('s:insert_pos')
    call cursor(s:insert_pos[1], s:insert_pos[2])
  endif
  let l:links = []
  for l:line in a:lines[1:]
    let l:line = substitute(l:line, '\e\[[0-9;]*m', '', 'g')
    let l:sep = stridx(l:line, ':')
    if l:sep <= 0 | continue | endif
    let l:path = strpart(l:line, 0, l:sep)
    let l:title = strpart(l:line, l:sep + 1)
    if !filereadable(l:path) | continue | endif
    call add(l:links, simple_yurii_note#make_link(l:path, l:title))
  endfor
  if empty(l:links) | return | endif
  let l:link = join(l:links, ' ')
  let l:cur = getline('.')
  let l:col = col('.') - 1
  call setline('.', strpart(l:cur, 0, l:col) . l:link . strpart(l:cur, l:col))
  call cursor(line('.'), l:col + strlen(l:link) + 1)
endfunction

" フォールバック用（fzf の 'sink' 形式・1 行 = パス<TAB>タイトル）。
function! s:insert_selected(line) abort
  let l:f = split(a:line, "\t", 1)
  let l:path = get(l:f, 0, '')
  let l:title = get(l:f, 1, '')
  if empty(l:path) | return | endif
  if exists('s:insert_buf') && bufnr('%') != s:insert_buf
    execute 'buffer ' . s:insert_buf
  endif
  if exists('s:insert_pos')
    call cursor(s:insert_pos[1], s:insert_pos[2])
  endif
  let l:link = simple_yurii_note#make_link(l:path, l:title)
  let l:cur = getline('.')
  let l:col = col('.') - 1
  call setline('.', strpart(l:cur, 0, l:col) . l:link . strpart(l:cur, l:col))
  call cursor(line('.'), l:col + strlen(l:link) + 1)
endfunction

" note_search.py（タイトル優先の全文検索）の起動コマンド。無ければ空。
" a:1 に追加引数（例: "--only '/tmp/xxx'"）を渡せる。
function! s:note_search_cmd(...) abort
  let l:script = get(g:, 'simple_yurii_search_notesearch', '')
  if empty(l:script) || !filereadable(l:script) || !executable('python3')
    return ''
  endif
  let l:extra = a:0 > 0 ? a:1 . ' ' : ''
  return 'python3 ' . shellescape(l:script) . ' ' . l:extra . shellescape(s:root())
endfunction

function! s:strip_ansi(text) abort
  return substitute(a:text, '\e\[[0-9;]*m', '', 'g')
endfunction

" 検索結果 1 行（path<TAB>title<TAB>line<TAB>excerpt）を分解する。
function! s:parse_note_line(line) abort
  let l:f = split(s:strip_ansi(a:line), "\t", 1)
  return {'path': get(l:f, 0, ''), 'title': get(l:f, 1, ''),
        \ 'line': str2nr(get(l:f, 2, '1')), 'excerpt': get(l:f, 3, '')}
endfunction

" gs の確定: 選んだノートを開き、最初のヒット行へ寄せる。
" この fzf 版の sink* はキー要素なしで選択行だけを渡す（キーらしき要素は
" パスとして解決できないので読み飛ばす）。
function! s:search_open_sink(lines) abort
  for l:line in a:lines
    let l:r = s:parse_note_line(l:line)
    if empty(l:r.path) || !filereadable(l:r.path) | continue | endif
    execute 'edit ' . fnameescape(l:r.path)
    if l:r.line > 1
      execute 'normal! ' . l:r.line . 'Gzz'
    endif
    return
  endfor
endfunction

" \L の確定: 選んだノートへの Markdown リンクをカーソル位置に挿入。
function! s:link_sink_tab(lines) abort
  let l:notes = []
  for l:line in a:lines
    let l:r = s:parse_note_line(l:line)
    if empty(l:r.path) || !filereadable(l:r.path) | continue | endif
    call add(l:notes, l:r)
  endfor
  if empty(l:notes) | return | endif
  if exists('s:insert_buf') && bufnr('%') != s:insert_buf
    execute 'buffer ' . s:insert_buf
  endif
  if exists('s:insert_pos')
    call cursor(s:insert_pos[1], s:insert_pos[2])
  endif
  let l:links = map(copy(l:notes), {_, n -> simple_yurii_note#make_link(n.path, n.title)})
  let l:link = join(l:links, ' ')
  let l:cur = getline('.')
  let l:col = col('.') - 1
  call setline('.', strpart(l:cur, 0, l:col) . l:link . strpart(l:cur, l:col))
  call cursor(line('.'), l:col + strlen(l:link) + 1)
endfunction

" note_search.py + fzf。表示はタイトル（with_nth で抜粋も出せる）。
" 検索・並び（タイトル優先）・強調は python 側。fzf は --disabled で表示に徹する。
function! s:note_search_run(prompt, with_nth, Sink, ...) abort
  let l:cmd = s:note_search_cmd(a:0 > 0 ? a:1 : '')
  if empty(l:cmd) | return 0 | endif
  let l:preview = s:preview_script()
  let l:options = [
        \ '--ansi', '--multi', '--disabled',
        \ '--delimiter=\t', '--with-nth=' . a:with_nth,
        \ '--prompt=' . a:prompt,
        \ '--bind', 'change:reload:' . l:cmd . ' {q}',
        \ ]
  if !empty(l:preview)
    " スクロールは fzf に任せない（+{3}/2 は wrap の折返しを考慮せず、長い行の
    " ヒットが下端で切れる）。preview_highlight.py が --line {3} でヒット行の
    " 少し上から出し、先頭付近に見せる。
    call extend(l:options, [
          \ '--preview', 'python3 ' . shellescape(l:preview) . ' {1} {q} --line {3}',
          \ '--preview-window', 'right:50%:wrap',
          \ ])
  endif
  call fzf#run(fzf#wrap({
        \ 'source': l:cmd . " ''",
        \ 'sink*': a:Sink,
        \ 'options': l:options,
        \ 'dir': s:root(),
        \ }))
  return 1
endfunction

" gs … vault を全文検索（タイトル優先）。左はタイトル、右はヒット箇所をハイライト。
function! simple_yurii_search#search_global() abort
  if !s:fzf_ok() | return | endif
  if s:note_search_run('Search> ', '2', function('s:search_open_sink'))
    return
  endif
  " フォールバック（note_search.py が無い時）: タイトル＋本文の全件リスト
  let l:notes = s:build_notes(s:root())
  if empty(l:notes) | echo 'simple_yurii_search: ノートが見つかりません' | return | endif
  let l:entries = map(copy(l:notes), {_, n -> n.p . "\t" . n.t . "\t" . n.b})
  call s:fzf_run(l:entries, function('s:open_selected'),
        \ s:fzf_options('2,3', '1', 'Search> '))
endfunction

" <Space> … 今のノートのリンク先を検索（タイトル優先。リンク先ノートの本文も対象）→ 開く
function! simple_yurii_search#search_local() abort
  if !s:fzf_ok() | return | endif
  let l:links = s:current_buffer_links()
  if empty(l:links) | echo 'simple_yurii_search: このノートにリンクがありません' | return | endif
  " リンク先ノートの本文も検索対象にする（タイトル優先）。note_search.py を --only で絞る。
  let l:onlyfile = tempname()
  call writefile(map(copy(l:links), {_, n -> n.p}), l:onlyfile)
  if s:note_search_run('Link> ', '2', function('s:search_open_sink'),
        \ '--only ' . shellescape(l:onlyfile))
    return
  endif
  " フォールバック（note_search.py が無い時）: 従来どおりタイトルだけ
  let l:entries = map(copy(l:links), {_, n -> n.p . "\t" . n.t})
  call s:fzf_run(l:entries, function('s:open_selected'),
        \ s:fzf_options('2', '1', 'Link> '))
endfunction

" \L … 全ノートを全文検索（タイトル優先・表示はタイトル）→ カーソル位置にリンク挿入。
function! simple_yurii_search#pick_insert_link() abort
  if !s:fzf_ok() | return | endif
  let s:insert_buf = bufnr('%')
  let s:insert_pos = getpos('.')
  if s:note_search_run('Title> ', '2', function('s:link_sink_tab'))
    return
  endif
  " フォールバック: 旧タイトルピッカー（タイトル検索・fzf 任せ）
  let l:notes = s:build_notes(s:root())
  if empty(l:notes) | echo 'simple_yurii_search: ノートが見つかりません' | return | endif
  let l:entries = map(copy(l:notes), {_, n -> n.p . "\t" . n.t})
  call s:fzf_run(l:entries, function('s:insert_selected'),
        \ s:fzf_options('2', '1,2', 'Title> '))
endfunction

" \L（ビジュアル）… 選択範囲を検索で選んだノートへのリンクで置き換える。
" リンクの表示テキストは選択していた文字列（空ならノートタイトル）。
function! simple_yurii_search#pick_insert_link_visual() abort range
  if !s:fzf_ok() | return | endif
  let s:vis = {}
  let s:vis.is_linewise = (visualmode() ==# 'V')
  let s:vis.sline = line("'<")
  let s:vis.eline = line("'>")
  let s:vis.scol  = col("'<")
  let s:vis.ecol  = col("'>")
  if s:vis.sline <= 0 || s:vis.eline <= 0
    echo 'No visual selection'
    return
  endif
  if s:vis.sline > s:vis.eline || (s:vis.sline == s:vis.eline && s:vis.scol > s:vis.ecol)
    let [s:vis.sline, s:vis.eline] = [s:vis.eline, s:vis.sline]
    let [s:vis.scol, s:vis.ecol] = [s:vis.ecol, s:vis.scol]
  endif
  let s:vis.lines = getline(s:vis.sline, s:vis.eline)
  if empty(s:vis.lines)
    echo 'No visual selection'
    return
  endif
  if s:vis.is_linewise
    let l:selected = join(s:vis.lines, "\n")
  elseif len(s:vis.lines) == 1
    let l:start_char = charidx(s:vis.lines[0], s:vis.scol - 1)
    let l:end_char = charidx(s:vis.lines[0], s:vis.ecol - 1) + 1
    let l:selected = strcharpart(s:vis.lines[0], l:start_char, l:end_char - l:start_char)
  else
    let l:sel_lines = copy(s:vis.lines)
    let l:first_start = charidx(l:sel_lines[0], s:vis.scol - 1)
    let l:last_end = charidx(l:sel_lines[-1], s:vis.ecol - 1) + 1
    let l:sel_lines[0] = strcharpart(l:sel_lines[0], l:first_start)
    let l:sel_lines[-1] = strcharpart(l:sel_lines[-1], 0, l:last_end)
    let l:selected = join(l:sel_lines, "\n")
  endif
  let s:vis.text = trim(substitute(l:selected, '\n\+', ' ', 'g'))
  let s:insert_buf = bufnr('%')
  let s:insert_pos = [s:vis.sline, s:vis.scol]
  call s:note_search_run('Link> ', '2', function('s:link_sink_visual'))
endfunction

" ビジュアル \L の確定: 選択範囲をリンクで置き換える。
function! s:link_sink_visual(lines) abort
  if !exists('s:vis') | return | endif
  for l:line in a:lines
    let l:r = s:parse_note_line(l:line)
    if empty(l:r.path) || !filereadable(l:r.path) | continue | endif
    if exists('s:insert_buf') && bufnr('%') != s:insert_buf
      execute 'buffer ' . s:insert_buf
    endif
    let l:label = !empty(s:vis.text) ? s:vis.text : l:r.title
    let l:link = simple_yurii_note#make_link(l:r.path, l:label)
    call simple_yurii_note#replace_visual_selection(
          \ l:link, s:vis.is_linewise, s:vis.sline, s:vis.eline,
          \ s:vis.scol, s:vis.ecol, s:vis.lines)
    call cursor(s:vis.sline, s:vis.scol)
    return
  endfor
endfunction

function! simple_yurii_search#run_legacy(...) abort
  let l:idx = get(g:, 'simple_yurii_search_index', '')
  if empty(l:idx) || !filereadable(l:idx)
    " python ヘルパーが無ければ旧 TUI
    call s:tui_run()
    return
  endif
  let l:root = get(g:, 'simple_yurii_note_root', '')
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
    echo 'simple_yurii_search: ノートが見つかりません（' . l:root . '）'
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
  let l:script = get(g:, 'simple_yurii_search_tui', '')
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
