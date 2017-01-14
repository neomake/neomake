" vim: ts=4 sw=4 et

function! neomake#makers#ft#lex#EnabledMakers() abort
    let makers = []
    if executable('flex')
        call add(makers, 'flex')
    endif
    return makers
endfunction

function! neomake#makers#ft#lex#flex() abort
    return {
            \ 'errorformat': '%f:%l: %m'
         \ }
endfunction
