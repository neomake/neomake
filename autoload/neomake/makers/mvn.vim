" vim: ts=4 sw=4 et

function! neomake#makers#mvn#mvn()
    return {
         \ 'exe': 'mvn',
         \ 'args': ['install'],
         \ 'errorformat':
           \ '%E[%tRROR]\ %f:[%l]\ %m,' .
           \ '%E[%tRROR]\ %f:[%l\,%v]\ %m,' .
           \ '%C\ %s:\ %m,' .
           \ '%C[ERROR]\ %s:\ %m,' .
           \ '%-G%.%#'
         \ }
endfunction
