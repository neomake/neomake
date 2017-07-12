" vim: ts=4 sw=4 et

function! neomake#makers#ft#go#EnabledMakers() abort
    let makers = ['go']
    if executable('gometalinter')
        call add(makers, 'gometalinter')
    else
        call extend(makers, ['golint', 'govet'])
    endif
    return makers
endfunction

function! neomake#makers#ft#go#go() abort
    return {
        \ 'args': [
            \ 'test', '-c',
            \ '-o', neomake#utils#DevNull(),
        \ ],
        \ 'append_file': 0,
        \ 'cwd': '%:h',
        \ 'serialize': 1,
        \ 'serialize_abort_on_error': 1,
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
        \ 'errorformat':
            \ '%Evet: %.%\+: %f:%l:%c: %m,' .
            \ '%W%f:%l: %m,' .
            \ '%-G%.%#'
        \ }
endfunction

function! neomake#makers#ft#go#gometalinter() abort
    " Only run a subset of gometalinter for speed, users can override with:
    " let g:neomake_go_gometalinter_args = ['--disable-all', '--enable=X', ...]
    "
    " All linters are only warnings, the go compiler will report errors
    return {
        \ 'args': ['--disable-all', '--enable=errcheck', '--enable=gosimple', '--enable=staticcheck', '--enable=unused'],
        \ 'append_file': 0,
        \ 'cwd': '%:h',
        \ 'errorformat': '%f:%l:%c:%t%*[^:]: %m',
        \ }
endfunction
