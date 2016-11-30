function! neomake#makers#ft#applescript#EnabledMakers()
    return ['osacompile']
endfunction

function! neomake#makers#ft#applescript#osacompile()
    return {
        \ 'args': ['-o', neomake#utils#DevNull()],
        \ 'errorformat': '%f:%l: %trror: %m',
        \ }
endfunction
