" vim: ts=4 sw=4 et

function! neomake#makers#ft#tsx#SupersetOf()
    return 'typescript'
endfunction

function! neomake#makers#ft#tsx#EnabledMakers()
    return ['tsc', 'tslint']
endfunction

function! neomake#makers#ft#tsx#tsc()
    return neomake#makers#ft#typescript#tsc()
endfunction

function! neomake#makers#ft#tsx#tslint()
    return neomake#makers#ft#typescript#tslint()
endfunction
