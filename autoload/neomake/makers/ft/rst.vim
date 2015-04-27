" vim: ts=4 sw=4 et

function! neomake#makers#ft#rst#EnabledMakers()
    return ['rstlint', 'rstcheck']
endfunction

function! neomake#makers#ft#rst#rstlint()
    return {
        \ 'exe': 'rst-lint',
        \ 'errorformat':
            \ '%EERROR %f:%l %m,'.
            \ '%IINFO %f:%l %m',
        \ }
endfunction

function! neomake#makers#ft#rst#rstcheck()
    return {
        \ 'errorformat':
            \ '%I%f:%l: (INFO/1) %m,'.
            \ '%W%f:%l: (WARNING/2) %m,'.
            \ '%E%f:%l: (ERROR/3) %m,'.
            \ '%E%f:%l: (SEVERE/4) %m',
        \ }
endfunction
