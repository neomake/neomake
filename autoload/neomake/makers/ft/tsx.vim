" vim: ts=4 sw=4 et

function! neomake#makers#ft#tsx#SupersetOf()
    return 'typescript'
endfunction

function! neomake#makers#ft#tsx#EnabledMakers()
    return ['tsc', 'tslint']
endfunction

function! neomake#makers#ft#tsx#tsc()
    let config = neomake#makers#ft#typescript#tsc()
    let config.args = config.args + ['--jsx', 'preserve']
    return config
endfunction

function! neomake#makers#ft#tsx#tslint()
    return neomake#makers#ft#typescript#tslint()
endfunction
