function! neomake#makers#ft#text#EnabledMakers() abort
    return ['writegood', 'proselint']
endfunction

function! neomake#makers#ft#text#writegood() abort
    return neomake#makers#ft#markdown#writegood()
endfunction

function! neomake#makers#ft#text#proselint() abort
    return neomake#makers#ft#markdown#proselint()
endfunction
