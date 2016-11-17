" vim: ts=4 sw=4 et

function! neomake#makers#ft#sh#EnabledMakers() abort
    return ['sh', 'shellcheck']
endfunction

function! neomake#makers#ft#sh#shellcheck() abort
    let ext = expand('%:e')
    let shebang = getline(1)

    if ext ==# 'dash' || shebang =~# '\<dash\>'
        let ft = 'dash'
    elseif exists('g:is_sh') || ext ==# 'sh' || shebang =~# '\<sh\>'
        let ft = 'sh'
    elseif exists('g:is_kornshell') || exists('g:is_posix') || ext ==# 'ksh'
        \ || shebang =~# '\<ksh\>'
        let ft = 'ksh'
    else
        let ft = 'bash'
    endif

    return {
        \ 'args': ['-fgcc', '-s', ft],
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
