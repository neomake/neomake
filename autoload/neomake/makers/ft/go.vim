" vim: ts=4 sw=4 et

function! neomake#makers#ft#go#EnabledMakers()
    return ['go', 'golint', 'govet']
endfunction

" The mapexprs in these are needed because cwd will make the command print out
" the wrong path (it will just be ./%:h in the output), so the mapexpr turns
" that back into the relative path

function! neomake#makers#ft#go#go()
    return {
        \ 'args': [
            \ 'test', '-c',
            \ '-o', neomake#utils#DevNull(),
        \ ],
        \ 'append_file': 0,
        \ 'cwd': '%:h',
        \ 'mapexpr': 'expand("%:h") . "/" . v:val',
        \ 'errorformat':
            \ '%W%f:%l: warning: %m,' .
            \ '%E%f:%l:%c:%m,' .
            \ '%E%f:%l:%m,' .
            \ '%C%\s%\+%m,' .
            \ '%-G#%.%#'
        \ }
endfunction

function! neomake#makers#ft#go#golint()
    return {
        \ 'errorformat':
            \ '%f:%l:%c: %m,' .
            \ '%-G%.%#'
        \ }
endfunction

function! neomake#makers#ft#go#govet()
    return {
        \ 'exe': 'go',
        \ 'args': ['vet'],
        \ 'append_file': 0,
        \ 'cwd': '%:h',
        \ 'mapexpr': 'expand("%:h") . "/" . v:val',
        \ 'errorformat':
            \ '%Evet: %.%\+: %f:%l:%c: %m,' .
            \ '%W%f:%l: %m,' .
            \ '%-G%.%#'
        \ }
endfunction
