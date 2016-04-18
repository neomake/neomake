" vim: ts=4 sw=4 et

function! neomake#makers#ft#elixir#EnabledMakers()
    return ['mix']
endfunction

function! neomake#makers#ft#elixir#elixir()
    return {
        \ 'errorformat':
            \ '** %s %f:%l: %m,' .
            \ '%f:%l: warning: %m'
        \ }
endfunction

function! neomake#makers#ft#elixir#credo()
    return {
      \ 'exe': 'mix',
      \ 'args': ['credo', 'list', '%:p', '--format=oneline', '-i', 'readability'],
      \ 'errorformat': '[%t] %. %f:%l:%c %m'
      \ }
endfunction

function neomake#makers#ft#elixir#mix()
    return {
      \ 'exe' : 'mix',
      \ 'args': ['compile.elixir', '--warnings-as-errors'],
      \ 'errorformat':
        \ '** %s %f:%l: %m,' .
        \ '%f:%l: warning: %m'
      \ }
endfunction
