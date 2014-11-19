
function! neomake#makers#go#EnabledMakers()
    return ['go', 'golint']
endfunction

function! neomake#makers#go#go()
    return {
        \ 'args': [
            \ 'build',
            \ '-o', neomake#utils#DevNull()
        \ ],
        \ 'errorformat':
            \ '%W%f:%l: warning: %m,' .
            \ '%E%f:%l:%c:%m,' .
            \ '%E%f:%l:%m,' .
            \ '%C%\s%\+%m,' .
            \ '%-G#%.%#'
        \ }
endfunction

function! neomake#makers#go#golint()
    return {
        \ 'errorformat':
            \ '%f:%l:%c: %m,' .
            \ '%-G%.%#'
        \ }
endfunction
