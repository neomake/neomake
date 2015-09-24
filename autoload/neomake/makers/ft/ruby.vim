" vim: ts=4 sw=4 et

function! neomake#makers#ft#ruby#EnabledMakers()
    return ['mri', 'rubocop']
endfunction

function! neomake#makers#ft#ruby#rubocop()
    return {
        \ 'args': ['--format', 'emacs'],
        \ 'errorformat': '%f:%l:%c: %t: %m',
        \ 'postprocess': function('neomake#makers#ft#ruby#RubocopEntryProcess')
        \ }
endfunction

function! neomake#makers#ft#ruby#RubocopEntryProcess(entry)
    if a:entry.type ==# 'F'
        let a:entry.type = 'E'
    elseif a:entry.type !=# 'W' && a:entry.type !=# 'E'
        let a:entry.type = 'W'
    endif
endfunction

function! neomake#makers#ft#ruby#mri()
    let errorformat = '%-G%\m%.%#warning: %\%%(possibly %\)%\?useless use of == in void context,'
    let errorformat .= '%-G%\%.%\%.%\%.%.%#,'
    let errorformat .=
        \ '%-GSyntax OK,'.
        \ '%E%f:%l: syntax error\, %m,'.
        \ '%Z%p^,'.
        \ '%W%f:%l: warning: %m,'.
        \ '%Z%p^,'.
        \ '%W%f:%l: %m,'.
        \ '%-C%.%#'

    return {
        \ 'exe': 'ruby',
        \ 'args': ['-c', '-T1', '-w'],
        \ 'errorformat': errorformat
        \ }
endfunction
