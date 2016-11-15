function! neomake#makers#ft#mail#EnabledMakers() abort
    return executable('proselint') ? ['proselint'] : []
endfunction

function! neomake#makers#ft#mail#proselint() abort
    return neomake#makers#proselint#proselint()
endfunction
