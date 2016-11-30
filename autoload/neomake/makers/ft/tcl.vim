function! neomake#makers#ft#tcl#EnabledMakers()
   return ['nagelfar']
endfunction

function! neomake#makers#ft#tcl#nagelfar()
   return {
      \ 'exe': 'nagelfar',
      \ 'args': ['-H'],
      \ 'errorformat':
         \ '%I%f: %l: N %m,' .
         \ '%f: %l: %t %m,' .
         \ '%-GChecking file %f'
      \ }
endfunction

