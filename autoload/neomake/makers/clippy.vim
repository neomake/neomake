" vim: ts=4 sw=4 et

function! neomake#makers#clippy#clippy()
    return {
        \ 'exe': 'cargo',
        \ 'args': ['clippy'],
        \ 'errorformat':
            \   '%-Z%f:%l,' .
            \   '%+C %s,' .
            \   '%A%f:%l:%c: %*\d:%*\d\ %t%*[^:]: %m,',
        \ }
endfunction
