" vim: ts=4 sw=4 et

function! neomake#makers#ft#rst#EnabledMakers()
    return ['rstlint', 'rstcheck', 'sphinx']
endfunction

function! neomake#makers#ft#rst#rstlint()
    return {
        \ 'exe': 'rst-lint',
        \ 'errorformat':
            \ '%EERROR %f:%l %m,'.
            \ '%WWARNING %f:%l %m,'.
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

" TODO: determine proper path of current .rst file upwards in sear for conf.py file, use that instead of "docs"
" TODO: ask noomake for a temporary folder instead of /tmp/neomake-sphinx
" TODO: split arguments and make them configurable
" TODO: support more errors
" TODO: add test-suite

function! neomake#makers#ft#rst#sphinx()
    return {
        \ 'exe': 'sphinx-build',
        \ 'args': '-n -E -q -N -b pseudoxml docs /tmp/neomake-sphinx',
        \ 'errorformat':
            \ '%f:%l: %tRROR: %m,' .
            \ '%f:%l: %tARNING: %m,' ,
        \ }
endfunction
