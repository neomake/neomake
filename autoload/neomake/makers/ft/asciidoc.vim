function! neomake#makers#ft#asciidoc#SupersetOf() abort
    return 'text'
endfunction

function! neomake#makers#ft#asciidoc#EnabledMakers() abort
    return ['asciidoc'] + neomake#makers#ft#text#EnabledMakers()
endfunction

function! neomake#makers#ft#asciidoc#asciidoc() abort
    return {
        \ 'errorformat':
        \   '%E%\w%\+: %tRROR: %f: line %l: %m,' .
        \   '%E%\w%\+: %tRROR: %f: %m,' .
        \   '%E%\w%\+: FAILED: %f: line %l: %m,' .
        \   '%E%\w%\+: FAILED: %f: %m,' .
        \   '%W%\w%\+: %tARNING: %f: line %l: %m,' .
        \   '%W%\w%\+: %tARNING: %f: %m,' .
        \   '%W%\w%\+: DEPRECATED: %f: line %l: %m,' .
        \   '%W%\w%\+: DEPRECATED: %f: %m'
        \ }
endfunction

function! neomake#makers#ft#asciidoc#asciidoctor() abort
    return neomake#makers#ft#asciidoc#asciidoc()
endfunction
