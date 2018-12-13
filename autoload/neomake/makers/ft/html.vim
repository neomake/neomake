function! neomake#makers#ft#html#tidy() abort
    return {
                \ 'args': ['-e', '-q', '--gnu-emacs', 'true'],
                \ 'errorformat': '%A%f:%l:%c: Warning: %m',
                \ }
endfunction

function! neomake#makers#ft#html#htmlhint() abort
    return {
                \ 'args': ['--format', 'unix'],
                \ 'errorformat': '%f:%l:%c: %m',
                \ }
endfunction

function! neomake#makers#ft#html#EnabledMakers() abort
    return ['tidy', 'htmlhint']
endfunction
" vim: ts=4 sw=4 et
