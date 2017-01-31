" vim: ts=4 sw=4 et

function! neomake#makers#ft#jsx#SupersetOf()
    return 'javascript'
endfunction

function! neomake#makers#ft#jsx#EnabledMakers()
    return ['jshint', 'eslint']
endfunction

function! neomake#makers#ft#jsx#jshint()
    let maker = neomake#makers#ft#javascript#jshint()
    let maker.exe = 'jsxhint'
    return maker
endfunction

function! neomake#makers#ft#jsx#jsxhint()
    return neomake#makers#ft#jsx#jshint()
endfunction

function! neomake#makers#ft#jsx#eslint()
    return neomake#makers#ft#javascript#eslint()
endfunction

function! neomake#makers#ft#jsx#eslint_d()
    return neomake#makers#ft#javascript#eslint_d()
endfunction

function! neomake#makers#ft#jsx#rjsx()
    return neomake#makers#ft#javascript#rjsx()
endfunction
