" vim: ts=4 sw=4 et

function! neomake#makers#ft#vlang#EnabledMakers() abort
    return ['v', 'vvet']
endfunction

function! neomake#makers#ft#vlang#v() abort
    return {
        \ 'exe': 'v',
        \ 'args': ['-check'],
        \ 'errorformat': '%f:%l:%c: %trror: %m.',
        \ }
endfunction

function! neomake#makers#ft#vlang#vvet() abort
    return {
        \ 'exe': 'v',
        \ 'args': ['vet'],
        \ 'errorformat': '%f:%l: %trror: %m.',
        \ }
endfunction
