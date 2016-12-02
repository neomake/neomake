
function! neomake#makers#ft#erlang#EnabledMakers()
    return ['erlc']
endfunction

function! neomake#makers#ft#erlang#erlc()
    return {
        \ 'errorformat':
            \ '%W%f:%l: Warning: %m,' .
            \ '%E%f:%l: %m'
        \ }
endfunction
