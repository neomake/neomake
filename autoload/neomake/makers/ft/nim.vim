function! neomake#makers#ft#nim#EnabledMakers()
    return ['nim']
endfunction

function! neomake#makers#ft#nim#nim()
    return {
                \ 'exe': 'nim',
                \ 'args': ['--listFullPaths', '--verbosity:0', '--colors:off',
                \   '-c', 'check'],
                \ 'errorformat':
                \   '%I%f(%l\, %c) Hint: %m,' .
                \   '%W%f(%l\, %c) Warning: %m,' .
                \   '%E%f(%l\, %c) Error: %m'
                \ }
endfunction
