
function! neomake#makers#ft#haskell#EnabledMakers()
    return ['ghcmod', 'hlint']
endfunction

function! neomake#makers#ft#haskell#ghcmod()
    " This filters out newlines, which is what neovim gives us instead of the
    " null bytes that ghc-mod sometimes spits out.
    let mapexpr = 'substitute(v:val, "\n", "", "g")'
    return {
        \ 'exe': 'ghc-mod',
        \ 'args': ['check'],
        \ 'mapexpr': mapexpr,
        \ 'errorformat':
            \ '%-G%\s%#,' .
            \ '%f:%l:%c:%trror: %m,' .
            \ '%f:%l:%c:%tarning: %m,'.
            \ '%f:%l:%c: %trror: %m,' .
            \ '%f:%l:%c: %tarning: %m,' .
            \ '%f:%l:%c:%m,' .
            \ '%E%f:%l:%c:,' .
            \ '%Z%m'
        \ }
endfunction

function! neomake#makers#ft#haskell#hlint()
    return {
        \ 'errorformat':
            \ '%E%f:%l:%v: Error: %m,' .
            \ '%W%f:%l:%v: Warning: %m,' .
            \ '%C%m'
        \ }
endfunction
