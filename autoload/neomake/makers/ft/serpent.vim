function! neomake#makers#ft#serpent#EnabledMakers() abort
    return ['serplint']
endfunction

function! neomake#makers#ft#serpent#serplint() abort
    return {
        \ 'exe': 'serplint',
        \ 'args': [],
        \ 'errorformat':
            \ '%f:%l:%c %t%n %m',
        \ }
endfunction
