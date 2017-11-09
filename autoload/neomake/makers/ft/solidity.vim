function! neomake#makers#ft#solidity#EnabledMakers() abort
    return ['solium', 'solhint']
endfunction

function! neomake#makers#ft#solidity#solium() abort
    return {
        \ 'args': ['--reporter', 'gcc', '--file'],
        \ 'errorformat':
            \ '%f:%l:%c: %t%s: %m',
        \ }
endfunction

function! neomake#makers#ft#solidity#solhint() abort
    return {
        \ 'args': ['-f', 'compact'],
        \ 'errorformat': '%E%f: line %l\, col %c\, Error - %m,' .
        \   '%W%f: line %l\, col %c\, Warning - %m,%-G,%-G%*\d problems%#'
        \ }
endfunction
