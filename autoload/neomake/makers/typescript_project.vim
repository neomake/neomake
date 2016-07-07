" vim: ts=4 sw=4 et

function! neomake#makers#typescript_project#typescript_project()
    return {
        \ 'exe': 'tsc',
        \ 'args': ['--noEmit'],
        \ 'errorformat':
            \ '%E%f %#(%l\,%c): error %m,' .
            \ '%E%f %#(%l\,%c): %m,' .
            \ '%Eerror %m,' .
            \ '%C%\s%\+%m'
        \ }
endfunction
