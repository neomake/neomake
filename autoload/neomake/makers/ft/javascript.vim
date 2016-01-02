" vim: ts=4 sw=4 et

function! neomake#makers#ft#javascript#EnabledMakers()
    return ['jshint', 'jscs', 'eslint']
endfunction

function! neomake#makers#ft#javascript#jshint()
    return {
        \ 'args': ['--verbose'],
        \ 'errorformat': '%A%f: line %l\, col %v\, %m \(%t%*\d\)',
        \ }
endfunction

function! neomake#makers#ft#javascript#jscs()
    return {
        \ 'args': ['--no-color', '--reporter', 'inline'],
        \ 'errorformat': '%f: line %l\, col %c\, %m',
        \ }
endfunction

function! neomake#makers#ft#javascript#eslint()
    return {
        \ 'args': ['-f', 'compact'],
        \ 'errorformat': '%E%f: line %l\, col %c\, Error - %m,' .
        \ '%W%f: line %l\, col %c\, Warning - %m'
        \ }
endfunction

function! neomake#makers#ft#javascript#eslint_d()
    return {
        \ 'args': ['-f', 'compact'],
        \ 'errorformat': '%E%f: line %l\, col %c\, Error - %m,' .
        \ '%W%f: line %l\, col %c\, Warning - %m'
        \ }
endfunction

function! neomake#makers#ft#javascript#standard()
    return {
        \ 'errorformat': '  %f:%l:%c: %m'
        \ }
endfunction

function! neomake#makers#ft#javascript#flow()
    " Multi-line Vim
    " \ 'errorformat': '%CFile %m%.%#,%AFile "%f"\, line %l\, characters %c-%.%#,%+G%m,%Z%m,%-G%.%#'

    " Single-line Vim - Long
    " 'errorformat': '%CFile %m%.%#,%AFile "%f"\, line %l\, characters %c-%.%#,%C%m,%Z%m,%-G%.%#'

    " Single-line Vim - Short
    " \ 'errorformat': '%CFile %.%#,%AFile "%f"\, line %l\, characters %c-%.%#,%C%m,%Z%m,%-G%.%#'

    return {
        \ 'args': ['--from=vim'],
        \ 'errorformat': '%CFile %.%#,%AFile "%f"\, line %l\, characters %c-%.%#,%C%m,%Z%m'
        \ }
endfunction
