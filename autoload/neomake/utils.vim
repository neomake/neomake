" vim: ts=4 sw=4 et
scriptencoding utf-8

let s:level_to_name = {
            \ 0: 'error',
            \ 1: 'quiet',
            \ 2: 'verb ',
            \ 3: 'debug',
            \ }

if has('reltime')
    let s:reltime_start = reltime()
endif
function! s:timestr() abort
    if exists('s:reltime_start')
        let cur_time = split(split(reltimestr(reltime(s:reltime_start)))[0], '\.')
        return cur_time[0].'.'.cur_time[1][0:2]
    endif
    return strftime('%H:%M:%S')
endfunction

function! neomake#utils#LogMessage(level, msg, ...) abort
    let verbose = get(g:, 'neomake_verbose', 1)
    let logfile = get(g:, 'neomake_logfile')

    if exists(':Log') != 2 && verbose < a:level && logfile is# ''
        return
    endif

    if a:0
        let jobinfo = a:1
        if has_key(jobinfo, 'id')
            let msg = printf('[%d.%d] %s', jobinfo.make_id, jobinfo.id, a:msg)
        else
            let msg = printf('[%d] %s', jobinfo.make_id, a:msg)
        endif
    else
        let jobinfo = {}
        let msg = a:msg
    endif

    if exists('*vader#log')
        " Log is defined during Vader tests.
        let test_msg = '['.s:level_to_name[a:level].'] ['.s:timestr().']: '.msg
        call vader#log(test_msg)
        " Only keep jobinfo entries that are relevant for / used in the message.
        let g:neomake_test_messages += [[a:level, a:msg,
                    \ filter(copy(jobinfo), "index(['id', 'make_id'], v:key) != -1")]]
    endif

    if verbose >= a:level
        redraw
        if a:level ==# 0
            echohl ErrorMsg
        endif
        if verbose > 2
            echom 'Neomake ['.s:timestr().']: '.msg
        else
            echom 'Neomake: '.msg
        endif
        if a:level ==# 0
            echohl None
        endif
    endif
    if type(logfile) ==# type('') && len(logfile)
        let date = strftime('%Y-%m-%dT%H:%M:%S%z')
        call writefile(['['.date.' @'.s:timestr().', '.s:level_to_name[a:level].'] '.msg], logfile, 'a')
    endif
endfunction

function! neomake#utils#ErrorMessage(...) abort
    call call('neomake#utils#LogMessage', [0] + a:000)
endfunction

function! neomake#utils#QuietMessage(...) abort
    call call('neomake#utils#LogMessage', [1] + a:000)
endfunction

function! neomake#utils#LoudMessage(...) abort
    call call('neomake#utils#LogMessage', [2] + a:000)
endfunction

function! neomake#utils#DebugMessage(...) abort
    call call('neomake#utils#LogMessage', [3] + a:000)
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

function! neomake#utils#DebugObject(msg, obj) abort
    call neomake#utils#DebugMessage(a:msg.' '.neomake#utils#Stringify(a:obj))
endfunction

" This comes straight out of syntastic.
"print as much of a:msg as possible without "Press Enter" prompt appearing
function! neomake#utils#WideMessage(msg) abort " {{{2
    let old_ruler = &ruler
    let old_showcmd = &showcmd

    "This is here because it is possible for some error messages to
    "begin with \n which will cause a "press enter" prompt.
    let msg = substitute(a:msg, "\n", '', 'g')

    "convert tabs to spaces so that the tabs count towards the window
    "width as the proper amount of characters
    let chunks = split(msg, "\t", 1)
    let msg = join(map(chunks[:-2], "v:val . repeat(' ', &tabstop - strwidth(v:val) % &tabstop)"), '') . chunks[-1]
    let msg = strpart(msg, 0, &columns - 1)

    set noruler noshowcmd
    redraw

    call neomake#utils#DebugMessage('WideMessage echo '.msg)
    echo msg

    let &ruler = old_ruler
    let &showcmd = old_showcmd
endfunction " }}}2

" This comes straight out of syntastic.
function! neomake#utils#IsRunningWindows() abort
    return has('win32') || has('win64')
endfunction

" This comes straight out of syntastic.
function! neomake#utils#DevNull() abort
    if neomake#utils#IsRunningWindows()
        return 'NUL'
    endif
    return '/dev/null'
endfunction

function! neomake#utils#Exists(exe) abort
    " DEPRECATED: just use executable() directly.
    return executable(a:exe)
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

