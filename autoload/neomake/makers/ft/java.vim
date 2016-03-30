function! neomake#makers#ft#java#EnabledMakers()
        return ['javac']
endfunction

function! neomake#makers#ft#java#javac()
    return {
        \ 'args': ['-Xlint'],
        \ 'buffer_output': 1,
        \ 'errorformat':
            \ '%E%f:%l: error: %m,'.
            \ '%W%f:%l: warning: %m,'.
            \ '%E%f:%l: %m,'.
            \ '%Z%p^,'.
            \ '%-G%.%#'
         \ }
endfunction
