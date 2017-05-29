function! neomake#makers#ft#chef#SupersetOf() abort
    return 'ruby'
endfunction

function! neomake#makers#ft#chef#EnabledMakers() abort
    let ruby_makers = neomake#makers#ft#ruby#EnabledMakers()
    return ruby_makers + ['foodcritic'] + ['cookstyle']
endfunction

function! neomake#makers#ft#chef#foodcritic() abort
    return {
      \ 'errorformat': '%WFC%n: %m: %f:%l',
      \ }
endfunction

function! neomake#makers#ft#chef#cookstyle() abort
    return {
      \ 'args': [ '-f', 'emacs', '--except', 'Style'],
      \ 'errorformat': '%f:%l:%c: %t: %m,%E%f:%l: %m',
      \ }
endfunction
