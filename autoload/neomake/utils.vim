" vim: ts=4 sw=4 et
scriptencoding utf-8

function! neomake#utils#DebugMessage(msg)
    if get(g:, 'neomake_verbose')
        echom a:msg
    endif
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
    let msg = join(map(chunks[:-2], 'v:val . repeat(" ", &tabstop - s:_width(v:val) % &tabstop)'), '') . chunks[-1]
    let msg = strpart(msg, 0, &columns - 1)

    set noruler noshowcmd
    redraw

    echo msg

    let &ruler = old_ruler
    let &showcmd = old_showcmd
endfunction " }}}2

" This comes straight out of syntastic.
function! neomake#utils#IsRunningWindows()
    return has('win16') || has('win32') || has('win64')
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

function! neomake#utils#RemoveFile(f) abort
    if neomake#utils#IsRunningWindows()
        let cmd = 'del'
    else
        let cmd = 'rm'
    endif
    call system(cmd.' '.shellescape(a:f))
    return !v:shell_error
endfunction

let s:available_makers = {}
function neomake#utils#MakerIsAvailable(ft, maker_name) abort
    if a:maker_name ==# 'makeprg'
        " makeprg refers to the actual makeprg, which we don't need to check
        " for our purposes
        return 1
    endif
    if !has_key(s:available_makers, a:maker_name)
        let maker = neomake#GetMaker(a:maker_name, '', a:ft)
        let s:available_makers[a:maker_name] = neomake#utils#Exists(maker.exe)
    endif
    return s:available_makers[a:maker_name]
endfunction

function! neomake#utils#AvailableMakers(ft, makers) abort
    return filter(copy(a:makers), 'neomake#utils#MakerIsAvailable(a:ft, v:val)')
endfunction

" This line intentionally ends with a space
sign define neomake_invisible text=\ 

function! neomake#utils#RedefineSign(name, opts)
    let signs = neomake#GetSigns({'name': a:name})
    for lnum in keys(signs.by_line)
        for sign in signs.by_line[lnum]
            exe 'sign place '.sign.id.' name=neomake_invisible file='.sign.file
        endfor
    endfor

    let sign_define = 'sign define '.a:name
    for attr in keys(a:opts)
        let sign_define .= ' '.attr.'='.a:opts[attr]
    endfor
    exe sign_define

    for lnum in keys(signs.by_line)
        for sign in signs.by_line[lnum]
            exe 'sign place '.sign.id.' name='.a:name.' file='.sign.file
        endfor
    endfor
endfunction

function! neomake#utils#RedefineErrorSign(...)
    let default_opts = {'text': '✖'}
    let opts = {}
    if a:0
        call extend(opts, a:1)
    elseif exists('g:neomake_error_sign')
        call extend(opts, g:neomake_error_sign)
    endif
    call extend(opts, default_opts, 'keep')
    call neomake#utils#RedefineSign('neomake_err', opts)
endfunction

function! neomake#utils#RedefineWarningSign(...)
    let default_opts = {'text': '⚠'}
    let opts = {}
    if a:0
        call extend(opts, a:1)
    elseif exists('g:neomake_warning_sign')
        call extend(opts, g:neomake_warning_sign)
    endif
    call extend(opts, default_opts, 'keep')
    call neomake#utils#RedefineSign('neomake_warn', opts)
endfunction
