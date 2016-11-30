" vim: ts=4 sw=4 et

function! neomake#makers#ft#jasmine#SupersetOf()
    return 'javascript'
endfunction

function! neomake#makers#ft#jasmine#EnabledMakers()
    return ['jshint', 'eslint', 'jscs']
endfunction

function! neomake#makers#ft#jasmine#jshint()
    return neomake#makers#ft#javascript#jshint()
endfunction

function! neomake#makers#ft#jasmine#eslint()
    return neomake#makers#ft#javascript#eslint()
endfunction

function! neomake#makers#ft#jasmine#eslint_d()
    return neomake#makers#ft#javascript#eslint_d()
endfunction

function! neomake#makers#ft#jasmine#jscs()
    return neomake#makers#ft#javascript#jscs()
endfunction
