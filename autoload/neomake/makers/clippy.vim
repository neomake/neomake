" vim: ts=4 sw=4 et

function! neomake#makers#clippy#clippy() abort
    " When rustup and a nightly toolchain is installed, that is used.
    " Otherwise, the default cargo exectuable is used. If this is not part
    " of a nightly rust, this will fail.
    if get(g:, 'neomake_clippy_rustup_has_nightly', -1) == -1
        if !executable('rustup')
            let g:neomake_clippy_rustup_has_nightly = 0
            call system('rustc --version | grep -q "\-nightly"')
            if v:shell_error
                call neomake#log#warning('Clippy requires a nightly rust installation.')
            endif
        else
            call system('rustup show | grep -q "^nightly-"')
            let g:neomake_clippy_rustup_has_nightly = !v:shell_error
        endif
    endif

    let cargo_maker = neomake#makers#ft#rust#cargo()
    let json_args = ['--message-format=json', '--quiet']

    if g:neomake_clippy_rustup_has_nightly
        let maker = {
            \ 'exe': 'rustup',
            \ 'args': ['run', 'nightly', 'cargo', 'clippy'] + json_args,
            \ 'process_output': cargo_maker.process_output,
            \ }
    else
        let maker = {
            \ 'exe': 'cargo',
            \ 'args': ['clippy'] + json_args,
            \ 'process_output': cargo_maker.process_output,
            \ }
    endif
    " InitForJob will lazily initialize cwd for us.
    let maker.InitForJob = cargo_maker.InitForJob
    return maker
endfunction
