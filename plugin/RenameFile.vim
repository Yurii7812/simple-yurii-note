" Rename current file
function! s:RenameFile()
    let old_name = expand('%')
    let new_name = input('New file name: ', expand('%'), 'file')
    if new_name != '' && new_name != old_name
        execute 'saveas ' . fnameescape(new_name)
        execute 'call delete(fnameescape("' . old_name . '"))'
        redraw!
    endif
endfunction

command! Rename call s:RenameFile()