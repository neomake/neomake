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
            \ '%E** %s %f:%l: %m,' .
            \ '%W%f:%l: warning: %m'
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
      \ 'args': ['compile', '--warnings-as-errors'],
      \ 'cwd': getcwd(),
      \ 'errorformat':
        \ '** %s %f:%l: %m,' .
        \ '%f:%l: warning: %m'
      \ }
endfunction

function! neomake#makers#ft#elixir#dogma()
    return {
      \ 'exe': 'mix',
      \ 'args': ['dogma', '%:p', '--format=flycheck'],
      \ 'errorformat': '%E%f:%l:%c: %.: %m'
      \ }
endfunction
