function! neomake#makers#ft#chef#SupersetOf()
    return 'ruby'
endfunction

function! neomake#makers#ft#chef#foodcritic()
    return {
      \ 'errorformat': 'FC%n: %m: %f:%l',
      \ 'postprocess': function('neomake#makers#ft#chef#FoodcriticProcess'),
      \ }
endfunction

function! neomake#makers#ft#chef#FoodcriticProcess(entry)
  let a:entry.type='W'
endfunction

function! neomake#makers#ft#chef#EnabledMakers()
    let ruby_makers = neomake#makers#ft#ruby#EnabledMakers()
    return ruby_makers + ['foodcritic']
endfunction

function! neomake#makers#ft#chef#mri()
    return neomake#makers#ft#ruby#mri()
endfunction

function! neomake#makers#ft#chef#rubocop()
    return neomake#makers#ft#ruby#rubocop()
endfunction

function! neomake#makers#ft#chef#reek()
    return neomake#makers#ft#ruby#reek()
endfunction

function! neomake#makers#ft#chef#rubylint()
    return neomake#makers#ft#ruby#rubylint()
endfunction
