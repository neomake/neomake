function! neomake#makers#ft#pandoc#EnabledMakers()
    return neomake#makers#ft#markdown#EnabledMakers()
endfunction

function! neomake#makers#ft#pandoc#mdl()
    return neomake#makers#ft#markdown#mdl()
endfunction

function! neomake#makers#ft#pandoc#proselint()
    return neomake#makers#ft#markdown#proselint()
endfunction
