" vim: ts=4 sw=4 et
function! neomake#makers#ft#scala#EnabledMakers()
    let makers = get(g:, 'neomake_scala_fast', 0) ? ['fsc'] : ['scalac']
    if neomake#utils#Exists('scalastyle') && get(g:, 'neomake_scala_style', 1)
        call add(makers, 'scalastyle')
    endif
    return makers
endfunction

function! neomake#makers#ft#scala#fsc()
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
