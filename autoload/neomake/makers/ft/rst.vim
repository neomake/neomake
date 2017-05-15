" vim: ts=4 sw=4 et

function! neomake#makers#ft#rst#SupersetOf() abort
    return 'text'
endfunction

function! neomake#makers#ft#rst#EnabledMakers() abort
    return ['rstlint', 'rstcheck']
endfunction

function! neomake#makers#ft#rst#rstlint() abort
    return {
        \ 'exe': 'rst-lint',
        \ 'errorformat':
            \ '%EERROR %f:%l %m,'.
            \ '%WWARNING %f:%l %m,'.
            \ '%IINFO %f:%l %m',
        \ }
endfunction

function! neomake#makers#ft#rst#rstcheck() abort
    return {
        \ 'errorformat':
            \ '%I%f:%l: (INFO/1) %m,'.
            \ '%W%f:%l: (WARNING/2) %m,'.
            \ '%E%f:%l: (ERROR/3) %m,'.
            \ '%E%f:%l: (SEVERE/4) %m',
        \ }
endfunction
