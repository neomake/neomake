unlet! s:makers

function! s:MakerAvailable(command) abort
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
    elseif executable(a:command) " stack isn't available, so check for the maker binary directly
        return 1
    else
        return 0
    endif
endfunction

function! neomake#makers#ft#haskell#EnabledMakers() abort
    " cache whether each maker is available, to avoid lots of (UI blocking) system calls...the user must restart vim if a maker's availability changes
    if !exists('s:makers')
        let commands = ['ghc-mod', 'hdevtools', 'hlint', 'liquid']
        let s:makers = []
        for command in commands
            if s:MakerAvailable(command)
                call add(s:makers, substitute(command, '-', '', 'g'))
            endif
        endfor
    endif
    return s:makers
endfunction

function! s:TryStack(maker) abort
    if executable('stack')
        if !has_key(a:maker, 'stackexecargs')
            let a:maker['stackexecargs'] = []
        endif
        let a:maker['args'] = ['--verbosity', 'silent', 'exec'] + a:maker['stackexecargs'] + ['--'] + [a:maker['exe']] + a:maker['args']
        let a:maker['exe'] = 'stack'
    endif
    return a:maker
endfunction

function! neomake#makers#ft#haskell#hdevtools() abort
    let mapexpr = 'substitute(substitute(v:val, " \\{2,\\}", " ", "g"), "`", "''", "g")'
    return s:TryStack({
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

function! neomake#makers#ft#haskell#ghcmod() abort
    " This filters out newlines, which is what neovim gives us instead of the
    " null bytes that ghc-mod sometimes spits out.
    let mapexpr = 'substitute(v:val, "\n", "", "g")'
    return s:TryStack({
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

function! neomake#makers#ft#haskell#HlintEntryProcess(entry) abort
    " Postprocess hlint output to make it more readable as a single line
    let a:entry.text = substitute(a:entry.text, '\v(Found:)\s*\n', ' | \1', 'g')
    let a:entry.text = substitute(a:entry.text, '\v(Why not:)\s*\n', ' | \1', 'g')
    call neomake#utils#CompressWhitespace(a:entry)
endfunction

function! neomake#makers#ft#haskell#hlint() abort
    return s:TryStack({
        \ 'exe': 'hlint',
        \ 'postprocess': function('neomake#makers#ft#haskell#HlintEntryProcess'),
        \ 'args': [],
        \ 'errorformat':
            \ '%E%f:%l:%v: Error: %m,' .
            \ '%W%f:%l:%v: Warning: %m,' .
            \ '%I%f:%l:%v: Suggestion: %m,' .
            \ '%C%m'
        \ })
endfunction

function! neomake#makers#ft#haskell#liquid() abort
    let mapexpr = 'substitute(substitute(v:val, " \\{2,\\}", " ", "g"), "`", "''", "g")'
    return s:TryStack({
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
