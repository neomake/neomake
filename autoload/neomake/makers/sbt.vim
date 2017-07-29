" vim: ts=4 sw=4 et

function! neomake#makers#sbt#sbt() abort
    return {
        \ 'exe': 'sbt',
        \ 'args': ['compile'],
        \ 'errorformat':
            \ '%E[%trror]\ %f:%l:\ %m,' .
            \ '%-Z[error]\ %p^,' .
            \ '%-C%.%#,' .
            \ '%-G%.%#'
    \ }
endfunction
