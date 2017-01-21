function! neomake#makers#ft#css#EnabledMakers() abort
    return ['csslint', 'stylelint']
endfunction

function! neomake#makers#ft#css#csslint() abort
  return {
        \ 'args': ['--format=compact'],
        \ 'errorformat':
        \   '%-G,'.
        \   '%-G%f: lint free!,'.
        \   '%f: line %l\, col %c\, %trror - %m,'.
        \   '%f: line %l\, col %c\, %tarning - %m,'.
        \   '%f: line %l\, col %c\, %m,'.
        \   '%f: %tarning - %m'
        \ }
endfunction

function! neomake#makers#ft#css#stylelint() abort
    return {
          \ 'errorformat':
          \   '%+P%f,'. 
          \   '%*\s%l:%c  %t  %m,'.
          \   '%-Q'
          \ }
endfunction
