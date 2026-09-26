command! -nargs=+ FileContentSearch call s:file_content_search(<q-args>)

function! s:file_content_search(query) abort
  let tokens = split(tolower(a:query))
  let files = systemlist(['rg', '--files'])
  let items = []

  for f in files
    if !filereadable(f)
      continue
    endif

    let lines = readfile(f)
    let text  = tolower(join(lines, "\n"))

    let ok = 1
    for t in tokens
      if stridx(text, t) < 0
        let ok = 0
        break
      endif
    endfor

    if ok
      let best_lnum = 1
      let preview = ''

      for i in range(len(lines))
        let l = tolower(lines[i])
        for t in tokens
          if stridx(l, t) >= 0
            let best_lnum = i + 1
            let preview = lines[i]
            break
          endif
        endfor
        if preview !=# ''
          break
        endif
      endfor

      call add(items, {
            \ 'filename': f,
            \ 'lnum': best_lnum,
            \ 'col': 1,
            \ 'text': '[file-hit] ' . preview
            \ })
    endif
  endfor

  call setqflist(items, 'r', {'title': 'FileContentSearch: ' . a:query})
  copen
endfunction