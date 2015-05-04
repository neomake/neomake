" vim: ts=4 sw=4 et
function! neomake#makers#ft#scala#EnabledMakers()
    return ['scalac']
endfunction

function! neomake#makers#ft#scala#scalac()
    return {
        \ 'args': [
            \ '-Ystop-after:parser'
        \ ],
        \ 'errorformat':
            \ '%E%f:%l: %trror: %m,' .
            \ '%Z%p^,' .
            \ '%-G%.%#'
        \ }
endfunction
