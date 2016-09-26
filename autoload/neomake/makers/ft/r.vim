" vim: ts=4 sw=4 et

if !exists('g:neomake_r_lintr_cache')
    let g:neomake_r_lintr_cache = 'FALSE'
endif

if !exists('g:neomake_r_lintr_linters')
    let g:neomake_r_lintr_linters = 'default_linters'
endif

function! neomake#makers#ft#r#EnabledMakers()
  return ['lintr']
endfunction

function! neomake#makers#ft#r#lintr()
  return {
        \ 'exe' : 'R',
        \ 'args' : ['--slave',
                  \ '--no-restore',
                  \ '--no-save',
                  \ '-e', 'suppressPackageStartupMessages(library(lintr))',
                  \ '-e', 'lint(cache = ' . g:neomake_r_lintr_cache . ', commandArgs(TRUE), ' . g:neomake_r_lintr_linters . ')',
                  \ '--args'],
                  \ 'errorformat':
          \ '%I%f:%l:%c: style: %m,' .
          \ '%W%f:%l:%c: warning: %m,' .
          \ '%E%f:%l:%c: error: %m,'
        \ }
endfunction
