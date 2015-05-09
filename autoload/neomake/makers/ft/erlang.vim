
function! neomake#makers#ft#erlang#EnabledMakers()
    return ['erlc']
endfunction

function! neomake#makers#ft#erlang#erlc()
    return {
        \ 'errorformat':
            \ '%f:%l: %m'
        \ }
endfunction
