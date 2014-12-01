" vim: ts=4 sw=4 et

function! neomake#makers#javascript#EnabledMakers()
    return ['jshint', 'eslint']
endfunction

function! neomake#makers#javascript#jshint()
    return {
        \ 'args': ['--verbose'],
            \ 'errorformat': '%A%f: line %l\, col %v\, %m \(%t%*\d\)',
            \ }
endfunction

function! neomake#makers#javascript#eslint()
    return {
        \ 'args': ['-f', 'compact'],
            \ 'errorformat': '%E%f: line %l\, col %c\, Error - %m,' .
            \ '%W%f: line %l\, col %c\, Warning - %m'
            \ }
endfunction
