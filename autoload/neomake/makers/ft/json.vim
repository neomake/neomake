function! neomake#makers#ft#json#EnabledMakers()
    return ['jsonlint']
endfunction

function! neomake#makers#ft#json#jsonlint()
    return {
        \ 'args': ['--compact'],
        \ 'errorformat':
            \ '%ELine %l:%c,'.
            \ '%Z\\s%#Reason: %m,'.
            \ '%C%.%#,'.
            \ '%f: line %l\, col %c\, %m,'.
	    	\ '%-G%.%#'
        \ }
endfunction
