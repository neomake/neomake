" vim: ts=4 sw=4 et
scriptencoding utf-8

function! neomake#utils#LogMessage(level, msg) abort
    let verbose = get(g:, 'neomake_verbose', 1)
    let logfile = get(g:, 'neomake_logfile')
    let msg ='Neomake: '.a:msg
    if verbose >= a:level
        if a:level ==# 0
            echohl ErrorMsg
        endif
        echom msg
        if a:level ==# 0
            echohl None
        endif
    endif
    if type(logfile) ==# type('') && len(logfile)
        let date = strftime("%Y-%m-%dT%H:%M:%S%z")
        call writefile([date.' Log level '.a:level.': '.msg], logfile, 'a')
    endif
endfunction

function! neomake#utils#ErrorMessage(msg) abort
    call neomake#utils#LogMessage(0, a:msg)
endfunction

function! neomake#utils#QuietMessage(msg) abort
    call neomake#utils#LogMessage(1, a:msg)
endfunction

function! neomake#utils#LoudMessage(msg) abort
    call neomake#utils#LogMessage(2, a:msg)
endfunction

function! neomake#utils#DebugMessage(msg) abort
    call neomake#utils#LogMessage(3, a:msg)
endfunction

function! neomake#utils#Stringify(obj) abort
    if type(a:obj) == type([])
        let ls = map(copy(a:obj), 'neomake#utils#Stringify(v:val)')
        return '['.join(ls, ', ').']'
    elseif type(a:obj) == type({})
        let ls = []
        for key in keys(a:obj)
            call add(ls, key.': '.neomake#utils#Stringify(a:obj[key]))
        endfor
        return '{'.join(ls, ', ').'}'
    else
        return ''.a:obj
    endif
endfunction

function neomake#utils#DebugObject(msg, obj) abort
    call neomake#utils#DebugMessage(a:msg.' '.neomake#utils#Stringify(a:obj))
endfunction

" This comes straight out of syntastic.
"print as much of a:msg as possible without "Press Enter" prompt appearing
function! neomake#utils#WideMessage(msg) " {{{2
    let old_ruler = &ruler
    let old_showcmd = &showcmd

    "This is here because it is possible for some error messages to
    "begin with \n which will cause a "press enter" prompt.
    let msg = substitute(a:msg, "\n", "", "g")

    "convert tabs to spaces so that the tabs count towards the window
    "width as the proper amount of characters
    let chunks = split(msg, "\t", 1)
    let msg = join(map(chunks[:-2], 'v:val . repeat(" ", &tabstop - strwidth(v:val) % &tabstop)'), '') . chunks[-1]
    let msg = strpart(msg, 0, &columns - 1)

    set noruler noshowcmd
    redraw

    call neomake#utils#DebugMessage('WideMessage echo '.msg)
    echo msg

    let &ruler = old_ruler
    let &showcmd = old_showcmd
endfunction " }}}2

" This comes straight out of syntastic.
function! neomake#utils#IsRunningWindows()
    return has('win32') || has('win64')
endfunction

" This comes straight out of syntastic.
function! neomake#utils#DevNull()
    if neomake#utils#IsRunningWindows()
        return 'NUL'
    endif
    return '/dev/null'
endfunction

function! neomake#utils#Exists(exe) abort
    if neomake#utils#IsRunningWindows()
        " TODO: Apparently XP uses a different utility to where, see
        " https://github.com/benekastah/neomake/issues/19#issuecomment-65195452
        let cmd = 'where'
    else
        let cmd = 'which'
    endif
    call system(cmd.' '.shellescape(a:exe))
    return !v:shell_error
endfunction

function! neomake#utils#Random() abort
    call neomake#utils#DebugMessage('Calling neomake#utils#Random')
    if neomake#utils#IsRunningWindows()
        let cmd = 'Echo %RANDOM%'
    else
        let cmd = 'echo $RANDOM'
    endif
    let answer = 0 + system(cmd)
    if v:shell_error
        " If complaints come up about this, consider using python
        throw "Can't generate random number for this platform"
    endif
    return answer
endfunction

function! neomake#utils#MakerFromCommand(shell, command) abort
    let command = substitute(a:command, '%\(:[a-z]\)*',
                           \ '\=expand(submatch(0))', 'g')
    let shell_name = split(a:shell, '/')[-1]
    if index(['sh', 'csh', 'ash', 'bash', 'dash', 'ksh', 'pdksh', 'mksh', 'zsh', 'fish'],
            \shell_name) >= 0
        let args = ['-c', command]
    else
        " TODO Windows support (at least)
        throw "Shell not recognized; can't build command"
    endif
    return {
        \ 'exe': a:shell,
        \ 'args': args
        \ }
endfunction

let s:available_makers = {}
function! neomake#utils#MakerIsAvailable(ft, maker_name) abort
    if a:maker_name ==# 'makeprg'
        " makeprg refers to the actual makeprg, which we don't need to check
        " for our purposes
        return 1
    endif
    if !has_key(s:available_makers, a:maker_name)
        let maker = neomake#GetMaker(a:maker_name, a:ft)
        let s:available_makers[a:maker_name] = neomake#utils#Exists(maker.exe)
    endif
    return s:available_makers[a:maker_name]
endfunction

function! neomake#utils#AvailableMakers(ft, makers) abort
    return filter(copy(a:makers), 'neomake#utils#MakerIsAvailable(a:ft, v:val)')
endfunction

function! neomake#utils#GetSupersetOf(ft) abort
    try
        return eval('neomake#makers#ft#' . a:ft . '#SupersetOf()')
    catch /^Vim\%((\a\+)\)\=:E117/
        return ''
    endtry
endfunction

" Attempt to get list of filetypes in order of most specific to least specific.
function! neomake#utils#GetSortedFiletypes(ft) abort
    function! CompareFiletypes(ft1, ft2) abort
        if neomake#utils#GetSupersetOf(a:ft1) ==# a:ft2
            return -1
        elseif neomake#utils#GetSupersetOf(a:ft2) ==# a:ft1
            return 1
        else
            return 0
        endif
    endfunction

    return sort(split(a:ft, '\.'), function('CompareFiletypes'))
endfunction
