" 公開API(simple_yurii_note#*)の一覧を書き出す。分割リファクタの回帰網。
" 使い方: test/run.sh
" 出力先は g:simple_yurii_note_api_out（既定 /tmp/simple_yurii_note_api.txt）。
set nomore
redir => s:out
silent function /simple_yurii_note#
redir END
let s:names = []
for s:l in split(s:out, "\n")
  let s:m = matchstr(s:l, 'simple_yurii_note#[A-Za-z0-9_#]*')
  if s:m != '' && s:m !~ '#$'
    call add(s:names, s:m)
  endif
endfor
call sort(s:names)
call writefile(s:names, get(g:, 'simple_yurii_note_api_out', '/tmp/simple_yurii_note_api.txt'))
