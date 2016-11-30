" vim: ts=4 sw=4 et

function! neomake#makers#ft#node#SupersetOf()
    return 'javascript'
endfunction

function! neomake#makers#ft#node#EnabledMakers()
    return ['jshint', 'eslint', 'jscs']
endfunction

function! neomake#makers#ft#node#jshint()
    return neomake#makers#ft#javascript#jshint()
endfunction

function! neomake#makers#ft#node#eslint()
    return neomake#makers#ft#javascript#eslint()
endfunction

function! neomake#makers#ft#node#eslint_d()
    return neomake#makers#ft#javascript#eslint_d()
endfunction

function! neomake#makers#ft#node#jscs()
    return neomake#makers#ft#javascript#jscs()
endfunction
