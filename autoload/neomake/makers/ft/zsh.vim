" vim: ts=4 sw=4 et

function! neomake#makers#ft#zsh#EnabledMakers()
    return ['zsh', 'shellcheck']
endfunction

function! neomake#makers#ft#zsh#shellcheck()
    return {
        \ 'args': ['-fgcc', '--shell', 'zsh'],
        \ 'errorformat':
            \ '%f:%l:%c: %trror: %m,' .
            \ '%f:%l:%c: %tarning: %m,' .
            \ '%f:%l:%c: %tote: %m',
        \ 'postprocess':
            \ function('neomake#makers#ft#zsh#ShellcheckEntryProcess')
        \ }
endfunction

function! neomake#makers#ft#zsh#ShellcheckEntryProcess(entry)
    if a:entry.type ==? 'N'
        let a:entry.type = 'W'
    endif
    return a:entry
endfunction

function! neomake#makers#ft#zsh#zsh()
    return {
        \ 'args': ['-n'],
        \ 'errorformat': '%f: line %l: %m'
        \}
endfunction
