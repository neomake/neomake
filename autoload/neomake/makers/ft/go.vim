" vim: ts=4 sw=4 et

function! neomake#makers#ft#go#EnabledMakers()
    if exists('s:go_makers')
        return s:go_makers
    endif
    if neomake#utils#Exists('gometalinter')
        let s:go_makers = ['gometalinter']
    else
        let s:go_makers = ['go', 'golint']
    endif
    return s:go_makers
endfunction

function! neomake#makers#ft#go#go()
    return {
        \ 'args': [
            \ 'build',
            \ '-o', neomake#utils#DevNull()
        \ ],
        \ 'append_file': 0,
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

function! neomake#makers#ft#go#gometalinter()
    return {
        \ 'args': ['-t', '%:p:h'],
        \ 'append_file': 0,
        \ 'errorformat':
            \ '%E%f:%l:%c:error: %m,' .
            \ '%E%f:%l::error: %m,' .
            \ '%W%f:%l:%c:warning: %m,' .
            \ '%W%f:%l::warning: %m'
        \ }
endfunction
