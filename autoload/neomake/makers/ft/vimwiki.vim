" vim: ts=4 sw=4 et

function! neomake#makers#ft#vimwiki#SupersetOf() abort
    return 'text'
endfunction

function! neomake#makers#ft#vimwiki#EnabledMakers() abort
    let makers = ['proselint', 'writegood'] + neomake#makers#ft#text#EnabledMakers()
    if expand('%:e') ==? 'md'
        let makers = executable('mdl') ? ['mdl'] : ['markdownlint'] + makers
    endif
    return makers
endfunction

function! neomake#makers#ft#vimwiki#mdl() abort
    return neomake#makers#ft#markdown#mdl()
endfunction

function! neomake#makers#ft#vimwiki#markdownlint() abort
    return neomake#makers#ft#markdown#markdownlint()
endfunction

