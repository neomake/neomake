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

function! neomake#makers#ft#elixir#credo()
    return {
      \ 'exe': 'mix',
      \ 'args': ['credo', 'list', '%:p', '--one-line', '-i', 'readability'],
      \ 'errorformat': '[%t] %. %f:%l:%c %m'
      \ }
endfunction

function neomake#makers#ft#elixir#mix()
    return {
      \ 'exe' : 'mix',
      \ 'args': ['compile.elixir', '%:p:h'],
      \ 'errorformat': '** (%t) %f:%l:%c %m'
      \ }
endfunction

" ** (CompileError) test/models/hashtag_test.exs:2: module Twchat.ModelCase is not loaded and could not be found
" 'errorformat': ' (%t) %f:%l:%c %m'
" [F] → web/views/error_helpers.ex:12 There should be no matches in `if` conditions.
" 'errorformat': '[%t] %. %f:%l:%c %m'
