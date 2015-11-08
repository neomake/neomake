" vim: ts=4 sw=4 et

function! neomake#makers#ft#cs#EnabledMakers()
    if neomake#utils#Exists('mcs')
        return ['mcs']
    end
endfunction

function! neomake#makers#ft#cs#mcs()
    return {
        \ 'args': ['--parse', '--unsafe'],
        \ 'errorformat': '%f(%l\,%c): %trror %m',
        \ }
endfunction
