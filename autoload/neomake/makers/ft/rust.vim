" vim: ts=4 sw=4 et

function! neomake#makers#ft#rust#EnabledMakers()
    return ['rustc']
endfunction

function! neomake#makers#ft#rust#rustc()
    return {
        \ 'args': ['-Z', 'parse-only'],
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
