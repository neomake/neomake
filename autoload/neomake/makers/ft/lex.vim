" vim: ts=4 sw=4 et

function! neomake#makers#ft#lex#EnabledMakers()
    let makers = []
    if executable('flex')
        call add(makers, 'flex')
    endif
    return makers
endfunction

function! neomake#makers#ft#lex#flex()

    return {
            \ 'errorformat': '%f:%l: %m'
         \ }
endfunction
