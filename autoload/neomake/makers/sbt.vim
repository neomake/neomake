" vim: ts=4 sw=4 et

function! neomake#makers#sbt#sbt() abort
    return {
        \ 'exe': 'sbt',
        \ 'args': ['compile'],
        \ 'errorformat': '[%trror] %f:%l: %m'
    \ }
endfunction
