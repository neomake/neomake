function! neomake#makers#ft#crystal#EnabledMakers() abort
    return ['crystal']
endfunction

function! neomake#makers#ft#crystal#crystal() abort
    " from vim-crystal
    return {
        \ 'args': ['run', '--no-color', '--no-codegen'],
        \ 'errorformat':
                \ '%ESyntax error in line %l: %m,'.
                \ '%ESyntax error in %f:%l: %m,'.
                \ '%EError in %f:%l: %m,'.
                \ '%C%p^,'.
                \ '%-C%.%#'
        \ }
endfunction
