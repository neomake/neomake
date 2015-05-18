" vim: ts=4 sw=4 et

function! neomake#makers#ft#php#EnabledMakers()
    return ['php', 'phpmd', 'phpcs']
endfunction

function! neomake#makers#ft#php#php()
    return {
        \ 'args': ['-l'],
        \ 'errorformat': '%m\ in\ %f\ on\ line\ %l,%-GErrors\ parsing\ %f,%-G',
        \ 'postprocess': function('neomake#makers#ft#php#PhpEntryProcess'),
        \ }
endfunction

function! neomake#makers#ft#php#PhpEntryProcess(entry)
    "All php lint entries are Errors.
    let a:entry.type = 'E'
endfunction

function! neomake#makers#ft#php#phpcs()
    let l:args = ['--report=csv']

    "Add standard argument if one is set.
    if exists("g:neomake_php_phpcs_args_standard")
        call add(l:args, '--standard=' . expand(g:neomake_php_phpcs_args_standard))
    endif

    return {
        \ 'args': args,
        \ 'errorformat':
            \ '%-GFile\,Line\,Column\,Type\,Message\,Source\,Severity%.%#,'.
            \ '"%f"\,%l\,%c\,%t%*[a-zA-Z]\,"%m"\,%*[a-zA-Z0-9_.-]\,%*[0-9]%.%#',
        \ }
endfunction

function! neomake#makers#ft#php#phpmd()

    return {
        \ 'args': ['%:p', 'text', 'codesize,design,unusedcode,naming'],
        \ 'errorformat': '%E%f:%l%\s%m'
        \ }
endfunction
