" vim: ts=4 sw=4 et

function! neomake#makers#ft#angular#SupersetOf()
    return 'javascript'
endfunction

function! neomake#makers#ft#angular#EnabledMakers()
    return ['jshint', 'eslint', 'jscs']
endfunction

function! neomake#makers#ft#angular#jshint()
    return neomake#makers#ft#javascript#jshint()
endfunction

function! neomake#makers#ft#angular#eslint()
    return neomake#makers#ft#javascript#eslint()
endfunction

function! neomake#makers#ft#angular#jscs()
    return neomake#makers#ft#javascript#jscs()
endfunction

