" vim: ts=4 sw=4 et

function! neomake#makers#ft#elixir#EnabledMakers()
    return ['elixir']
endfunction

function! neomake#makers#ft#elixir#elixir()
    return {
        \ 'errorformat':
            \ '%E** %s %f:%l: %m,' .
            \ '%W%f:%l: warning: %m'
        \ }
endfunction

function! neomake#makers#ft#elixir#credo()
    return {
      \ 'exe': 'mix',
      \ 'args': ['credo', 'list', '%:p', '--format=oneline',
      \          '-i', 'readability'],
      \ 'errorformat': '[%t] %. %f:%l:%c %m'
      \ }
endfunction

function! neomake#makers#ft#elixir#dogma()
    return {
      \ 'exe': 'mix',
      \ 'args': ['dogma', '%:p', '--format=flycheck'],
      \ 'errorformat': '%E%f:%l:%c: %.: %m'
      \ }
endfunction
