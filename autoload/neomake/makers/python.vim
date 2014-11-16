
function! neomake#makers#python#EnabledMakers()
    return ['pylint', 'pyflakes', 'pep8']
endfunction

function! neomake#makers#python#pylint()
    return {
        \ 'args': [
            \ '-f', 'text',
            \ '--msg-template="{path}:{line}:{column}:{C}: [{symbol}] {msg}"',
            \ '-r', 'n'
        \ ],
        \ 'errorformat':
            \ '%A%f:%l:%c:%t: %m,' .
            \ '%A%f:%l: %m,' .
            \ '%A%f:(%l): %m,' .
            \ '%-Z%p^%.%#,' .
            \ '%-G%.%#',
        \ }
endfunction

function! neomake#makers#python#pyflakes()
    return {
        \ 'errorformat':
            \ '%E%f:%l: could not compile,' .
            \ '%-Z%p^,'.
            \ '%E%f:%l:%c: %m,' .
            \ '%E%f:%l: %m,' .
            \ '%-G%.%#',
        \ }
endfunction

function! neomake#makers#python#pep8()
    return {
        \ 'errorformat': '%f:%l:%c: %m',
        \ }
endfunction
