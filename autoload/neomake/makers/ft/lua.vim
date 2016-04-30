function! neomake#makers#ft#lua#EnabledMakers()
    if executable('luacheck')
        return ['luacheck']
    endif
    return ['luac']
endfunction

function! neomake#makers#ft#lua#luacheck()
    return {
        \ 'args': ['--no-color'],
        \ 'errorformat': '%f:%l:%c: %m,%-G%.%#',
        \ }
endfunction

function! neomake#makers#ft#lua#luac()
    return {
        \ 'args': ['-p'],
        \ 'errorformat': 'luac: %f:%l: %m',
        \ }
endfunction
