" vim: ts=4 sw=4 et

function! neomake#makers#ft#sh#EnabledMakers() abort
    return ['sh', 'shellcheck']
endfunction

function! s:shellcheck_determine_supported() abort
    let s:shellcheck_supported = ['sh', 'bash', 'dash', 'ksh']

    " zsh support was available from the first release of shellcheck and
    " removed in version 0.3.6. Before shellcheck version 0.3.1 there was no
    " way to get the version information.
    let l:version_line = matchstr(systemlist('shellcheck --version'), '^version:')
    if v:shell_error != 0
        let s:shellcheck_supported += ['zsh']
    else
        let l:version = matchstr(l:version_line, '^version:\s*\zs.*$')
        if neomake#utils#CompareSemanticVersions(l:version, '0.3.6') == -1
            let s:shellcheck_supported += ['zsh']
        endif
    endif
endfunction
call s:shellcheck_determine_supported()

function! s:shellcheck_getshell() abort
    let pattern = '^#\s*shellcheck\s*shell='
    let line = matchstr(getline(1, line('$')), l:pattern)
    return matchstr(l:line, l:pattern . '\zs[^ \t]*$')
endfunction

function! neomake#makers#ft#sh#shellcheck() abort
    let args = ['-fgcc']
    let shebang = matchstr(getline(1), '^#!\s*\zs.*$')
    if !len(shebang) && !len(s:shellcheck_getshell())
        if index(s:shellcheck_supported, &filetype) != -1
            let args += ['-s', &filetype]
        endif
    endif
    return {
        \ 'args': args,
        \ 'errorformat':
            \ '%f:%l:%c: %trror: %m,' .
            \ '%f:%l:%c: %tarning: %m,' .
            \ '%I%f:%l:%c: Note: %m',
        \ }
endfunction

function! neomake#makers#ft#sh#checkbashisms() abort
    return {
        \ 'args': ['-fx'],
        \ 'errorformat':
            \ '%-Gscript %f is already a bash script; skipping,' .
            \ '%Eerror: %f: %m\, opened in line %l,' .
            \ '%Eerror: %f: %m,' .
            \ '%Ecannot open script %f for reading: %m,' .
            \ '%Wscript %f %m,%C%.# lines,' .
            \ '%Wpossible bashism in %f line %l (%m):,%C%.%#,%Z.%#,' .
            \ '%-G%.%#'
        \ }
endfunction

function! neomake#makers#ft#sh#sh() abort
    let shebang = matchstr(getline(1), '^#!\s*\zs.*$')
    if len(shebang)
        let l = split(shebang)
        let exe = l[0]
        let args = l[1:] + ['-n']
    else
        let exe = '/bin/sh'
        let args = ['-n']
    endif

    " NOTE: the format without "line" is used by dash.
    return {
        \ 'exe': exe,
        \ 'args': args,
        \ 'errorformat':
            \ '%f: line %l: %m,' .
            \ '%f: %l: %m'
        \}
endfunction
