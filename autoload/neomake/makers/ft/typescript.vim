" vim: ts=4 sw=4 et

function! neomake#makers#ft#typescript#EnabledMakers() abort
    return ['tsc', 'tslint']
endfunction

function! neomake#makers#ft#typescript#tsc() abort
    " tsc should not be passed a single file.  Changing to the file's dir will
    " make it look upwards for a tsconfig.json file.
    return {
        \ 'args': ['--noEmit'],
        \ 'append_file': 0,
        \ 'cwd': '%:p:h',
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
