function! neomake#makers#ft#markdown#EnabledMakers()
    if executable('mdl') && executable('markdownlint')
        return ['mdl', 'proselint']
    endif

    return ['mdl', 'markdownlint', 'proselint']
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

function! neomake#makers#ft#markdown#markdownlint()
    return {
                \ 'errorformat':
                \ '%f: %l: %m'
                \ }
endfunction
