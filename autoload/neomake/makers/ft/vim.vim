" vim: ts=4 sw=4 et

function! neomake#makers#ft#vim#EnabledMakers() abort
    return ['vint']
endfunction

function! neomake#makers#ft#vim#vint() abort
    return {
        \ 'args': ['--style-problem'],
        \ 'errorformat':
            \ '%f:%l:%c: %m,'
        \ }
endfunction
