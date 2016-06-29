" vim: ts=4 sw=4 et

function! neomake#makers#ft#cuda#EnabledMakers()
    return ['nvcc']
endfunction

function! neomake#makers#ft#cuda#nvcc()
    return {
        \ 'exe': 'nvcc',
        \ 'errorformat':
            \ '%f\(%l\): %trror: %m,'.
            \ '%f\(%l\): %tarning: %m,'.
            \ '%f\(%l\): %m',
        \ }
endfunction
