function! neomake#makers#ft#swift#EnabledMakers()
    return ['swiftlint']
endfunction

function! neomake#makers#ft#swift#swiftlint()
    return {
        \ 'args': ['lint', '--config', './.swiftlint.yml', '--quiet'],
        \ 'errorformat': '%f:%l:%c: %trror: %m,%f:%l:%c: %tarning: %m,%f:%l: %tarning: %m,%f:%l: %trror: %m',
        \ 'append_file': 0,
        \ }
endfunction
