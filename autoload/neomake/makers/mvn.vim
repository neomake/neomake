" vim: ts=4 sw=4 et

function! neomake#makers#mvn#mvn()
    return {
         \ 'exe': 'mvn',
         \ 'args': ['install'],
            \ 'errorformat': '[%tRROR]\ %f:[%l]\ %m,%-G%.%#'
         \ }
endfunction
