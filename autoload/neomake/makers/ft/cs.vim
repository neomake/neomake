" vim: ts=4 sw=4 et

function! neomake#makers#ft#cs#EnabledMakers()
    return ['mcs']
endfunction

function! neomake#makers#ft#cs#mcs()
    return {
        \ 'args': ['--parse', '--unsafe'],
        \ 'errorformat': '%f(%l\,%c): %trror %m',
        \ }
endfunction
