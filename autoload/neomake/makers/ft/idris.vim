function! neomake#makers#ft#idris#EnabledMakers() abort
    return ['idris']
endfunction

function! neomake#makers#ft#idris#postprocess(entry) abort
  call neomake#utils#CompressWhitespace(a:entry)
  " Extract length from the beginning of the entry ('-4:When checking left hand side of xor:').
  if a:entry.text =~# '\v^\d+:'
    let end = 0 + a:entry.text  " cast to int
    let a:entry.length = end - a:entry.col
    let a:entry.text = substitute(a:entry.text, '\v^([^:]+:){2} ', '', '')
  endif
endfunction

function! neomake#makers#ft#idris#idris() abort
    return {
        \ 'exe': 'idris',
        \ 'args': ['--check', '--warn', '--total', '--warnpartial', '--warnreach'],
        \ 'errorformat':
        \   '%E%f:%l:%c:%.%#,%-C  %#%m,%-C%.%#,'.
        \   '%E%f:%l:%c-%m,%-C  %#%m,%-C%.%#',
        \ 'postprocess': function('neomake#makers#ft#idris#postprocess'),
        \ }
endfunction
