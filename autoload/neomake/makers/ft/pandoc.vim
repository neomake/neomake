function! neomake#makers#ft#pandoc#EnabledMakers()
    return ['mdl', 'proselint']
endfunction

function! neomake#makers#ft#pandoc#mdl()
    return {
                \ 'errorformat':
                \ '%f:%l: %m'
                \ }
endfunction

function! neomake#makers#ft#pandoc#proselint()
    return {
                \ 'errorformat': '%f:%l:%c: %m'
                \ }
endfunction
