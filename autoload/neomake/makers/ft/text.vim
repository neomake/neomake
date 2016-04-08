function! neomake#makers#ft#text#EnabledMakers()
    return ['proselint']
endfunction

function! neomake#makers#ft#text#proselint()
    return {
                \ 'errorformat': '%f:%l:%c: %m'
                \ }
endfunction
