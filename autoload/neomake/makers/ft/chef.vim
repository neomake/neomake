function! neomake#makers#ft#chef#SupersetOf() abort
    return 'ruby'
endfunction

function! neomake#makers#ft#chef#EnabledMakers() abort
    let ruby_makers = neomake#makers#ft#ruby#EnabledMakers()
    return ruby_makers + ['foodcritic']
endfunction

function! neomake#makers#ft#chef#foodcritic() abort
    return {
      \ 'errorformat': '%WFC%n: %m: %f:%l',
      \ }
endfunction
