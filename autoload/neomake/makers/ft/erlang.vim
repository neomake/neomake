
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
        \ 'args': function('neomake#makers#ft#erlang#glob_paths'),
        \ 'errorformat':
            \ '%W%f:%l: Warning: %m,' .
            \ '%E%f:%l: %m'
        \ }
endfunction

function! neomake#makers#ft#erlang#glob_paths() abort
    " Pick the rebar3 profile to use.
    if match(expand('%'), 'SUITE.erl$') > -1
        let profile = 'test'
    else
        let profile = 'default'
    endif
    " Find project root directory.
    let root = fnamemodify(neomake#utils#FindGlobFile('rebar.config'), ':h')
    let ebins = glob(root . '/_build/' . profile . '/lib/*/ebin', '', 1)
    " Set g:erlang_extra_deps in a project-local .vimrc, e.g.:
    "   let g:erlang_extra_deps = ['deps.local']
    if exists('g:erlang_extra_deps')
        for extra_deps in g:erlang_extra_deps
            let ebins += glob(extra_deps . '/*/ebin', '', 1)
        endfor
    endif
    let args = ['-pa', 'ebin', '-I', 'include', '-I', 'src']
    for ebin in ebins
        let args += [ '-pa', ebin,
                    \ '-I', substitute(ebin, 'ebin$', 'include', '') ]
    endfor
    let build_dir = root . '/_build'
    " If <project-root>/_build doesn't exist we'll clutter CWD with .beam files,
    " the same way erlc does by default.
    if isdirectory(build_dir)
        let target_dir = build_dir . '/neomake'
        call mkdir(target_dir)
        let args += ['-o', target_dir]
    endif
    return args
endfunction
