function! neomake#makers#ft#chef#SupersetOf() abort
    return 'ruby'
endfunction

function! neomake#makers#ft#chef#foodcritic() abort
    return {
      \ 'errorformat': 'FC%n: %m: %f:%l',
      \ 'postprocess': function('neomake#makers#ft#chef#FoodcriticProcess'),
      \ }
endfunction

function! neomake#makers#ft#chef#FoodcriticProcess(entry) abort
  let a:entry.type='W'
endfunction

function! neomake#makers#ft#chef#EnabledMakers() abort
    let ruby_makers = neomake#makers#ft#ruby#EnabledMakers()
    return ruby_makers + ['foodcritic']
endfunction

function! neomake#makers#ft#chef#mri() abort
    return neomake#makers#ft#ruby#mri()
endfunction

function! neomake#makers#ft#chef#rubocop() abort
    return neomake#makers#ft#ruby#rubocop()
endfunction

function! neomake#makers#ft#chef#reek() abort
    return neomake#makers#ft#ruby#reek()
endfunction

function! neomake#makers#ft#chef#rubylint() abort
    return neomake#makers#ft#ruby#rubylint()
endfunction
