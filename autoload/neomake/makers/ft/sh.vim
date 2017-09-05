" vim: ts=4 sw=4 et

function! neomake#makers#ft#sh#EnabledMakers() abort
    return ['sh', 'shellcheck']
endfunction

function! neomake#makers#ft#sh#shellcheck() abort
    let ext = expand('%:e')
    let maker = {
        \ 'args': ['-fgcc'],
        \ 'errorformat':
            \ '%f:%l:%c: %trror: %m [SC%n],' .
            \ '%f:%l:%c: %tarning: %m [SC%n],' .
            \ '%I%f:%l:%c: Note: %m [SC%n]',
        \ 'output_stream': 'stdout',
        \ }

    if match(getline(1), '\v^#!.*<%(sh|dash|bash|ksh)') >= 0
                \ || match(getline(1), '\v^#\s*shellcheck\s+shell\=') >= 0
        " shellcheck reads the shebang by itself
    elseif ext ==# 'ksh'
        let maker.args += ['-s', 'ksh']
    elseif ext ==# 'sh'
        if exists('g:is_sh')
            let maker.args += ['-s', 'sh']
        elseif exists('g:is_posix') || exists('g:is_kornshell')
            let maker.args += ['-s', 'ksh']
        else
            let maker.args += ['-s', 'bash']
        endif
    else
        let maker.args += ['-s', 'bash']
    endif
    return maker
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
            \ '%-G%.%#',
        \ 'output_stream': 'stderr',
        \ }
endfunction

function! neomake#makers#ft#sh#sh() abort
    let shebang = matchstr(getline(1), '^#!\s*\zs.*$')
    if !empty(shebang)
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
            \ '%E%f: line %l: %m,' .
            \ '%E%f: %l: %m',
        \ 'output_stream': 'stderr',
        \}
endfunction

function! neomake#makers#ft#sh#dash() abort
    return {
        \ 'args': ['-n'],
        \ 'errorformat': '%E%f: %l: %m',
        \ 'output_stream': 'stderr',
        \}
endfunction
