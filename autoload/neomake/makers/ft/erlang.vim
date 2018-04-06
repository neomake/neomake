
function! neomake#makers#ft#erlang#EnabledMakers() abort
    return ['erlc']
endfunction

function! neomake#makers#ft#erlang#erlc() abort
    return {
        \ 'args': function('neomake#makers#ft#erlang#GlobPaths'),
        \ 'errorformat':
            \ '%W%f:%l: Warning: %m,' .
            \ '%E%f:%l: %m'
        \ }
endfunction

function! neomake#makers#ft#erlang#GlobPaths() abort
    " Find project root directory.
    let rebar_config = neomake#utils#FindGlobFile('rebar.config')
    if !empty(rebar_config)
        let root = fnamemodify(rebar_config, ':h')
    else
        " At least try with CWD
        let root = getcwd()
    endif
    let root = fnamemodify(root, ':p')
    let build_dir = root . '_build'
    let ebins = []
    if isdirectory(build_dir)
        " Pick the rebar3 profile to use
        let profile = 'default'
        if expand('%') =~# '_SUITE.erl$'
            let profile = 'test'
        endif
        let ebins += neomake#makers#ft#erlang#Glob(build_dir . '/' . profile . '/lib/*/ebin')
        let target_dir = build_dir . '/neomake'
    else
        let target_dir = tempname()
    endif
    " If <root>/_build doesn't exist it might be a rebar2/erlang.mk project
    if isdirectory(root . 'deps')
        let ebins += neomake#makers#ft#erlang#Glob(root . 'deps/*/ebin')
    endif
    " Set g:neomake_erlang_erlc_extra_deps in a project-local .vimrc, e.g.:
    "   let g:neomake_erlang_erlc_extra_deps = ['deps.local']
    " Or just b:neomake_erlang_erlc_extra_deps in a specific buffer.
    let extra_deps_dirs = get(b:, 'neomake_erlang_erlc_extra_deps',
                        \ get(g:, 'neomake_erlang_erlc_extra_deps'))
    if !empty(extra_deps_dirs)
        for extra_deps in extra_deps_dirs
            if extra_deps[-1] !=# '/'
                let extra_deps .= '/'
            endif
            let ebins += neomake#makers#ft#erlang#Glob(extra_deps . '*/ebin')
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

function! neomake#makers#ft#erlang#Glob(expr) abort
    if v:version <= 703
        return split(glob(a:expr))
    endif
    return glob(a:expr, '', 1)
endfunction
