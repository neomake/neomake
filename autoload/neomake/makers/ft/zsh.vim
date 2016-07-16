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
            \ '%I%f:%l:%c: Note: %m',
        \ 'postprocess':
            \ function('neomake#makers#ft#zsh#ShellcheckEntryProcess')
        \ }
endfunction

function! neomake#makers#ft#zsh#zsh() abort
    let shebang = matchstr(getline(1), '^#!\s*\zs.*$')
    if len(shebang)
        let l = split(shebang)
        let exe = l[0]
        let args = l[1:] + ['-n']
    else
        let exe = '/usr/bin/zsh'
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
