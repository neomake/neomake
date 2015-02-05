" vim: ts=4 sw=4 et

function! neomake#makers#ft#zsh#EnabledMakers()
    return ['shellcheck']
endfunction

function! neomake#makers#ft#zsh#shellcheck()
    let maker = neomake#makers#ft#sh#shellcheck()
    return maker
endfunction
