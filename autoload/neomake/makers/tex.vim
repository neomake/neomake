" vim: ts=4 sw=4 et

function! neomake#makers#tex#EnabledMakers()
    if neomake#utils#Exists('chktex')
        return ['chktex']
    else
        return ['lacheck']
    end
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

function! neomake#makers#tex#lacheck()
    return {
        \ 'errorformat':
            \ '%-G** %f:,' .
            \ '%E"%f"\, line %l: %m'
        \ }
endfunction
