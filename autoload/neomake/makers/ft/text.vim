function! neomake#makers#ft#text#EnabledMakers() abort
    return executable('proselint') ? ['proselint'] : []
endfunction

function! neomake#makers#ft#text#proselint() abort
    return neomake#makers#proselint#proselint()
endfunction
