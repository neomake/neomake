" vim: ts=4 sw=4 et

function! neomake#makers#ft#pug#EnabledMakers()
    return ['puglint']
endfunction

function! neomake#makers#ft#pug#puglint()
    return {
        \ 'exe': 'pug-lint',
        \ 'args': ['--reporter', 'inline'],
        \ 'errorformat': '%f:%l:%c %m'
        \ }
endfunction
