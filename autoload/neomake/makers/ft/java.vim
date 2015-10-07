function! neomake#makers#ft#java#EnabledMakers()
        return ['javac']
endfunction

function! neomake#makers#ft#java#javac()
    return {
         \ 'errorformat':
                \ '%f:%l: error: %m'
         \ }
endfunction
