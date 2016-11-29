" vim: ts=4 sw=4 et

function! neomake#makers#ft#vue#EnabledMakers() abort
    return ['eslint']
endfunction

function! neomake#makers#ft#vue#eslint() abort
    return {
        \ 'args': ['--format', 'compact', '--plugin', 'html'],
        \ 'errorformat': '%E%f: line %l\, col %c\, Error - %m,' .
        \ '%W%f: line %l\, col %c\, Warning - %m'
        \ }
endfunction

function! neomake#makers#ft#vue#eslint_d() abort
    return neomake#makers#ft#vue#eslint()
endfunction
