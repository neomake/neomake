" vim: ts=4 sw=4 et

function! neomake#makers#ft#go#EnabledMakers()
    return ['go', 'golint', 'govet']
endfunction

function! neomake#makers#ft#go#go()

    " Uses:
    " https://github.com/scrooloose/syntastic/blob/master/syntax_checkers/go/go.vim#L54
    " as an example.
    if match(expand('%', 1), '\m_test\.go$') == -1
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
    else
        return {
            \ 'cwd': expand('%:p:h', 1),
            \ 'args': [
                \ 'test',
                \ '-c',
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
    endif
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
        \ 'errorformat':
            \ '%Evet: %.%\+: %f:%l:%c: %m,' .
            \ '%W%f:%l: %m,' .
            \ '%-G%.%#'
        \ }
endfunction
