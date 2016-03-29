" vim: ts=4 sw=4 et

function! neomake#makers#ft#sh#EnabledMakers()
    return ['shellcheck']
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
