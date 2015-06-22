" vim: ts=4 sw=4 et

function! neomake#makers#ft#less#EnabledMakers()
    return ['lessc']
endfunction

function! neomake#makers#ft#less#lessc()
    return {
        \ 'args': ['--lint', '--no-color'],
        \ 'errorformat':
            \ '%m in %f on line %l\, column %c:,' .
            \ '%m in %f:%l:%c,' .
            \ '%-G%.%#'
    \ }
endfunction
