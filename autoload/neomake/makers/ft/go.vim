" vim: ts=4 sw=4 et

function! neomake#makers#ft#go#EnabledMakers() abort
    return ['go', 'golint', 'govet']
endfunction

" The mapexprs in these are needed because cwd will make the command print out
" the wrong path (it will just be ./%:h in the output), so the mapexpr turns
" that back into the relative path

function! neomake#makers#ft#go#go() abort
    return {
        \ 'args': [
            \ 'test', '-c',
            \ '-o', neomake#utils#DevNull(),
        \ ],
        \ 'append_file': 0,
        \ 'cwd': '%:h',
        \ 'mapexpr': 'neomake_bufdir . "/" . v:val',
        \ 'errorformat':
            \ '%W%f:%l: warning: %m,' .
            \ '%E%f:%l:%c:%m,' .
            \ '%E%f:%l:%m,' .
            \ '%C%\s%\+%m,' .
            \ '%-G#%.%#'
        \ }
endfunction

function! neomake#makers#ft#go#golint() abort
    return {
        \ 'errorformat':
            \ '%W%f:%l:%c: %m,' .
            \ '%-G%.%#'
        \ }
endfunction

function! neomake#makers#ft#go#govet() abort
    return {
        \ 'exe': 'go',
        \ 'args': ['vet'],
        \ 'append_file': 0,
        \ 'cwd': '%:h',
        \ 'mapexpr': 'neomake_bufdir . "/" . v:val',
        \ 'errorformat':
            \ '%Evet: %.%\+: %f:%l:%c: %m,' .
            \ '%W%f:%l: %m,' .
            \ '%-G%.%#'
        \ }
endfunction

" This comes straight out of vim-go.
function! neomake#makers#ft#go#Paths() abort
    let dirs = []

    if !exists('s:goroot')
        if executable('go')
            let s:goroot = substitute(system('go env GOROOT'), '\n', '', 'g')
        else
            let s:goroot = $GOROOT
        endif
    endif

    if len(s:goroot) != 0 && isdirectory(s:goroot)
        let dirs += [s:goroot]
    endif

    let workspaces = split($GOPATH, neomake#utils#path_sep())
    if workspaces != []
        let dirs += workspaces
    endif

    return dirs
endfunction

" This comes straight out of vim-go.
function! neomake#makers#ft#go#ImportPath(arg) abort
    let path = fnamemodify(resolve(a:arg), ':p')
    let dirs = neomake#makers#ft#go#Paths()

    let workspace = ''
    for dir in dirs
        if len(dir) && match(path, dir) == 0
            let workspace = dir
        endif
    endfor

    if empty(workspace)
        return -1
    endif

    let srcdir = substitute(workspace . '/src/', '//', '/', '')
    return substitute(path, srcdir, '', '')
endfunction

function! neomake#makers#ft#go#errcheck() abort
    let path = neomake#makers#ft#go#ImportPath(expand('%:p:h'))
    return {
        \ 'args': ['-abspath', path],
        \ 'append_file': 0,
        \ 'errorformat': '%E%f:%l:%c:\ %m, %f:%l:%c\ %#%m'
        \ }
endfunction
