" vim: ts=4 sw=4 et

function! neomake#makers#clippy#clippy()
    let errorfmt = '%Eerror[E%n]: %m,'.
                 \ '%Eerror: %m,'.
                 \ '%Wwarning: %m,'.
                 \ '%Inote: %m,'.
                 \ '%-Z\ %#-->\ %f:%l:%c,'.
                 \ '%I\ %#\= %t%*[^:]: %m,'.
                 \ '%I\ %#|\ %#%\\^%\\+ %m,'.
                 \ '%-G%s,'

    " When rustup and a nightly toolchain is installed, that is used
    " Otherwise, the default cargo exectuable is used. If this is not part
    " of a nightly rust, this will fail.
    if executable('rustup') && system('rustup show | grep nightly | wc -l') >= 2
        return {
            \ 'exe': 'rustup',
            \ 'args': ['run', 'nightly', 'cargo', 'clippy'],
            \ 'errorformat': errorfmt,
            \ }
    else
        return {
            \ 'exe': 'cargo',
            \ 'args': ['clippy'],
            \ 'errorformat': errorfmt,
            \ }
endfunction
