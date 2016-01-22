function! neomake#makers#ft#css#EnabledMakers()
    return ['csslint', 'stylelint']
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

function! neomake#makers#ft#css#stylelint()
    return {
        \ 'errorformat': '%+P%f, %W%l:%c%*\s%m, %-Q'
    \ }
endfunction
