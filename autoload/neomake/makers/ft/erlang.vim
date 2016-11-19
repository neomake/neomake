" vim: ts=4 sw=4 et

function! neomake#makers#ft#erlang#EnabledMakers()
    return ['erlc']
endfunction

function! neomake#makers#ft#erlang#erlc()
    return {
                \ 'errorformat':
                \ '%f:%l: %m'
                \ }
endfunction
