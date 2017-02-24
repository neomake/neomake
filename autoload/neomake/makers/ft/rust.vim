" vim: ts=4 sw=4 et

function! neomake#makers#ft#rust#EnabledMakers() abort
    return ['cargo']
endfunction

function! neomake#makers#ft#rust#rustc() abort
    return {
        \ 'errorformat':
            \ '%-Gerror: aborting due to previous error,'.
            \ '%-Gerror: aborting due to %\\d%\\+ previous errors,'.
            \ '%-Gerror: Could not compile `%s`.,'.
            \ '%Eerror[E%n]: %m,'.
            \ '%Eerror: %m,'.
            \ '%Wwarning: %m,'.
            \ '%Inote: %m,'.
            \ '%-Z\ %#-->\ %f:%l:%c,'.
            \ '%G\ %#\= %*[^:]: %m,'.
            \ '%G\ %#|\ %#%\\^%\\+ %m,'.
            \ '%I%>help:\ %#%m,'.
            \ '%Z\ %#%m,'.
            \ '%-G%s',
        \ }
endfunction

function! neomake#makers#ft#rust#cargo() abort
    return {
        \ 'args': ['build'],
        \ 'append_file': 0,
        \ 'errorformat':
            \ ',' .
            \ '%-G,' .
            \ '%-Gerror: aborting %.%#,' .
            \ '%-Gerror: Could not compile %.%#,' .
            \ '%Eerror: %m,' .
            \ '%Eerror[E%n]: %m,' .
            \ '%-Gwarning: the option `Z` is unstable %.%#,' .
            \ '%Wwarning: %m,' .
            \ '%Inote: %m,' .
            \ '%C %#--> %f:%l:%c',
        \ }
endfunction
