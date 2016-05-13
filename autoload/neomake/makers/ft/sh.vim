" vim: ts=4 sw=4 et

function! neomake#makers#ft#sh#EnabledMakers()
    return ['sh', 'shellcheck']
endfunction

function! neomake#makers#ft#sh#shellcheck()
    return {
        \ 'args': ['-fgcc'],
        \ 'errorformat':
            \ '%f:%l:%c: %trror: %m,' .
            \ '%f:%l:%c: %tarning: %m,' .
            \ '%f:%l:%c: %tote: %m',
        \ 'postprocess':
            \ function('neomake#makers#ft#sh#ShellcheckEntryProcess')
        \ }
endfunction

function! neomake#makers#ft#sh#ShellcheckEntryProcess(entry)
    if a:entry.type ==? 'N'
        let a:entry.type = 'W'
    endif
    return a:entry
endfunction

function! neomake#makers#ft#sh#checkbashisms()
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

function! neomake#makers#ft#sh#sh()
    let l:sh = '/bin/sh'
    let l:line = getline(1)
    if l:line =~# '^#!'
        let l:sh = matchstr(l:line, '^#!\zs\S*\ze')
    endif

    return {
        \ 'exe': l:sh,
        \ 'args': ['-n'],
        \ 'errorformat': '%f: line %l: %m'
        \}
endfunction
