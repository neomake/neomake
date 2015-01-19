" vim: ts=4 sw=4 et

function! neomake#makers#c#EnabledMakers()
    let makers = []
    if neomake#utils#Exists('clang')
        call add(makers, 'clang')
    else
        call add(makers, 'gcc')
    end
    return makers
endfunction

function! neomake#makers#c#clang()
    return {
        \ 'exe': 'clang',
        \ 'args': ['-fsyntax-only'],
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

function! neomake#makers#c#gcc()
    return {
        \ 'exe': 'clang',
        \ 'args': ['-fsyntax-only'],
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
