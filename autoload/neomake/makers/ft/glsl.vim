" vim: ts=4 sw=4 et

function! neomake#makers#ft#glsl#EnabledMakers() abort
    return executable('glslc') ? ['glslc'] : []
endfunction

function! neomake#makers#ft#glsl#glslc() abort
    return {
        \ 'args': ['-c', '-o', g:neomake#compat#dev_null],
        \ 'errorformat':
            \ '%f:%l: %trror: %m,' .
            \ '%f: %trror: %m,' .
            \ '%f:%l: %tarning: %m,' .
            \ '%f: %tarning: %m,' .
            \ '%-G%s',
        \ }
endfunction
