" vim: ts=4 sw=4 et

function! neomake#makers#ft#elixir#EnabledMakers()
    return ['elixir']
endfunction

function! neomake#makers#ft#elixir#elixir()
    return {
        \ 'errorformat':
            \ '** %s %f:%l: %m,' .
            \ '%f:%l: warning: %m'
        \ }
endfunction
