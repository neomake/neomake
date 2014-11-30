" vim: ts=4 sw=4 et

function! neomake#makers#ruby#EnabledMakers()
    return ['rubocop']
endfunction

function! neomake#makers#ruby#rubocop()
    return {
        \ 'args': ['--format', 'emacs'],
        \ 'errorformat': '%f:%l:%c: %t: %m'
        \ }
endfunction
