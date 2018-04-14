function! neomake#makers#ft#xslt#EnabledMakers() abort
    return ['xmllint']
endfunction

function! neomake#makers#ft#xslt#xmllint() abort
    return neomake#makers#ft#xml#xmllint()
endfunction
