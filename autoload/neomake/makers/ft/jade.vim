" vim: ts=4 sw=4 et

function! neomake#makers#ft#jade#EnabledMakers()
    return ['jadelint']
endfunction

function! neomake#makers#ft#jade#jadelint()
    return {
        \ 'exe': 'jade-lint',
        \ 'args': ['--reporter', 'inline'],
        \ 'errorformat': '%f:%l:%c %m'
        \ }
endfunction
