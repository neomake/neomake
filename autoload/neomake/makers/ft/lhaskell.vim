
function! neomake#makers#ft#lhaskell#EnabledMakers()
    " enable linters which claim literate haskell support
    return ['ghcmod', 'hdevtools', 'hlint']
endfunction

function! neomake#makers#ft#lhaskell#hdevtools()
    return neomake#makers#ft#haskell#hdevtools()
endfunction

function! neomake#makers#ft#lhaskell#ghcmod()
    return neomake#makers#ft#haskell#ghcmod()
endfunction

function! neomake#makers#ft#lhaskell#hlint()
    return neomake#makers#ft#haskell#hlint()
endfunction
