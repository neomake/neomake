function! neomake#makers#ft#vimwiki#SupersetOf() abort
    return 'markdown'
endfunction

function! neomake#makers#ft#vimwiki#EnabledMakers() abort
    return neomake#makers#ft#markdown#EnabledMakers()
endfunction

" vim: ts=4 sw=4 et
