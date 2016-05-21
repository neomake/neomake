" vim: ts=4 sw=4 et

function! neomake#makers#ft#fish#EnabledMakers()
    return ['fish']
endfunction

function! neomake#makers#ft#fish#fish()
    return {
        \ 'args': ['-n'],
        \ 'errorformat':
            \ '%C%f (line %l): %s,'.
            \ '%-Gfish: %.%#,'.
            \ '%Z%p^,'.
            \ '%E%m'
        \}
endfunction
