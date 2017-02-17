" vim: ts=4 sw=4 et

function! neomake#makers#ft#php#EnabledMakers() abort
    return ['php', 'phpmd', 'phpcs']
endfunction

function! neomake#makers#ft#php#php() abort
    return {
        \ 'args': ['-l', '-d', 'display_errors=1', '-d', 'log_errors=0',
            \      '-d', 'xdebug.cli_color=0'],
        \ 'errorformat':
            \ '%-GNo syntax errors detected in%.%#,'.
            \ 'Parse error: %#syntax %trror\, %m in %f on line %l,'.
            \ 'Parse %trror: %m in %f on line %l,'.
            \ 'Fatal %trror: %m in %f on line %l,'.
            \ '%-G\s%#,'.
            \ '%-GErrors parsing %.%#',
        \ 'postprocess': function('neomake#makers#ft#php#PhpEntryProcess'),
        \ }
endfunction

function! neomake#makers#ft#php#PhpEntryProcess(entry) abort
    "All php lint entries are Errors.
    let a:entry.type = 'E'
endfunction

function! neomake#makers#ft#php#phpcs() abort
    let l:args = ['--report=csv']

    "Add standard argument if one is set.
    if exists('g:neomake_php_phpcs_args_standard')
        call add(l:args, '--standard=' . expand(g:neomake_php_phpcs_args_standard))
    endif

    return {
        \ 'args': args,
        \ 'errorformat':
            \ '%-GFile\,Line\,Column\,Type\,Message\,Source\,Severity%.%#,'.
            \ '"%f"\,%l\,%c\,%t%*[a-zA-Z]\,"%m"\,%*[a-zA-Z0-9_.-]\,%*[0-9]%.%#',
        \ }
endfunction

function! neomake#makers#ft#php#phpmd() abort
    return {
        \ 'args': ['%:p', 'text', 'codesize,design,unusedcode,naming'],
        \ 'errorformat': '%E%f:%l%\s%\s%#%m'
        \ }
endfunction
