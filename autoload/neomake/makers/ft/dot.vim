" vim: ts=4 sw=4 et
" inspired by wmgraphviz.vim
function! neomake#makers#ft#dot#EnabledMakers()
    if neomake#utils#Exists('dot')
        return ['dot']
    end
endfunction

function! neomake#makers#ft#dot#dot()
    return {
        \ 'args': ['-Tpng', '%:p', '> %:p.png'],
        \ 'errorformat':
            \ '%EError:\ %f:%l:%m,%+Ccontext:\ %.%#,%WWarning:\ %m'
        \ }
endfunction

