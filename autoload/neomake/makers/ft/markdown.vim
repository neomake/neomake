function! neomake#makers#ft#markdown#EnabledMakers()
    return ['mdl', 'proselint']
endfunction

function! neomake#makers#ft#markdown#mdl()
    return {
                \ 'errorformat':
                \ '%f:%l: %m'
                \ }
endfunction

function! neomake#makers#ft#markdown#proselint()
    return {
                \ 'errorformat': '%f:%l:%c: %m'
                \ }
endfunction
