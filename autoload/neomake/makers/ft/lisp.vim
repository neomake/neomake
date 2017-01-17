" vim: ts=4 sw=4 et

function! neomake#makers#ft#lisp#EnabledMakers() abort
    return ['clisp']
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
