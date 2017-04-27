function! neomake#makers#ft#applescript#EnabledMakers() abort
    return ['osacompile']
endfunction

function! neomake#makers#ft#applescript#osacompile() abort
    return {
        \ 'args': ['-o', neomake#utils#DevNull()],
        \ 'errorformat': '%f:%l: %trror: %m',
        \ }
endfunction
