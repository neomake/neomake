function! neomake#makers#ft#text#EnabledMakers() abort
    return ['writegood']
endfunction

function! neomake#makers#ft#text#writegood() abort
    return neomake#makers#ft#markdown#writegood()
endfunction
