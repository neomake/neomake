function! neomake#makers#ft#ada#EnabledMakers() abort
    return ['gcc']
endfunction

function! neomake#makers#ft#ada#gcc() abort
    return {
        \ 'args': ['-c', '-x', 'ada', '-gnats'],
        \ 'errorformat':
            \ '%-G%f:%s:,' .
            \ '%f:%l:%c: %m,' .
            \ '%f:%l: %m'
        \ }
endfunction
