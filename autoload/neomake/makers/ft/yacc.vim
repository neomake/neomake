" vim: ts=4 sw=4 et

function! neomake#makers#ft#yacc#EnabledMakers() abort
    let makers = []
    if executable('bison')
        call add(makers, 'bison')
    endif
    return makers
endfunction

function! neomake#makers#ft#yacc#bison() abort
    return {
            \ 'errorformat':
                \ '%E%f:%l%.%v-%.%\{-}: %trror: %m,' .
                \ '%E%f:%l%.%v: %trror: %m,' .
                \ '%W%f:%l%.%v-%.%\{-}: %tarning: %m,' .
                \ '%W%f:%l%.%v: %tarning: %m,' .
                \ '%I%f:%l%.%v-%.%\{-}: %\s%\+%m,' .
                \ '%I%f:%l%.%v: %\s%\+%m'
        \ }
endfunction
