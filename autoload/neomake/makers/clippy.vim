" vim: ts=4 sw=4 et

" Yet to be determined
let s:rustup_has_nightly = -1

function! neomake#makers#clippy#clippy() abort
    let errorfmt = neomake#makers#ft#rust#rustc()['errorformat']

    " When rustup and a nightly toolchain is installed, that is used.
    " Otherwise, the default cargo exectuable is used. If this is not part
    " of a nightly rust, this will fail.
    if s:rustup_has_nightly == -1
        if !executable('rustup')
            let s:rustup_has_nightly = 0
            call system('rustc --version | grep -q "\-nightly"')
            if v:shell_error
                call neomake#utils#ErrorMessage('Clippy requires a nightly rust installation.')
            endif
        else
            call system('rustup show | grep -q "^nightly-"')
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
