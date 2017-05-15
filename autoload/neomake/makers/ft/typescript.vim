" vim: ts=4 sw=4 et

function! neomake#makers#ft#typescript#EnabledMakers() abort
    return ['tsc', 'tslint']
endfunction

function! neomake#makers#ft#typescript#tsc() abort
    " tsc should not be passed a single file.
    return {
        \ 'args': ['--project', neomake#utils#FindGlobFile('tsconfig.json'), '--noEmit', '--watch', 'false'],
        \ 'append_file': 0,
        \ 'errorformat':
            \ '%E%f %#(%l\,%c): error %m,' .
            \ '%E%f %#(%l\,%c): %m,' .
            \ '%Eerror %m,' .
            \ '%C%\s%\+%m'
        \ }
endfunction

function! neomake#makers#ft#typescript#tslint() abort
    return {
        \ 'args': [
            \ '%:p', '--format verbose'
        \ ],
        \ 'errorformat': '%E%f[%l\, %c]: %m'
        \ }
endfunction
