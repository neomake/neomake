function! neomake#makers#ft#sql#EnabledMakers() abort
    return ['sqlint', 'sqlfluff']
endfunction

function! neomake#makers#ft#sql#sqlfluff() abort
    return {
        \ 'errorformat':
            \ '==\ [%f] FAIL,' .
            \ '%EL:\ %#%l\ |\ P:\ %#%c\ |\ %t%n\ |\ %m,' .
            \ '%C\ %#|\ %m'
        \ }
endfunction

function! neomake#makers#ft#sql#sqlint() abort
    return {
        \ 'errorformat':
            \ '%E%f:%l:%c:ERROR %m,' .
            \ '%W%f:%l:%c:WARNING %m,' .
            \ '%C %m'
        \ }
endfunction
" vim: ts=4 sw=4 et
