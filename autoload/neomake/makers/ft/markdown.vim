function! neomake#makers#ft#markdown#EnabledMakers() abort
    let makers = executable('mdl') ? ['mdl'] : ['markdownlint']
    return makers + ['proselint']
endfunction

function! neomake#makers#ft#markdown#mdl() abort
    return {
                \ 'errorformat':
                \ '%f:%l: %m'
                \ }
endfunction

function! neomake#makers#ft#markdown#proselint() abort
    return neomake#makers#ft#text#proselint()
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
