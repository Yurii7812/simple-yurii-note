" SetImageSize - マークダウン画像記法/ファイル名/imgタグをHTMLのimgタグに変換・編集

let s:image_ext_pattern = '\c\%(jpe\?g\|png\|gif\|webp\|avif\|svg\|bmp\|tiff\?\|heic\|heif\|jfif\|ico\|apng\)'
let s:file_pattern = '[^[:space:]<>"''`\[\]]\+\.' . s:image_ext_pattern . '\%([?#][^[:space:]<>"''`]*\)\?'
let s:img_pattern = '<img\s\+[^>]*src\s*=\s*["'']\([^"'']\+\)["''][^>]*>'
let s:md_image_pattern = '!\[\([^\]]*\)\](\([^)]\+\))'

function! s:BuildImgTag(src, size) abort
  return '<img src="' . a:src . '" width="' . a:size . '">'
endfunction

function! s:FindImgTagAt(line, col) abort
  let l:pos = 0
  while 1
    let l:match = matchstrpos(a:line, s:img_pattern, l:pos)
    if l:match[1] == -1
      return ['', -1, -1]
    endif
    if a:col >= l:match[1] + 1 && a:col <= l:match[2]
      let l:src = substitute(l:match[0], s:img_pattern, '\1', '')
      return [l:src, l:match[1], l:match[2]]
    endif
    let l:pos = l:match[2]
  endwhile
endfunction

function! s:FindMarkdownImageAt(line, col) abort
  let l:pos = 0
  while 1
    let l:match = matchstrpos(a:line, s:md_image_pattern, l:pos)
    if l:match[1] == -1
      return ['', -1, -1]
    endif
    if a:col >= l:match[1] + 1 && a:col <= l:match[2]
      let l:src = substitute(l:match[0], s:md_image_pattern, '\2', '')
      return [l:src, l:match[1], l:match[2]]
    endif
    let l:pos = l:match[2]
  endwhile
endfunction

function! s:FindPlainImageAt(line, col) abort
  let l:pos = 0
  while 1
    let l:match = matchstrpos(a:line, s:file_pattern, l:pos)
    if l:match[1] == -1
      return ['', -1, -1]
    endif
    if a:col >= l:match[1] + 1 && a:col <= l:match[2]
      return [l:match[0], l:match[1], l:match[2]]
    endif
    let l:pos = l:match[2]
  endwhile
endfunction

function! s:FindImageAtCursor(line, col) abort
  let l:found = s:FindImgTagAt(a:line, a:col)
  if l:found[1] != -1
    return l:found
  endif

  let l:found = s:FindMarkdownImageAt(a:line, a:col)
  if l:found[1] != -1
    return l:found
  endif

  let l:found = s:FindPlainImageAt(a:line, a:col)
  if l:found[1] != -1
    return l:found
  endif

  return ['', -1, -1]
endfunction

function! s:UpdateImgTag(match, size) abort
  if a:match =~# '\c\swidth\s*='
    return substitute(a:match, '\c\swidth\s*=\s*["''][^"'']*["'']', ' width="' . a:size . '"', '')
  endif

  if a:match =~# '/\s*>\s*$'
    return substitute(a:match, '\s*/\s*>\s*$', ' width="' . a:size . '" />', '')
  endif

  return substitute(a:match, '>\s*$', ' width="' . a:size . '">', '')
endfunction

function! s:UpdateMarkdownImage(match, size) abort
  let l:src = substitute(a:match, s:md_image_pattern, '\2', '')
  return s:BuildImgTag(l:src, a:size)
endfunction

function! s:IsInsideSpan(spans, start, end) abort
  for l:span in a:spans
    if a:start >= l:span[0] && a:end <= l:span[1]
      return 1
    endif
  endfor
  return 0
endfunction

function! s:ProtectedSpans(line) abort
  let l:spans = []
  for l:pattern in [s:img_pattern, s:md_image_pattern, '\[[^\]]*\]([^)]*)']
    let l:pos = 0
    while 1
      let l:match = matchstrpos(a:line, l:pattern, l:pos)
      if l:match[1] == -1
        break
      endif
      call add(l:spans, [l:match[1], l:match[2]])
      let l:pos = l:match[2]
    endwhile
  endfor
  return l:spans
endfunction

function! s:ReplacePlainImages(line, size) abort
  let l:spans = s:ProtectedSpans(a:line)
  let l:out = ''
  let l:pos = 0
  let l:changed = 0

  while 1
    let l:match = matchstrpos(a:line, s:file_pattern, l:pos)
    if l:match[1] == -1
      break
    endif
    if s:IsInsideSpan(l:spans, l:match[1], l:match[2])
      let l:out .= strpart(a:line, l:pos, l:match[2] - l:pos)
    else
      let l:out .= strpart(a:line, l:pos, l:match[1] - l:pos)
      let l:out .= s:BuildImgTag(l:match[0], a:size)
      let l:changed = 1
    endif
    let l:pos = l:match[2]
  endwhile

  let l:out .= strpart(a:line, l:pos)
  return [l:out, l:changed]
endfunction

function! s:ReplaceImagesInLine(line, size) abort
  let l:line = a:line
  let l:changed = 0

  if l:line =~# s:img_pattern
    let l:line = substitute(l:line, s:img_pattern, '\=s:UpdateImgTag(submatch(0), a:size)', 'g')
    let l:changed = 1
  endif

  if l:line =~# s:md_image_pattern
    let l:line = substitute(l:line, s:md_image_pattern, '\=s:UpdateMarkdownImage(submatch(0), a:size)', 'g')
    let l:changed = 1
  endif

  let l:plain = s:ReplacePlainImages(l:line, a:size)
  if l:plain[1]
    let l:line = l:plain[0]
    let l:changed = 1
  endif

  return [l:line, l:changed]
endfunction

function! s:SetImageSizeLine() abort
  let l:line = getline('.')
  let l:found = s:FindImageAtCursor(l:line, col('.'))

  if l:found[0] ==# ''
    echo 'カーソル位置に画像が見つかりません'
    return
  endif

  let l:size = input('Size: ')
  if l:size ==# ''
    return
  endif

  let l:matched = strpart(l:line, l:found[1], l:found[2] - l:found[1])
  if l:matched =~# '^<img\s'
    let l:replacement = s:UpdateImgTag(l:matched, l:size)
  else
    let l:replacement = s:BuildImgTag(l:found[0], l:size)
  endif

  let l:new_line = strpart(l:line, 0, l:found[1]) . l:replacement . strpart(l:line, l:found[2])
  call setline('.', l:new_line)
endfunction

function! s:SetImageSizeRange(line1, line2) abort
  let l:size = input('Size: ')
  if l:size ==# ''
    return
  endif

  let l:changed = 0
  for l:lnum in range(a:line1, a:line2)
    let l:result = s:ReplaceImagesInLine(getline(l:lnum), l:size)
    if l:result[1]
      call setline(l:lnum, l:result[0])
      let l:changed += 1
    endif
  endfor

  if l:changed == 0
    echo '範囲内に画像が見つかりません'
  endif
endfunction

function! s:SetImageSize(line1, line2, range) abort
  if a:range
    call s:SetImageSizeRange(a:line1, a:line2)
  else
    call s:SetImageSizeLine()
  endif
endfunction

command! -range SetImageSize call s:SetImageSize(<line1>, <line2>, <range>)

nnoremap <nowait> <silent> \i <Cmd>SetImageSize<CR>
xnoremap <nowait> <silent> \i :<C-U>call <SID>SetImageSizeRange(line("'<"), line("'>"))<CR>
