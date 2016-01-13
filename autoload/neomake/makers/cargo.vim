" vim: ts=4 sw=4 et

function! neomake#makers#cargo#cargo()
    return {
        \ 'args': ['build'],
        \ 'errorformat':
            \   '%-Z%f:%l,' .
            \   '%+C %s,' .
            \   '%A%f:%l:%c: %*\d:%*\d\ %t%*[^:]: %m,',
        \ }
endfunction
