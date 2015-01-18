" vim: ts=4 sw=4 et

function! neomake#makers#zsh#EnabledMakers()
    return ['shellcheck']
endfunction

function! neomake#makers#zsh#shellcheck()
    let maker = neomake#makers#sh#shellcheck()
    return maker
endfunction
