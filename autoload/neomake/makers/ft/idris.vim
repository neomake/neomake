function! neomake#makers#ft#idris#EnabledMakers() abort
    return ['idris']
endfunction

function! neomake#makers#ft#idris#idris() abort
    return {
        \ 'exe': 'idris',
        \ 'args': ['--check', '--warn', '--total', '--warnpartial', '--warnreach'],
        \ 'errorformat':
            \ '%f:%l:%c%.%#:,%m' ,
        \ }
endfunction
