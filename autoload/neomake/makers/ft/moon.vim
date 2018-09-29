function! neomake#makers#ft#moon#EnabledMakers() abort
    return ['moonc']
endfunction

function! neomake#makers#ft#moon#moonc() abort
    return {
        \ 'args': ['-l'],
        \ 'errorformat':
            \ '%-G,' .
            \ '%-G>%#,' .
            \ '%+P%f,'.
            \ 'line\ %l:\ %m'
    \ }
endfunction
