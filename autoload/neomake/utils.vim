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

let s:unset = {}

function! neomake#utils#LogMessage(level, msg, ...) abort
    let verbose = get(g:, 'neomake_verbose', 1)
    let logfile = get(g:, 'neomake_logfile')

    if exists(':Log') != 2 && verbose < a:level && logfile is# ''
        return
    endif

    if a:0
        let jobinfo = a:1
        if has_key(jobinfo, 'id')
            let msg = printf('[%s.%d] %s', get(jobinfo, 'make_id', '-'), jobinfo.id, a:msg)
        else
            let msg = printf('[%s] %s', get(jobinfo, 'make_id', '?'), a:msg)
        endif
    else
        let jobinfo = {}
        let msg = a:msg
    endif

    " Use Vader's log for messages during tests.
    if exists('*vader#log') && exists('g:neomake_test_messages')
        let test_msg = '['.s:level_to_name[a:level].'] ['.s:timestr().']: '.msg
        call vader#log(test_msg)
        " Only keep jobinfo entries that are relevant for / used in the message.
        let g:neomake_test_messages += [[a:level, a:msg,
                    \ filter(copy(jobinfo), "index(['id', 'make_id'], v:key) != -1")]]
    elseif verbose >= a:level
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

function! neomake#utils#wstrpart(mb_string, start, len) abort
  return matchstr(a:mb_string, '.\{,'.a:len.'}', 0, a:start+1)
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
    let msg = neomake#utils#wstrpart(msg, 0, &columns - 1)

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

let s:command_maker = {
            \ 'remove_invalid_entries': 0,
            \ }
function! s:command_maker.fn(jobinfo) dict abort
    let maker = filter(copy(self), "v:key !~# '^__' && v:key !~# 'fn'")
    let argv = split(&shell) + split(&shellcmdflag)
    let command = self.__command

    if a:jobinfo.file_mode && get(maker, 'append_file', 1)
        let command .= ' '.fnameescape(fnamemodify(bufname(a:jobinfo.bufnr), ':p'))
        let maker.append_file = 0
    endif
    call extend(maker, {
                \ 'exe': argv[0],
                \ 'args': argv[1:] + [command],
                \ })
    return maker
endfunction

function! neomake#utils#MakerFromCommand(command) abort
    let command = neomake#utils#ExpandArgs([a:command])[0]
    " Create a maker object, with a "fn" callback.
    let maker = copy(s:command_maker)
    let maker.__command = command
    return maker
endfunction

let s:available_makers = {}
function! neomake#utils#MakerIsAvailable(ft, maker_name) abort
    if a:maker_name ==# 'makeprg'
        " makeprg refers to the actual makeprg, which we don't need to check
        " for our purposes
        return 1
    endif
    let maker = neomake#GetMaker(a:maker_name, a:ft)
    if empty(maker)
        return 0
    endif
    if !has_key(s:available_makers, maker.exe)
        let s:available_makers[maker.exe] = executable(maker.exe)
    endif
    return s:available_makers[maker.exe]
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
  let maker_name = has_key(a:maker, 'name') ? a:maker.name : ''
  for ft in a:fts + ['']
    " Look through the override vars for a filetype maker, like
    " neomake_scss_sasslint_exe (should be a string), and
    " neomake_scss_sasslint_args (should be a list).
    let part = join(filter([ft, maker_name], 'len(v:val)'), '_')
    if !len(part)
        break
    endif
    let config_var = 'neomake_'.part.'_'.a:key
    if has_key(g:, config_var)
          \ || neomake#compat#getbufvar(a:bufnr, config_var, s:unset) isnot s:unset
      break
    endif
  endfor

  if exists('config_var')
    let bufcfgvar = neomake#compat#getbufvar(a:bufnr, config_var, s:unset)
    if bufcfgvar isnot s:unset
      return copy(bufcfgvar)
    elseif has_key(g:, config_var)
      return copy(get(g:, config_var))
    endif
  endif
  if has_key(a:maker, a:key)
    return a:maker[a:key]
  endif
  " Look for 'neomake_'.key in the buffer and global namespace.
  let bufvar = neomake#compat#getbufvar(a:bufnr, 'neomake_'.a:key, s:unset)
  if bufvar isnot s:unset
      return bufvar
  endif
  if has_key(g:, 'neomake_'.a:key)
      return get(g:, 'neomake_'.a:key)
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
    " Expand % in args like when using :!
    " \% is ignored
    " \\% is expanded to \\file.ext
    " %% becomes %
    " % must be followed with an expansion keyword
    let isk = &iskeyword
    set iskeyword=p,h,t,r,e,%,:
    try
        let ret = map(a:args,
                    \ 'substitute(v:val, '
                    \ . '''\(\%(\\\@<!\\\)\@<!%\%(%\|\%(:[phtre]\+\)*\)\ze\)\w\@!'', '
                    \ . '''\=(submatch(1) == "%%" ? "%" : expand(submatch(1)))'', '
                    \ . '''g'')')
    finally
        let &iskeyword = isk
    endtry
    return ret
endfunction

function! neomake#utils#hook(event, context, ...) abort
    if exists('#User#'.a:event)
        let jobinfo = a:0 ? a:1 : (
                    \ has_key(a:context, 'jobinfo') ? a:context.jobinfo : {})
        let g:neomake_hook_context = a:context

        let args = ['Calling User autocmd '.a:event
                    \ .' with context: '.string(map(copy(a:context), "v:key ==# 'jobinfo' ? '…' : v:val"))]
        if len(jobinfo)
            let args += [jobinfo]
        endif
        call call('neomake#utils#LoudMessage', args)
        if v:version >= 704 || (v:version == 703 && has('patch442'))
            exec 'doautocmd <nomodeline> User ' . a:event
        else
            exec 'doautocmd User ' . a:event
        endif
        unlet g:neomake_hook_context
    else
        call neomake#utils#DebugMessage(printf(
                    \ 'Skipping User autocmd %s: no hooks.', a:event))
    endif
endfunction

function! neomake#utils#diff_dict(d1, d2) abort
    let diff = [{}, {}, {}]
    let keys = keys(a:d1) + keys(a:d2)
    for k in keys
        if !has_key(a:d2, k)
            let diff[1][k] = a:d1[k]
        elseif !has_key(a:d1, k)
            let diff[2][k] = a:d2[k]
        elseif type(a:d1[k]) !=# type(a:d2[k]) || a:d1[k] !=# a:d2[k]
            let diff[0][k] = [a:d1[k], a:d2[k]]
        endif
    endfor
    return diff
endfunction

" Sort quickfix/location list entries by distance to current cursor position's
" column, but preferring entries starting at or behind the cursor position.
function! neomake#utils#sort_by_col(a, b) abort
    let col = getpos('.')[2]
    if a:a.col > col
        if a:b.col < col
            return 1
        endif
    elseif a:b.col > col
        return -1
    endif
    return abs(col - a:a.col) - abs(col - a:b.col)
endfunction

function! neomake#utils#path_sep() abort
    return neomake#utils#IsRunningWindows() ? ';' : ':'
endfunction
