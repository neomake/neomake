" vim: ts=4 sw=4 et

function! neomake#makers#ft#cpp#EnabledMakers() abort
    let makers = executable('clang++') ? ['clang', 'clangtidy', 'clangcheck'] : ['gcc']
    call add(makers, 'cppcheck')
    return makers
endfunction

function! neomake#makers#ft#cpp#clang() abort
    let maker = neomake#makers#ft#c#clang()
    let maker.exe = 'clang++'
    let maker.args += ['-std=c++1z']
    " as a single-file maker, include the current directory in the default
    " search path
    let maker.args += ['-I./']
    return maker
endfunction

function! neomake#makers#ft#cpp#gcc() abort
    let maker = neomake#makers#ft#c#gcc()
    let maker.exe = 'g++'
    let maker.args += ['-std=c++1z']
    " as a single-file maker, include the current directory in the default
    " search path
    let maker.args += ['-I./']
    return maker
endfunction

function! neomake#makers#ft#cpp#clangtidy() abort
    let maker = neomake#makers#ft#c#clangtidy()
    " clang-tidy invokes clang, and that needs to be configured
    " clang arguments are passed to clang-tidy after a literal "--"
    let maker.args += ['--']
    let maker.args += neomake#makers#ft#cpp#clang().args
    return maker
endfunction

function! neomake#makers#ft#cpp#clangcheck() abort
    let maker = neomake#makers#ft#c#clangcheck()
    " clang-check invokes clang, and that needs to be configured
    " clang arguments are passed to clang-check after a literal "--"
    let maker.args += ['--']
    let maker.args += neomake#makers#ft#cpp#clang().args
    return maker
endfunction

function! neomake#makers#ft#cpp#cppcheck() abort
    return {
        \ 'args': '--quiet --language=c++ --enable=warning',
        \ 'errorformat':
            \ '[%f:%l]: (%trror) %m,' .
            \ '[%f:%l]: (%tarning) %m',
        \ }
endfunction

function! neomake#makers#ft#cpp#cpplint() abort
    return {
        \ 'exe': executable('cpplint') ? 'cpplint' : 'cpplint.py',
        \ 'args': ['--verbose=3'],
        \ 'errorformat':
        \     '%A%f:%l:  %m [%t],' .
        \     '%-G%.%#',
        \ 'postprocess': function('neomake#makers#ft#cpp#CpplintEntryProcess')
        \ }
endfunction

function! neomake#makers#ft#cpp#CpplintEntryProcess(entry) abort
    let a:entry.type = str2nr(a:entry.type) < 5 ? 'W' : 'E'
endfunction
