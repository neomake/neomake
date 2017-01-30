if !exists('g:neomake_test_messages')
  " Only use it during tests.
  finish
endif

function! neomake#makers#ft#neomake_tests#EnabledMakers() abort
  return get(g:, 'neomake_test_enabledmakers',
        \ ['maker_without_exe', 'nonexisting'])
endfunction

function! neomake#makers#ft#neomake_tests#maker_without_exe() abort
  return {}
endfunction
