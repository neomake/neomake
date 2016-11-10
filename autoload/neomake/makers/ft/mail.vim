function! neomake#makers#ft#mail#EnabledMakers()
    return ['proselint']
endfunction

function! neomake#makers#ft#mail#proselint()
    return {
                \ 'errorformat': '%f:%l:%c: %m'
                \ }
endfunction
