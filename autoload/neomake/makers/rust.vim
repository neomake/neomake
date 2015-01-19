" vim: ts=4 sw=4 et

function! neomake#makers#rust#EnabledMakers()
    return ['rustc']
endfunction

function! neomake#makers#rust#rustc()
    return {
        \ 'errorformat':
            \ '%-G%f:%s:,' .
            \ '%f:%l:%c: %trror: %m,' .
            \ '%f:%l:%c: %tarning: %m,' .
            \ '%f:%l:%c: %m,'.
            \ '%f:%l: %trror: %m,'.
            \ '%f:%l: %tarning: %m,'.
            \ '%f:%l: %m',
        \ }
endfunction
