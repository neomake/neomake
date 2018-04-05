
function! neomake#makers#ft#erlang#EnabledMakers() abort
    return ['erlc_glob_paths']
endfunction

function! neomake#makers#ft#erlang#erlc() abort
    return {
        \ 'errorformat':
            \ '%W%f:%l: Warning: %m,' .
            \ '%E%f:%l: %m'
        \ }
endfunction

function! neomake#makers#ft#erlang#erlc_glob_paths() abort
    return {
        \ 'exe': 'erlc',
        \ 'args': function("neomake#makers#ft#erlang#glob_paths"),
        \ 'errorformat':
            \ '%W%f:%l: Warning: %m,' .
            \ '%E%f:%l: %m'
        \ }
endfunction

function! neomake#makers#ft#erlang#glob_paths() abort
    if match(expand('%'), "SUITE.erl$") > -1
        let l:profile = "test"
    else
        let l:profile = "default"
    endif
    let l:ebins = glob("_build/" . l:profile . "/lib/*/ebin", "", 1)
    " Set g:erlang_extra_deps in a project-local .vimrc, e.g.:
    "   let g:erlang_extra_deps = ['deps.local']
    if exists("g:erlang_extra_deps")
        for extra_deps in g:erlang_extra_deps
            let l:ebins += glob(extra_deps . "/*/ebin", "", 1)
        endfor
    endif
    let l:args = ['-I', 'include', '-I', 'src']
    for ebin in ebins
        call add(l:args, '-pa')
        call add(l:args, ebin)
        call add(l:args, '-I')
        call add(l:args, substitute(ebin, "ebin$", "include", ""))
    endfor
    call add(l:args, '-o')
    call add(l:args, '_build/neomake')
    return l:args
endfunction
