" vim: ts=4 sw=4 et

function! neomake#makers#clippy#clippy() abort
    let errorfmt = '%Eerror[E%n]: %m,'.
                 \ '%Eerror: %m,'.
                 \ '%Wwarning: %m,'.
                 \ '%Inote: %m,'.
                 \ '%-Z\ %#-->\ %f:%l:%c,'.
                 \ '%I\ %#\= %t%*[^:]: %m,'.
                 \ '%I\ %#|\ %#%\\^%\\+ %m,'.
                 \ '%-G%s,'

    " When rustup and a nightly toolchain is installed, that is used.
    " Otherwise, the default cargo exectuable is used. If this is not part
    " of a nightly rust, this will fail.
    if !exists('s:rustup_has_nightly')
        if !executable('rustup')
            let s:rustup_has_nightly = false
        else
            call system('rustup show | grep -q nightly')
            let s:rustup_has_nightly = !v:shell_error
        endif
    endif

    if s:rustup_has_nightly
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
    endif
endfunction
