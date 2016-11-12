function! neomake#makers#ft#markdown#EnabledMakers() abort
    if executable('mdl') && executable('markdownlint')
        return ['mdl', 'proselint', 'writegood']
    endif

    return ['mdl', 'markdownlint', 'proselint', 'writegood']
endfunction

function! neomake#makers#ft#markdown#mdl() abort
    return {
                \ 'errorformat':
                \ '%f:%l: %m'
                \ }
endfunction

function! neomake#makers#ft#markdown#proselint() abort
    return {
                \ 'errorformat': '%f:%l:%c: %m'
                \ }
endfunction

function! neomake#makers#ft#markdown#writegood() abort
    return {
                \ 'args': ['--parse'],
                \ 'errorformat': '%W%f:%l:%c:%m'
                \ }
endfunction

function! neomake#makers#ft#markdown#markdownlint() abort
    return {
                \ 'errorformat':
                \ '%f: %l: %m'
                \ }
endfunction
