" vim: ts=4 sw=4 et

function! neomake#makers#ft#jsx#EnabledMakers()
    return ['jsxhint']
endfunction

function! neomake#makers#ft#jsx#jsxhint()
    " This will still call jsxhint, just using all the normal jshint options
    return neomake#makers#ft#javascript#jshint()
endfunction
