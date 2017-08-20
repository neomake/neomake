function! neomake#makers#ft#markdown#SupersetOf() abort
    return 'text'
endfunction
function! neomake#makers#ft#markdown#EnabledMakers() abort
    let makers = executable('mdl') ? ['mdl'] : ['markdownlint']
    return makers + ['proselint', 'writegood'] + neomake#makers#ft#text#EnabledMakers()
endfunction

function! neomake#makers#ft#markdown#mdl() abort
    return {
        \ 'errorformat':
        \   '%W%f:%l: MD%n %m,' .
        \   '%W%f:%l: %m'
        \ }
endfunction

function! neomake#makers#ft#markdown#markdownlint() abort
    return {
                \ 'errorformat':
                \ '%f: %l: %m'
                \ }
endfunction

function! neomake#makers#ft#markdown#alex() abort
    return {
                \ 'errorformat':
                \ '%P%f,' .
                \ '%-Q,' .
                \ '%*[ ]%l:%c-%*\d:%n%*[ ]%tarning%*[ ]%m,' .
                \ '%-G%.%#'
                \ }
endfunction
