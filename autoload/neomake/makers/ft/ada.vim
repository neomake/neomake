function! neomake#makers#ft#ada#EnabledMakers()
    return ['gcc']
endfunction

function! neomake#makers#ft#ada#gcc()
    return {
        \ 'args': ['-c', '-x', 'ada', '-gnats'],
        \ 'errorformat':
            \ '%-G%f:%s:,' .
            \ '%f:%l:%c: %m,' .
            \ '%f:%l: %m'
        \ }
endfunction
