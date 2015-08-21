function! neomake#makers#ft#lua#EnabledMakers()
    return ['luacheck']
endfunction

function! neomake#makers#ft#lua#luacheck()
    return {
        \ 'args': ['--no-color'],
        \ 'errorformat': '%f:%l:%c: %m,%-G%.%#',
        \ }
endfunction
