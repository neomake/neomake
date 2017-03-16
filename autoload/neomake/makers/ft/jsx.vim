" vim: ts=4 sw=4 et

function! neomake#makers#ft#jsx#SupersetOf() abort
    return 'javascript'
endfunction

function! neomake#makers#ft#jsx#EnabledMakers() abort
    return ['jshint', 'eslint']
endfunction

function! neomake#makers#ft#jsx#jshint() abort
    let maker = neomake#makers#ft#javascript#jshint()
    let maker.exe = 'jsxhint'
    return maker
endfunction

function! neomake#makers#ft#jsx#jsxhint() abort
    return neomake#makers#ft#jsx#jshint()
endfunction

function! neomake#makers#ft#jsx#eslint() abort
    return neomake#makers#ft#javascript#eslint()
endfunction

function! neomake#makers#ft#jsx#eslint_d() abort
    return neomake#makers#ft#javascript#eslint_d()
endfunction

function! neomake#makers#ft#jsx#standard() abort
    return neomake#makers#ft#javascript#standard()
endfunction

function! neomake#makers#ft#jsx#semistandard() abort
    return neomake#makers#ft#javascript#semistandard()
endfunction

function! neomake#makers#ft#jsx#rjsx() abort
    return neomake#makers#ft#javascript#rjsx()
endfunction

function! neomake#makers#ft#jsx#flow() abort
    return neomake#makers#ft#javascript#flow()
endfunction
