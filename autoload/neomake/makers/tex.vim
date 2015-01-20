" vim: ts=4 sw=4 et

function! neomake#makers#tex#EnabledMakers()
    return ['chktex']
endfunction

function! neomake#makers#tex#chktex()
    return {
        \ 'errorformat':
            \ '%EError %n in %f line %l: %m,' .
            \ '%WWarning %n in %f line %l: %m,' .
            \ '%WMessage %n in %f line %l: %m,' .
            \ '%Z%p^,' .
            \ '%-G%.%#'
        \ }
endfunction
