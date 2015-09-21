" vim: ts=4 sw=4 et

function! neomake#makers#ft#typescript#EnabledMakers()
    return ['tsc', 'tslint']
endfunction

function! neomake#makers#ft#typescript#tsc()
    return {
        \ 'args': [
            \ '-m', 'commonjs', '--noEmit'
        \ ],
        \ 'errorformat':
            \ '%E%f %#(%l\,%c): error %m,' .
            \ '%E%f %#(%l\,%c): %m,' .
            \ '%Eerror %m,' .
            \ '%C%\s%\+%m'
        \ }
endfunction

function! neomake#makers#ft#typescript#tslint()
    return {
        \ 'args': [
            \ '%:p', '--format verbose'
        \ ],
        \ 'errorformat': '%f[%l\, %c]: %m'
        \ }
endfunction
