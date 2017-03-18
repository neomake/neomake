function! neomake#makers#ft#jsx#SupersetOf() abort
    return 'javascript'
endfunction

function! neomake#makers#ft#jsx#EnabledMakers() abort
    return ['jshint', 'eslint']
endfunction

function! neomake#makers#ft#jsx#jsxhint() abort
    return neomake#makers#ft#javascript#jshint()
endfunction

" vim: ts=4 sw=4 et
