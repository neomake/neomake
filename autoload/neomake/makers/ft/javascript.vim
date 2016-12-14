" vim: ts=4 sw=4 et

function! neomake#makers#ft#javascript#EnabledMakers() abort
    return ['eslint', 'jscs', 'jshint', 'ternlint']
endfunction

" ============================================================================
" Makers sorted alphabetically
" ============================================================================

function! neomake#makers#ft#javascript#eslint() abort
    return {
        \ 'args': ['-f', 'compact'],
        \ 'errorformat': '%E%f: line %l\, col %c\, Error - %m,' .
        \ '%W%f: line %l\, col %c\, Warning - %m'
        \ }
endfunction

function! neomake#makers#ft#javascript#eslint_d() abort
    return {
        \ 'args': ['-f', 'compact'],
        \ 'errorformat': '%E%f: line %l\, col %c\, Error - %m,' .
        \ '%W%f: line %l\, col %c\, Warning - %m'
        \ }
endfunction

function! neomake#makers#ft#javascript#flow() abort
    " Replace "\n" by space.
    let mapexpr = 'substitute(v:val, "\\\\n", " ", "g")'
    return {
        \ 'args': ['--old-output-format'],
        \ 'errorformat': '%E%f:%l:%c\,%n: %m',
        \ 'mapexpr': mapexpr,
        \ }
endfunction

function! neomake#makers#ft#javascript#jshint() abort
    return {
        \ 'args': ['--verbose'],
        \ 'errorformat': '%A%f: line %l\, col %v\, %m \(%t%*\d\)',
        \ }
endfunction

function! neomake#makers#ft#javascript#jscs() abort
    return {
        \ 'args': ['--no-colors', '--reporter', 'inline'],
        \ 'errorformat': '%E%f: line %l\, col %c\, %m',
        \ }
endfunction

function! neomake#makers#ft#javascript#standard() abort
    return {
        \ 'errorformat': '%W  %f:%l:%c: %m'
        \ }
endfunction

function! neomake#makers#ft#javascript#semistandard()
    return {
        \ 'errorformat': '%W  %f:%l:%c: %m'
        \ }
endfunction

" Requires tern-lint npm module >= 1.0.0
" so `npm install -g tern-lint`
function! neomake#makers#ft#javascript#ternlint() abort
    let l:tern_pattern = '\([^:]\+:\)\([^:]\+\)\(.*\)'
    let l:tern_replace = '\=submatch(1) . byte2line(submatch(2)) . submatch(3) . " [tern-lint]"'
    let l:tern_mapexpr = 'substitute('
          \.   'v:val, '
          \.   "'" . l:tern_pattern . "', "
          \.   "'" . l:tern_replace . "', "
          \.   "''"
          \. ')'
    return {
        \ 'exe':          'tern-lint',
        \ 'args':         [ '--format=vim' ],
        \ 'mapexpr':      l:tern_mapexpr,
        \ 'errorformat':  '%f:%l: %trror: %m,'
        \               . '%f:%l: %tarning: %m',
        \ }
endfunction

function! neomake#makers#ft#javascript#xo() abort
    return {
        \ 'args': ['--compact'],
        \ 'errorformat': '%E%f: line %l\, col %c\, Error - %m,' .
        \ '%W%f: line %l\, col %c\, Warning - %m',
        \ }
endfunction
