
function! neomake#makers#javascript#EnabledMakers()
    return ['jshint']
endfunction

function! neomake#makers#javascript#jshint()
    return {
        \ 'args': ['--verbose'],
        \ 'errorformat': '%A%f: line %l\, col %v\, %m \(%t%*\d\)',
        \ }
endfunction
