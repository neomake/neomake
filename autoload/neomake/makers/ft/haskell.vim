
function! neomake#makers#ft#haskell#MakerAvailable(command)
    " stack may be able to find a maker binary that's not on the normal path
    " so check for that first
    if executable('stack')
        " run the maker command using stack to see whether stack can find it
        " use the help flag to run the maker command without doing anything
        if system('stack exec -- ' . a:command . ' --help > /dev/null 2>&1; echo $?') == 0
            return 1
        else " if stack cannot find the maker command, its not available anywhere
            return 0
        endif
    elseif executable(a:command) " stack isn't available, so check for the binary directly
        return 1
    else
        return 0
    endif
endfunction

function! neomake#makers#ft#haskell#EnabledMakers()
    let commands = ['ghc-mod', 'hdevtools', 'hlint', 'liquid']
    let makers = []
    for command in commands
        if neomake#makers#ft#haskell#MakerAvailable(command)
            call add(makers, substitute(command, "-", "", "g"))
        endif
    endfor
    return makers
endfunction

function! neomake#makers#ft#haskell#TryStack(maker)
    if executable('stack')
        if !has_key(a:maker, 'stackexecargs')
            let a:maker['stackexecargs'] = []
        endif
        let a:maker['args'] = ['--verbosity', 'silent', 'exec'] + a:maker['stackexecargs'] + ['--'] + [a:maker['exe']] + a:maker['args']
        let a:maker['exe'] = 'stack'
    endif
    return a:maker
endfunction

function! neomake#makers#ft#haskell#hdevtools()
    let mapexpr = 'substitute(substitute(v:val, " \\{2,\\}", " ", "g"), "`", "''", "g")'
    return neomake#makers#ft#haskell#TryStack({
        \ 'exe': 'hdevtools',
        \ 'args': ['check', '-g-Wall'],
        \ 'stackexecargs': ['--no-ghc-package-path'],
        \ 'mapexpr': mapexpr,
        \ 'errorformat':
            \ '%-Z %#,'.
            \ '%W%f:%l:%v: Warning: %m,'.
            \ '%W%f:%l:%v: Warning:,'.
            \ '%E%f:%l:%v: %m,'.
            \ '%E%>%f:%l:%v:,'.
            \ '%+C  %#%m,'.
            \ '%W%>%f:%l:%v:,'.
            \ '%+C  %#%tarning: %m,'
        \ })
endfunction

function! neomake#makers#ft#haskell#ghcmod()
    " This filters out newlines, which is what neovim gives us instead of the
    " null bytes that ghc-mod sometimes spits out.
    let mapexpr = 'substitute(v:val, "\n", "", "g")'
    return neomake#makers#ft#haskell#TryStack({
        \ 'exe': 'ghc-mod',
        \ 'args': ['check'],
        \ 'mapexpr': mapexpr,
        \ 'errorformat':
            \ '%-G%\s%#,' .
            \ '%f:%l:%c:%trror: %m,' .
            \ '%f:%l:%c:%tarning: %m,'.
            \ '%f:%l:%c: %trror: %m,' .
            \ '%f:%l:%c: %tarning: %m,' .
            \ '%E%f:%l:%c:%m,' .
            \ '%E%f:%l:%c:,' .
            \ '%Z%m'
        \ })
endfunction

function! neomake#makers#ft#haskell#hlint()
    return neomake#makers#ft#haskell#TryStack({
        \ 'exe': 'hlint',
        \ 'args': [],
        \ 'errorformat':
            \ '%E%f:%l:%v: Error: %m,' .
            \ '%W%f:%l:%v: Warning: %m,' .
            \ '%I%f:%l:%v: Suggestion: %m,' .
            \ '%C%m'
        \ })
endfunction

function! neomake#makers#ft#haskell#liquid()
    let mapexpr = 'substitute(substitute(v:val, " \\{2,\\}", " ", "g"), "`", "''", "g")'
    return neomake#makers#ft#haskell#TryStack({
      \ 'exe': 'liquid',
      \ 'args': [],
      \ 'mapexpr': mapexpr,
      \ 'errorformat':
          \ '%E %f:%l:%c-%.%#Error: %m,' .
          \ '%C%.%#|%.%#,' .
          \ '%C %#^%#,' .
          \ '%C%m,'
      \ })
endfunction
