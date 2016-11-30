" vim: ts=4 sw=4 et

function! neomake#makers#ft#rust#EnabledMakers() abort
    return ['rustc']
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
