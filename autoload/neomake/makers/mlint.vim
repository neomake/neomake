" vim: ts=4 sw=4 et

function! neomake#maker#mlint#mlint() abort 
    return {
        \ 'exe': 'mlint',
        \ 'args': ['-id'],
        \ 'mapexpr': "neomake_bufname.':'.v:val",
        \ 'errorformat':
        \ '%f:L %l (C %c): %m,' .
        \ '%f:L %l (C %c-%*[0-9]): %m,',
        \ }
endfunction
