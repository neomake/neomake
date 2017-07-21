function! neomake#makers#ft#solidity#EnabledMakers() abort
    return ['solium']
endfunction

function! neomake#makers#ft#solidity#solium() abort
    return {
        \ 'exe': 'solium',
        \ 'args': ['--reporter', 'gcc', '--file'],
        \ 'errorformat':
            \ '%f:%l:%c: %t%s: %m',
        \ }
endfunction
