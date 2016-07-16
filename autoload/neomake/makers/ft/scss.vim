" vim: ts=4 sw=4 et

function! neomake#makers#ft#scss#EnabledMakers()
    " Only enable first one found
    for m in ['sass-lint', 'scss-lint']
        if executable(m)
            " Return without dash since maker names have no dash
            return [substitute(m, '-', '', 'g')]
        endif
    endfor
    return []
endfunction

function! neomake#makers#ft#scss#scsslint()
    return {
        \ 'exe': 'scss-lint',
        \ 'errorformat': '%f:%l [%t] %m'
        \ }
endfunction

function! neomake#makers#ft#scss#sasslint()
    return {
        \ 'exe': 'sass-lint',
        \ 'args': ['--no-exit', '--verbose', '--format=compact'],
        \ 'errorformat':
            \ '%E%f: line %l\, col %c\, Error - %m,' .
            \ '%W%f: line %l\, col %c\, Warning - %m',
        \ }
endfunction

