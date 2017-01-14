" vim: ts=4 sw=4 et

function! neomake#makers#ft#lisp#EnabledMakers() abort
    let makers = []
    if executable('clisp')
        call add(makers, 'clisp')
    endif
    return makers
endfunction

function! neomake#makers#ft#lisp#clisp() abort
    return {
            \ 'exe': 'clisp',
            \ 'errorformat':
                \ '%-G;%.%#,' .
                \ '%W%>WARNING:%.%# line %l : %m,' .
                \ '%Z  %#%m,' .
                \ '%W%>WARNING:%.%# lines %l%\%.%\%.%\d%\+ : %m,' .
                \ '%Z  %#%m,' .
                \ '%E%>The following functions were %m,' .
                \ '%Z %m,' .
                \ '%-G%.%#',
            \ 'args': ['-q', '-c']
         \ }
endfunction
