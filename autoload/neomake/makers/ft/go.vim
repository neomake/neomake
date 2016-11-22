" vim: ts=4 sw=4 et

function! neomake#makers#ft#go#EnabledMakers() abort
    return ['go', 'golint', 'govet', 'gometalinter']
endfunction

" The mapexprs in these are needed because cwd will make the command print out
" the wrong path (it will just be ./%:h in the output), so the mapexpr turns
" that back into the relative path

function! neomake#makers#ft#go#go() abort
    return {
        \ 'args': [
            \ 'test', '-c',
            \ '-o', neomake#utils#DevNull(),
        \ ],
        \ 'append_file': 0,
        \ 'cwd': '%:h',
        \ 'mapexpr': 'neomake_bufdir . "/" . v:val',
        \ 'errorformat':
            \ '%W%f:%l: warning: %m,' .
            \ '%E%f:%l:%c:%m,' .
            \ '%E%f:%l:%m,' .
            \ '%C%\s%\+%m,' .
            \ '%-G#%.%#'
        \ }
endfunction

function! neomake#makers#ft#go#golint() abort
    " golint's issues are informational, as they're stylistic (not bugs)
    return {
        \ 'errorformat':
            \ '%I%f:%l:%c: %m,' .
            \ '%-G%.%#'
        \ }
endfunction

function! neomake#makers#ft#go#govet() abort
    return {
        \ 'exe': 'go',
        \ 'args': ['vet'],
        \ 'append_file': 0,
        \ 'cwd': '%:h',
        \ 'mapexpr': 'neomake_bufdir . "/" . v:val',
        \ 'errorformat':
            \ '%Evet: %.%\+: %f:%l:%c: %m,' .
            \ '%W%f:%l: %m,' .
            \ '%-G%.%#'
        \ }
endfunction

function! neomake#makers#ft#go#gometalinter() abort
    " Only run a subset of gometalinter for speed, users can override with:
    " let g:let g:neomake_go_gometalinter_args = ['--disable-all', '--enable=X', ...]
    "
    " All linters are only warnings, the go compiler will report errors
    return {
        \ 'args': ['--disable-all', '--enable=errcheck', '--enable=gosimple', '--enable=staticcheck', '--enable=unused'],
        \ 'append_file': 0,
        \ 'cwd': '%:h',
        \ 'mapexpr': 'neomake_bufdir . "/" . v:val',
        \ 'errorformat': '%W%f:%l:%c:%m',
        \ }
endfunction
