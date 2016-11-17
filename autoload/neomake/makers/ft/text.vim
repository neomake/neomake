function! neomake#makers#ft#text#EnabledMakers() abort
    return ['proselint']
endfunction

function! neomake#makers#ft#text#proselint() abort
    return neomake#makers#text#proselint()
endfunction
