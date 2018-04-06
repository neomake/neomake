
function! neomake#makers#ft#erlang#EnabledMakers() abort
    return ['erlc']
endfunction

function! neomake#makers#ft#erlang#erlc() abort
    return {
        \ 'exe': 'erlc',
        \ 'args': function('neomake#makers#ft#erlang#GlobPaths'),
        \ 'errorformat':
            \ '%W%f:%l: Warning: %m,' .
            \ '%E%f:%l: %m'
        \ }
endfunction

function! neomake#makers#ft#erlang#GlobPaths() abort
    " Find project root directory.
    let root = fnamemodify(neomake#utils#FindGlobFile('rebar.config'), ':h')
    if empty(root)
        " At least try with CWD
        root = getcwd()
    endif
    let build_dir = root . '/_build'
    let ebins = []
    if isdirectory(build_dir)
        " Pick the rebar3 profile to use
        let profile = 'default'
        if expand('%') =~# '_SUITE.erl$'
            let profile = 'test'
        endif
        let ebins += glob(build_dir . '/' . profile . '/lib/*/ebin', '', 1)
        let target_dir = build_dir . '/neomake'
    else
        " If <root>/_build doesn't exist it might be a rebar2/erlang.mk project
        let ebins += glob(root . '/deps/*/ebin', '', 1)
        let target_dir = tempname()
    endif
    " Set g:neomake_erlang_erlc_extra_deps in a project-local .vimrc, e.g.:
    "   let g:neomake_erlang_erlc_extra_deps = ['deps.local']
    " Or just b:neomake_erlang_erlc_extra_deps in a specific buffer.
    let extra_deps_dirs = get(b:, 'neomake_erlang_erlc_extra_deps',
                        \ get(g:, 'neomake_erlang_erlc_extra_deps'))
    if !empty(extra_deps_dirs)
        for extra_deps in extra_deps_dirs
            let ebins += glob(extra_deps . '/*/ebin', '', 1)
        endfor
    endif
    let args = ['-pa', 'ebin', '-I', 'include', '-I', 'src']
    for ebin in ebins
        let args += [ '-pa', ebin,
                    \ '-I', substitute(ebin, 'ebin$', 'include', '') ]
    endfor
    if !isdirectory(target_dir)
        call mkdir(target_dir, 'p')
    endif
    let args += ['-o', target_dir]
    return args
endfunction
