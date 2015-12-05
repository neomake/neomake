" vim: ts=4 sw=4 et

function! neomake#makers#ft#haml#EnabledMakers()
    return ['hamllint']
endfunction

function! neomake#makers#ft#haml#hamllint()
    return {
        \ 'exe': 'haml-lint',
        \ 'args': ['--no-color'],
        \ 'errorformat': '%f:%l %m'
        \ }
endfunction
