function! neomake#makers#ft#tcl#EnabledMakers() abort
   return ['nagelfar']
endfunction

function! neomake#makers#ft#tcl#nagelfar() abort
   return {
      \ 'exe': 'nagelfar',
      \ 'args': ['-H'],
      \ 'errorformat':
         \ '%I%f: %l: N %m,' .
         \ '%f: %l: %t %m,' .
         \ '%-GChecking file %f'
      \ }
endfunction

