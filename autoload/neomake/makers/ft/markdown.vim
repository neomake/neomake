function! neomake#makers#ft#markdown#EnabledMakers()
    return ['mdl']
endfunction

function! neomake#makers#ft#markdown#mdl()
    return {
                \ 'errorformat':
                \ '%f:%l: %m'
                \ }
endfunction
