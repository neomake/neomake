" vim: ts=4 sw=4 et
function! neomake#makers#ft#moon#EnabledMakers()
    return ['moonc']
endfunction

function! neomake#makers#ft#moon#moonc()
    return {
                \ 'args': ['-l', '%:p'],
                \ 'errorformat':
                \ '%-G,' .
                \ '%-G>%#,' .
                \ '%+P%f,'.
                \ 'line\ %l:\ %m'
                \ }
endfunction
