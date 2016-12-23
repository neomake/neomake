function! neomake#makers#ft#pandoc#EnabledMakers() abort
    return neomake#makers#ft#markdown#EnabledMakers()
endfunction

function! neomake#makers#ft#pandoc#mdl() abort
    return neomake#makers#ft#markdown#mdl()
endfunction

function! neomake#makers#ft#pandoc#markdownlint() abort
    return neomake#makers#ft#markdown#markdownlint()
endfunction

function! neomake#makers#ft#pandoc#proselint() abort
    return neomake#makers#ft#markdown#proselint()
endfunction

function! neomake#makers#ft#pandoc#writegood() abort
    return neomake#makers#ft#markdown#writegood()
endfunction
