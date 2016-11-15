" vim: ts=4 sw=4 et

function! neomake#makers#proselint#proselint() abort
    return {
        \ 'errorformat': '%f:%l:%c: %m'
        \ }
endfunction
