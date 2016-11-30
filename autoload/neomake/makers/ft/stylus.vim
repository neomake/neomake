" vim: ts=4 sw=4 et

function! neomake#makers#ft#stylus#EnabledMakers()
    return ['stylint']
endfunction

function! neomake#makers#ft#stylus#stylint()
    return {
        \ 'errorformat':
            \ '%WWarning: %m,' .
            \ '%EError: %m,' .
            \ '%-Csee file: %f for the original selector,' .
            \ '%CFile: %f,' .
            \ '%ZLine: %l:%.%#'
    \ }
endfunction
