" vim: ts=4 sw=4 et

function! neomake#makers#ft#slim#EnabledMakers()
    return ['slimlint']
endfunction

function! neomake#makers#ft#slim#slimlint()
    return {
        \ 'exe': 'slim-lint',
        \ 'args': ['--no-color'],
        \ 'errorformat': '%f:%l [%t] %m'
        \ }
endfunction
