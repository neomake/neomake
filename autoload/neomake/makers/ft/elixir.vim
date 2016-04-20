" vim: ts=4 sw=4 et

function s:find_mix_file(path)
    " TODO: Recurse upwards to fix the mix file.
endfunction

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
      \ 'args': ['credo', 'list', '%:p', '--one-line', '-i', 'readability'],
      \ 'errorformat': '[%t] %. %f:%l:%c %m'
      \ }
endfunction

function neomake#makers#ft#elixir#mix()
    return {
      \ 'exe' : 'mix',
      \ 'args': ['compile', '--warnings-as-errors'],
      \ 'cwd': getcwd(),
      \ 'errorformat':
        \ '** %s %f:%l: %m,' .
        \ '%f:%l: warning: %m'
      \ }
endfunction
