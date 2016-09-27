function! neomake#makers#ft#markdown#EnabledMakers()
    if executable('mdl') && executable('markdownlint')
        return ['mdl', 'proselint', 'writegood']
    endif

    return ['mdl', 'markdownlint', 'proselint', 'writegood']
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

function! neomake#makers#ft#markdown#writegood()
    return {
                \ 'args': ['--parse'],
                \ 'errorformat': '%f:%l:%c:%m'
                \ }
endfunction

function! neomake#makers#ft#markdown#markdownlint()
    return {
                \ 'errorformat':
                \ '%f: %l: %m'
                \ }
endfunction
