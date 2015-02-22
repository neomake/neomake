" vim: ts=4 sw=4 et

function! neomake#makers#ft#c#EnabledMakers()
    if neomake#utils#Exists('clang')
        return ['clang']
    else
        return ['gcc']
    end
endfunction

function! neomake#makers#ft#c#clang()
    return {
        \ 'args': ['-fsyntax-only', '-Wall', '-Wextra'],
        \ 'errorformat':
            \ '%-G%f:%s:,' .
            \ '%f:%l:%c: %trror: %m,' .
            \ '%f:%l:%c: %tarning: %m,' .
            \ '%f:%l:%c: %m,'.
            \ '%f:%l: %trror: %m,'.
            \ '%f:%l: %tarning: %m,'.
            \ '%f:%l: %m',
        \ }
endfunction

function! neomake#makers#ft#c#gcc()
    return {
        \ 'args': ['-fsyntax-only', '-Wall', '-Wextra'],
        \ 'errorformat':
            \ '%-G%f:%s:,' .
            \ '%-G%f:%l: %#error: %#(Each undeclared identifier is reported only%.%#,' .
            \ '%-G%f:%l: %#error: %#for each function it appears%.%#,' .
            \ '%-GIn file included%.%#,' .
            \ '%-G %#from %f:%l\,,' .
            \ '%f:%l:%c: %trror: %m,' .
            \ '%f:%l:%c: %tarning: %m,' .
            \ '%f:%l:%c: %m,' .
            \ '%f:%l: %trror: %m,' .
            \ '%f:%l: %tarning: %m,'.
            \ '%f:%l: %m',
        \ }
endfunction
