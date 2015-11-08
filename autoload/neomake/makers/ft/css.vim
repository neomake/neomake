function! neomake#makers#ft#css#EnabledMakers()
    return ['csslint']
endfunction

function! neomake#makers#ft#css#csslint()
    return {
        \ 'args': ['--format=compact'],
        \ 'errorformat':
            \ '%-G,' .
            \ '%-G%f: lint free!,' .
            \ '%f: line %l\, col %c\, %trror - %m,' .
            \ '%f: line %l\, col %c\, %tarning - %m,'.
            \ '%f: line %l\, col %c\, %m,'
    \ }
endfunction
