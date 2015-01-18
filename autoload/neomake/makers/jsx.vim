" vim: ts=4 sw=4 et

function! neomake#makers#jsx#EnabledMakers()
    return ['jsxhint']
endfunction

function! neomake#makers#jsx#jsxhint()
    " This will still call jsxhint, just using all the normal jshint options
    return neomake#makers#javascript#jshint()
endfunction
