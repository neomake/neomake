function! neomake#makers#ft#text#EnabledMakers()
    return ['proselint', 'writegood']
endfunction

function! neomake#makers#ft#text#writegood()
    return {
                \ 'args': ['--parse'],
                \ 'errorformat': '%W%f:%l:%c:%m'
                \ }
endfunction

function! neomake#makers#ft#text#proselint()
    return {
                \ 'errorformat': '%f:%l:%c: %m'
                \ }
endfunction
