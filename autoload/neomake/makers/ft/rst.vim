" vim: ts=4 sw=4 et

function! neomake#makers#ft#rst#SupersetOf() abort
    return 'text'
endfunction

function! neomake#makers#ft#rst#EnabledMakers() abort
    if executable('sphinx-build')
                \ && !empty(neomake#utils#FindGlobFile('conf.py'))
        return ['sphinx']
    endif
    return ['rstlint', 'rstcheck']
endfunction

function! neomake#makers#ft#rst#rstlint() abort
    return {
        \ 'exe': 'rst-lint',
        \ 'errorformat':
            \ '%EERROR %f:%l %m,'.
            \ '%WWARNING %f:%l %m,'.
            \ '%IINFO %f:%l %m,'.
            \ '%C%m',
        \ }
endfunction

function! neomake#makers#ft#rst#rstcheck() abort
    return {
        \ 'errorformat':
            \ '%I%f:%l: (INFO/1) %m,'.
            \ '%W%f:%l: (WARNING/2) %m,'.
            \ '%E%f:%l: (ERROR/3) %m,'.
            \ '%E%f:%l: (SEVERE/4) %m',
        \ }
endfunction

function! neomake#makers#ft#rst#sphinx() abort
    " TODO:
    "  - project mode (after cleanup branch)
    if !exists('s:sphinx_cache')
        let s:sphinx_cache = tempname()
    endif
    let conf = neomake#utils#FindGlobFile('conf.py')
    if empty(conf)
        throw 'Neomake: sphinx: could not find conf.py'
    endif
    let srcdir = fnamemodify(conf, ':h')
    " NOTE: uses '%Z%m,%-G%.%#' instead of '%C%m,%-G' to include next line in
    "       multiline errors (fixed in 7.4.203).
    return {
        \ 'exe': 'sphinx-build',
        \ 'args': ['-n', '-E', '-q', '-N', '-b', 'dummy', srcdir, s:sphinx_cache],
        \ 'append_file': 0,
        \ 'errorformat':
            \ '%f:%l: %tARNING: %m,' .
            \ '%EWARNING: %f:%l: (SEVER%t/4) %m,' .
            \ '%EWARNING: %f:%l: (%tRROR/3) %m,' .
            \ '%EWARNING: %f:%l: (%tARNING/2) %m,' .
            \ '%Z%m,' .
            \ '%-G%.%#',
        \ 'output_stream': 'stderr',
        \ }
endfunction
