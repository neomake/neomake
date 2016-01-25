" vim: ts=4 sw=4 et

function! neomake#makers#ft#python#EnabledMakers()
    if exists('s:python_makers')
        return s:python_makers
    endif

    let makers = ['python', 'frosted']

    if neomake#utils#Exists('pylama')
        call add(makers, 'pylama')
    else
        if neomake#utils#Exists('flake8')
            call add(makers, 'flake8')
        else
            call extend(makers, ['pep257', 'pep8', 'pyflakes'])
        endif

        call add(makers, 'pylint')  " Last because it is the slowest
    endif

    let s:python_makers = makers
    return makers
endfunction

function! neomake#makers#ft#python#pylint()
    return {
        \ 'args': [
            \ '-f', 'text',
            \ '--msg-template="{path}:{line}:{column}:{C}: [{symbol}] {msg}"',
            \ '-r', 'n'
        \ ],
        \ 'errorformat':
            \ '%A%f:%l:%c:%t: %m,' .
            \ '%A%f:%l: %m,' .
            \ '%A%f:(%l): %m,' .
            \ '%-Z%p^%.%#,' .
            \ '%-G%.%#',
        \ }
endfunction

function! neomake#makers#ft#python#flake8()
    return {
        \ 'errorformat':
            \ '%E%f:%l: could not compile,%-Z%p^,' .
            \ '%A%f:%l:%c: %t%n %m,' .
            \ '%A%f:%l: %t%n %m,' .
            \ '%-G%.%#',
        \ 'postprocess': function('neomake#makers#ft#python#Flake8EntryProcess')
        \ }
endfunction

function! neomake#makers#ft#python#Flake8EntryProcess(entry)
    if a:entry.type ==# 'F'  " PyFlake errors
        let type = 'E'
    elseif a:entry.type ==# 'E' && a:entry.nr >= 900  " PEP8 runtime errors (E901, E902)
        let type = 'E'
    elseif a:entry.type ==# 'E' || a:entry.type ==# 'W'  " PEP8 errors & warnings
        let type = 'W'
    elseif a:entry.type ==# 'N' || a:entry.type ==# 'D'  " Naming (PEP8) & docstring (PEP257) conventions
        let type = 'W'
    elseif a:entry.type ==# 'C' || a:entry.type ==# 'T'  " McCabe complexity & todo notes
        let type = 'I'
    else
        let type = ''
    endif
    let a:entry.type = type
endfunction

function! neomake#makers#ft#python#pyflakes()
    return {
        \ 'errorformat':
            \ '%E%f:%l: could not compile,' .
            \ '%-Z%p^,'.
            \ '%E%f:%l:%c: %m,' .
            \ '%E%f:%l: %m,' .
            \ '%-G%.%#',
        \ }
endfunction

function! neomake#makers#ft#python#pep8()
    return {
        \ 'errorformat': '%f:%l:%c: %m',
        \ }
endfunction

function! neomake#makers#ft#python#pep257()
    return {
        \ 'errorformat': '%f:%l %m,%m',
        \ }
endfunction

function! neomake#makers#ft#python#pylama()
    return {
        \ 'args': ['--format', 'pep8'],
        \ 'errorformat': '%f:%l:%c: %m',
        \ }
endfunction

function! neomake#makers#ft#python#python()
    return {
        \ 'args': [ '-c',
            \ "from __future__ import print_function\n" .
            \ "from sys import argv, exit\n" .
            \ "if len(argv) != 2:\n" .
            \ "    exit(1)\n" .
            \ "try:\n" .
            \ "    compile(open(argv[1]).read(), argv[1], 'exec', 0, 1)\n" .
            \ "except SyntaxError as err:\n" .
            \ "    print('%s:%s:%s: %s' % (err.filename, err.lineno, err.offset, err.msg))"
        \ ],
        \ 'errorformat': '%E%f:%l:%c: %m',
        \ }
endfunction

function! neomake#makers#ft#python#frosted()
    return {
        \ 'args': [
            \ '-vb'
        \ ],
        \ 'errorformat':
            \ '%f:%l:%c:%m,' .
            \ '%E%f:%l: %m,' .
            \ '%-Z%p^,' .
            \ '%-G%.%#'
        \ }
endfunction