function! neomake#utils#MakerFromCommand(command) abort
    " XXX: use neomake#utils#ExpandArgs and/or remove it.
    "      Expansion should happen later already!
    let command = substitute(a:command, '%\(:[a-z]\)*',
                           \ '\=expand(submatch(0))', 'g')
    return {
        \ 'exe': &shell,
        \ 'args': [&shellcmdflag, command],
        \ 'remove_invalid_entries': 0,
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
        if empty(maker)
            return 0
        endif
        let s:available_makers[a:maker_name] = executable(maker.exe)
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

" Get a setting by key, based on filetypes, from the buffer or global
" namespace, defaulting to default.
function! neomake#utils#GetSetting(key, maker, default, fts, bufnr) abort
  let maker_name = has_key(a:maker, 'name') ? '_'.a:maker.name : ''
  if len(a:fts)
    for ft in a:fts
      " Look through the neomake setting override vars for a filetype maker,
      " like neomake_scss_sasslint_exe (should be a string), and
      " neomake_scss_sasslint_args (should be a list)
      let config_var = 'neomake_'.ft.maker_name.'_'.a:key
      if has_key(g:, config_var)
            \ || !empty(getbufvar(a:bufnr, config_var))
        break
      endif
    endfor
  elseif len(maker_name)
    " Following this, we're checking the neomake overrides for global makers
    let config_var = 'neomake'.maker_name.'_'.a:key
  endif

  if exists('config_var')
    if !empty(getbufvar(a:bufnr, config_var))
      return copy(getbufvar(a:bufnr, config_var))
    elseif has_key(g:, config_var)
      return copy(get(g:, config_var))
    endif
  endif
  if has_key(a:maker, a:key)
    return a:maker[a:key]
  endif
  " Look for 'neomake_'.key in the buffer and global namespace.
  let bufvar = getbufvar(a:bufnr, 'neomake_'.a:key)
  if !empty(bufvar)
      return bufvar
  endif
  let var = get(g:, 'neomake_'.a:key)
  if !empty(var)
      return var
  endif
  return a:default
endfunction

" Get property from highlighting group.
function! neomake#utils#GetHighlight(group, what) abort
  let reverse = synIDattr(synIDtrans(hlID(a:group)), 'reverse')
  let what = a:what
  if reverse
    let what = neomake#utils#ReverseSynIDattr(what)
  endif
  if what[-1:] ==# '#'
      let val = synIDattr(synIDtrans(hlID(a:group)), what, 'gui')
  else
      let val = synIDattr(synIDtrans(hlID(a:group)), what, 'cterm')
  endif
  if empty(val) || val == -1
    let val = 'NONE'
  endif
  return val
endfunction

function! neomake#utils#ReverseSynIDattr(attr) abort
  if a:attr ==# 'fg'
    return 'bg'
  elseif a:attr ==# 'bg'
    return 'fg'
  elseif a:attr ==# 'fg#'
    return 'bg#'
  elseif a:attr ==# 'bg#'
    return 'fg#'
  endif
  return a:attr
endfunction

function! neomake#utils#CompressWhitespace(entry) abort
    let text = a:entry.text
    let text = substitute(text, "\001", '', 'g')
    let text = substitute(text, '\r\?\n', ' ', 'g')
    let text = substitute(text, '\m\s\{2,}', ' ', 'g')
    let text = substitute(text, '\m^\s\+', '', '')
    let text = substitute(text, '\m\s\+$', '', '')
    let a:entry.text = text
endfunction

function! neomake#utils#redir(cmd) abort
    if exists('*execute') && has('nvim')
        " NOTE: require Neovim, since Vim has at least an issue when using
        "       this in a :command-completion function.
        "       Ref: https://github.com/neomake/neomake/issues/650.
        return execute(a:cmd)
    endif
    if type(a:cmd) == type([])
        let r = ''
        for cmd in a:cmd
            let r .= neomake#utils#redir(cmd)
        endfor
        return r
    endif
    redir => neomake_redir
    try
        silent exe a:cmd
    finally
        redir END
    endtry
    return neomake_redir
endfunction

function! neomake#utils#ExpandArgs(args) abort
    " Only expand those args that start with \ and a single %
    call map(a:args, "v:val =~# '\\(^\\\\\\|^%$\\|^%[^%]\\)' ? expand(v:val) : v:val")
endfunction

function! neomake#utils#hook(event, context) abort
    if exists('#User#'.a:event)
        let g:neomake_hook_context = a:context
        call neomake#utils#DebugMessage('Calling User autocmd '.a:event
                                      \ .' with context: '.string(a:context))
        if v:version >= 704 || (v:version == 703 && has('patch442'))
            exec 'doautocmd <nomodeline> User ' . a:event
        else
            exec 'doautocmd User ' . a:event
        endif
        unlet g:neomake_hook_context
    endif
endfunction
