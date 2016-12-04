" vim: ts=4 sw=4 et

function! neomake#makers#ft#ansible#EnabledMakers() abort
    return ['ansiblelint']
endfunction

function! neomake#makers#ft#ansible#ansiblelint() abort
    return {
        \ 'exe': 'ansible-lint',
        \ 'args': ['-p', '--nocolor'],
        \ 'errorformat': '%f:%l: [%tANSIBLE%n] %m',
        \ }
endfunction
