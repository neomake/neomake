function! neomake#makers#ft#sql#EnabledMakers()
    return ['sqlint']
endfunction

function! neomake#makers#ft#sql#sqlint()
    return {
        \ 'errorformat':
            \ '%E%f:%l:%c:ERROR %m,' .
            \ '%W%f:%l:%c:WARNING %m,' .
            \ '%C %m'
        \ }
endfunction
