" vim: ts=4 sw=4 et
function! neomake#makers#ft#svelte#EnabledMakers() abort
    let makers = []
    if executable('svelte-check')
        call add(makers, 'svelte_check')
    endif
    if executable('eslint')
        call add(makers, 'eslint')
    endif
    return makers
endfunction

function! neomake#makers#ft#svelte#svelte_check() abort
    let maker = {
                \ 'exe': 'svelte-check',
                \ 'args': ['--output', 'machine'],
                \ 'append_file': 0,
                \ 'errorformat':
                    \ '%E\\d%\\+ ERROR \"%f\" %l:%c \"%m\",' .
                    \ '%W%\\d%\\+ WARNING \"%f\" %l:%c \"%m\",' .
                    \ '%-G%.%#',
                \ }
    return maker
endfunction

function! neomake#makers#ft#svelte#eslint() abort
    return neomake#makers#ft#javascript#eslint()
endfunction
