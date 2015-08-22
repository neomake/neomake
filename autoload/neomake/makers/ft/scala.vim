" vim: ts=4 sw=4 et
function! neomake#makers#ft#scala#EnabledMakers()
    let makers = ['scalac']
    if neomake#utils#Exists('scalastyle')
        call add(makers, 'scalastyle')
    return makers
endfunction

function! neomake#makers#ft#scala#scalac()
    return {
        \ 'args': [
            \ '-Ystop-after:parser'
        \ ],
        \ 'errorformat':
            \ '%E%f:%l: %trror: %m,' .
            \ '%Z%p^,' .
            \ '%-G%.%#'
        \ }
endfunction

function! neomake#makers#ft#scala#scalastyle()
    return {
        \ 'errorformat':
            \ '%trror file=%f message=%m line=%l column=%c,' .
            \ '%trror file=%f message=%m line=%l,' .
            \ '%tarning file=%f message=%m line=%l column=%c,' .
            \ '%tarning file=%f message=%m line=%l'
        \ }
endfunction
