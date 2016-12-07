" vim: ts=4 sw=4 et

function! neomake#makers#ft#python#EnabledMakers() abort
    if exists('s:python_makers')
        return s:python_makers
    endif

    let makers = ['python', 'frosted']

    if executable('pylama')
        call add(makers, 'pylama')
    else
        if executable('flake8')
            call add(makers, 'flake8')
        else
            call extend(makers, ['pyflakes', 'pep8', 'pydocstyle'])
        endif

        call add(makers, 'pylint')  " Last because it is the slowest
    endif

    let s:python_makers = makers
    return makers
endfunction

function! neomake#makers#ft#python#pylint() abort
    return {
        \ 'args': [
            \ '--output-format=text',
            \ '--msg-template="{path}:{line}:{column}:{C}: [{symbol}] {msg}"',
            \ '--reports=no'
        \ ],
        \ 'errorformat':
            \ '%A%f:%l:%c:%t: %m,' .
            \ '%A%f:%l: %m,' .
            \ '%A%f:(%l): %m,' .
            \ '%-Z%p^%.%#,' .
            \ '%-G%.%#',
        \ 'postprocess': function('neomake#makers#ft#python#PylintEntryProcess')
        \ }
endfunction

function! neomake#makers#ft#python#PylintEntryProcess(entry) abort
    if a:entry.type ==# 'F'  " Fatal error which prevented further processing
        let type = 'E'
    elseif a:entry.type ==# 'E'  " Error for important programming issues
        let type = 'E'
    elseif a:entry.type ==# 'W'  " Warning for stylistic or minor programming issues
        let type = 'W'
    elseif a:entry.type ==# 'R'  " Refactor suggestion
        let type = 'W'
    elseif a:entry.type ==# 'C'  " Convention violation
        let type = 'W'
    elseif a:entry.type ==# 'I'  " Informations
        let type = 'I'
    else
        let type = ''
    endif
    let a:entry.type = type
endfunction

function! neomake#makers#ft#python#flake8() abort
    return {
        \ 'args': ['--format=default'],
        \ 'errorformat':
            \ '%E%f:%l: could not compile,%-Z%p^,' .
            \ '%A%f:%l:%c: %t%n %m,' .
            \ '%A%f:%l: %t%n %m,' .
            \ '%-G%.%#',
        \ 'postprocess': function('neomake#makers#ft#python#Flake8EntryProcess')
        \ }
endfunction

function! neomake#makers#ft#python#Flake8EntryProcess(entry) abort
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
    let l:token = matchstr(a:entry.text, "'.*'")
    if strlen(l:token)
        let a:entry.length = strlen(l:token) - 2 " subtract the quotes
    endif

    let a:entry.text = a:entry.type . a:entry.nr . ' ' . a:entry.text
    let a:entry.type = type
    let a:entry.nr = ''  " Avoid redundancy in the displayed error message.
endfunction

function! neomake#makers#ft#python#pyflakes() abort
    return {
        \ 'errorformat':
            \ '%E%f:%l: could not compile,' .
            \ '%-Z%p^,'.
            \ '%E%f:%l:%c: %m,' .
            \ '%E%f:%l: %m,' .
            \ '%-G%.%#',
        \ }
endfunction

function! neomake#makers#ft#python#pep8() abort
    return {
        \ 'errorformat': '%f:%l:%c: %m',
        \ 'postprocess': function('neomake#makers#ft#python#Pep8EntryProcess')
        \ }
endfunction

function! neomake#makers#ft#python#Pep8EntryProcess(entry) abort
    if a:entry.text =~# '^E9'  " PEP8 runtime errors (E901, E902)
        let a:entry.type = 'E'
    elseif a:entry.text =~# '^E113'  " unexpected indentation (IndentationError)
        let a:entry.type = 'E'
    else  " Everything else is a warning
        let a:entry.type = 'W'
    endif
endfunction

function! neomake#makers#ft#python#pydocstyle() abort
  if !exists('s:_pydocstyle_exe')
    " Use the preferred exe to avoid deprecation warnings.
    let s:_pydocstyle_exe = executable('pydocstyle') ? 'pydocstyle' : 'pep257'
  endif
  return {
        \ 'exe': s:_pydocstyle_exe,
        \ 'errorformat':
        \   '%W%f:%l %.%#:,' .
        \   '%+C        %m',
        \ 'postprocess': function('neomake#utils#CompressWhitespace'),
        \ }
endfunction

" Note: pep257 has been renamed to pydocstyle, but is kept also as alias.
function! neomake#makers#ft#python#pep257() abort
    return neomake#makers#ft#python#pydocstyle()
endfunction

function! neomake#makers#ft#python#PylamaEntryProcess(entry) abort
    if a:entry.type ==# 'C' && a:entry.text =~# '\v\[%(pycodestyle|pep8)\]$'
        call neomake#makers#ft#python#Pep8EntryProcess(a:entry)
    elseif a:entry.type ==# 'D'  " pydocstyle/pep257
        let a:entry.type = 'W'
    elseif a:entry.type ==# 'E901'  " mccabe
        let a:entry.type = 'W'
    elseif a:entry.type ==# 'R'  " Radon
        let a:entry.type = 'W'
    endif
endfunction

function! neomake#makers#ft#python#pylama() abort
    return {
        \ 'args': ['--format', 'parsable'],
        \ 'errorformat': '%f:%l:%c: [%t] %m',
        \ 'postprocess': function('neomake#makers#ft#python#PylamaEntryProcess'),
        \ }
endfunction

function! neomake#makers#ft#python#python() abort
    return {
        \ 'args': [ '-c',
            \ "from __future__ import print_function\r" .
            \ "from sys import argv, exit\r" .
            \ "if len(argv) != 2:\r" .
            \ "    exit(64)\r" .
            \ "try:\r" .
            \ "    compile(open(argv[1]).read(), argv[1], 'exec', 0, 1)\r" .
            \ "except SyntaxError as err:\r" .
            \ "    print('%s:%s:%s: %s' % (err.filename, err.lineno, err.offset, err.msg))\r" .
            \ '    exit(1)'
        \ ],
        \ 'errorformat': '%E%f:%l:%c: %m',
        \ }
endfunction

function! neomake#makers#ft#python#frosted() abort
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

function! neomake#makers#ft#python#vulture() abort
    return {
        \ 'errorformat': '%f:%l: %m',
        \ }
endfunction

" Because this uses --silent-imports it requires mypy >= 0.4
" It is annoying for new users to use MyPy without --silent-imports
function! neomake#makers#ft#python#mypy() abort
    return {
        \ 'args': ['--silent-imports'],
        \ 'errorformat':
            \ '%E%f:%l: error: %m,' .
            \ '%W%f:%l: warning: %m,' .
            \ '%I%f:%l: note: %m',
        \ }
endfunction

function! neomake#makers#ft#python#py3kwarn() abort
    return {
        \ 'errorformat': '%W%f:%l:%c: %m',
        \ }
endfunction
