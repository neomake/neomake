" vim: ts=4 sw=4 et

function! neomake#makers#ft#java#EnabledMakers()
    return ['javac', 'checkstyle']
endfunction

function! neomake#makers#ft#java#javac()
    return {
        \ 'args': ['-Xlint'],
        \ 'buffer_output': 1,
        \ 'errorformat':
            \ '%E%f:%l: error: %m,'.
            \ '%W%f:%l: warning: %m,'.
            \ '%E%f:%l: %m,'.
            \ '%Z%p^,'.
            \ '%-G%.%#'
         \ }
endfunction

function! neomake#makers#ft#java#checkstyle()
    return {
        \ 'args': ['-c', '/usr/share/checkstyle/google_checks.xml'],
            \ 'errorformat':
            \ '[%t%*[^]]] %f:%l:%c: %m [%s]'
         \ }
endfunction
