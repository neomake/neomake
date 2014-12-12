" vim: ts=4 sw=4 et

function! neomake#makers#coffee#EnabledMakers()
    return ['coffeelint']
endfunction

function! neomake#makers#coffee#coffeelint()
    return {
        \ 'args': ['--reporter=csv'],
        \ 'errorformat': '%f\,%l\,%\d%#\,%trror\,%m,' .
            \ '%f\,%l\,%trror\,%m,' .
            \ '%f\,%l\,%\d%#\,%tarn\,%m,' .
            \ '%f\,%l\,%tarn\,%m'
            \ }
endfunction
