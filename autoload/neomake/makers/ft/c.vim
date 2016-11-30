" vim: ts=4 sw=4 et

function! neomake#makers#ft#c#EnabledMakers()
    let makers = executable('clang') ? ['clang', 'clangtidy', 'clangcheck'] : ['gcc']
    call add(makers, 'checkpatch')
    return makers
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

function! neomake#makers#ft#c#clangcheck()
    return {
        \ 'exe': 'clang-check',
        \ 'args': ['%:p'],
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

" The -p option followed by the path to the build directory should be set in
" the maker's arguments. That directory should contain the compile command
" database (compile_commands.json).
function! neomake#makers#ft#c#clangtidy()
    return {
        \ 'exe': 'clang-tidy',
        \ 'errorformat':
            \ '%E%f:%l:%c: fatal error: %m,' .
            \ '%E%f:%l:%c: error: %m,' .
            \ '%W%f:%l:%c: warning: %m,' .
            \ '%-G%\m%\%%(LLVM ERROR:%\|No compilation database found%\)%\@!%.%#,' .
            \ '%E%m',
        \ }
endfunction

function! neomake#makers#ft#c#checkpatch()
    return {
        \ 'exe': 'checkpatch.pl',
        \ 'args': ['--no-summary', '--no-tree', '--terse', '--file'],
        \ 'errorformat':
            \ '%f:%l: %tARNING: %m,' .
            \ '%f:%l: %tRROR: %m',
        \ }
endfunction
