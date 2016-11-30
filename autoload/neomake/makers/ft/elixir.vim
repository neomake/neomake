" vim: ts=4 sw=4 et

function! neomake#makers#ft#elixir#EnabledMakers() abort
    return ['mix']
endfunction

function! neomake#makers#ft#elixir#elixir() abort
    return {
        \ 'errorformat':
            \ '%E** %s %f:%l: %m,' .
            \ '%W%f:%l: warning: %m'
        \ }
endfunction

function! neomake#makers#ft#elixir#credo() abort
    return {
      \ 'exe': 'mix',
      \ 'args': ['credo', 'list', '%:p', '--format=oneline', '-i', 'readability'],
      \ 'errorformat': '[%t] %. %f:%l:%c %m'
      \ }
endfunction

function! neomake#makers#ft#elixir#mix() abort
    return {
      \ 'exe' : 'mix',
      \ 'args': ['compile', '--warnings-as-errors'],
      \ 'cwd': getcwd(),
      \ 'errorformat':
        \ '** %s %f:%l: %m,' .
        \ '%f:%l: warning: %m'
      \ }
endfunction

function! neomake#makers#ft#elixir#dogma() abort
    return {
      \ 'exe': 'mix',
      \ 'args': ['dogma', '%:p', '--format=flycheck'],
      \ 'errorformat': '%E%f:%l:%c: %.: %m'
      \ }
endfunction
