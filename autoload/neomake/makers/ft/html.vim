function! neomake#makers#ft#html#tidy()
    return {
                \ 'args': ['-e', '-q', '--gnu-emacs', 'true'],
                \ 'errorformat': '%A%f:%l:%c: Warning: %m',
                \ }
endfunction

function! neomake#makers#ft#html#EnabledMakers()
    return ['tidy']
endfunction
