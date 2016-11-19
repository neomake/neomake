" vim: ts=4 sw=4 et
function! neomake#makers#ft#text#EnabledMakers() abort
    return ['proselint']
endfunction

function! neomake#makers#ft#text#proselint() abort
    return {
                \ 'errorformat': '%W%f:%l:%c: %m'
                \ }
endfunction
