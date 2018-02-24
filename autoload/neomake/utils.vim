" vim: ts=4 sw=4 et
scriptencoding utf-8

let s:level_to_name = {0: 'error  ', 1: 'warning', 2: 'verbose', 3: 'debug  '}
let s:short_level_to_name = {0: 'E', 1: 'W', 2: 'V', 3: 'D'}

let s:is_testing = exists('g:neomake_test_messages')

function! s:reltime_lastmsg() abort
    if exists('s:last_msg_ts')
        let cur = neomake#compat#reltimefloat()
        let diff = (cur - s:last_msg_ts)
    else
        let diff = 0
    endif
    let s:last_msg_ts = neomake#compat#reltimefloat()

    if diff < 0.01
        return '     '
    elseif diff < 10
        let format = '+%.2f'
    elseif diff < 100
        let format = '+%.1f'
    elseif diff < 100
        let format = '  +%.0f'
    elseif diff < 1000
        let format = ' +%.0f'
    else
        let format = '+%.0f'
    endif
    return printf(format, diff)
endfunction

" Get verbosity, optionally based on jobinfo's make_id (a:1).
function! neomake#utils#get_verbosity(...) abort
    if a:0 && has_key(a:1, 'make_id')
        return neomake#GetMakeOptions(a:1.make_id).verbosity
    endif
    return get(g:, 'neomake_verbose', 1) + &verbose
endfunction

function! neomake#utils#LogMessage(level, msg, ...) abort
    if a:0
        let context = a:1
        let verbosity = neomake#utils#get_verbosity(context)
    else
        let context = {}  " just for vimlint (EVL104)
        let verbosity = neomake#utils#get_verbosity()
    endif
    let logfile = get(g:, 'neomake_logfile', '')

    if !s:is_testing && verbosity < a:level && logfile is# ''
        return
    endif

    if a:0
        let msg = printf('[%s.%s:%s:%d] %s',
                    \ get(context, 'make_id', '-'),
                    \ get(context, 'id', '-'),
                    \ get(context, 'bufnr', get(context, 'file_mode', 0) ? '?' : '-'),
                    \ winnr(),
                    \ a:msg)
    else
        let msg = a:msg
    endif

    " Use Vader's log for messages during tests.
    " @vimlint(EVL104, 1, l:timediff)
    if s:is_testing && (verbosity >= a:level || get(g:, 'neomake_test_log_all_messages', 0))
        let timediff = s:reltime_lastmsg()
        if timediff !=# '     '
            let test_msg = '['.s:short_level_to_name[a:level].' '.timediff.']: '.msg
        else
            let test_msg = '['.s:level_to_name[a:level].']: '.msg
        endif

        call vader#log(test_msg)
        " Only keep context entries that are relevant for / used in the message.
        let context = a:0
                    \ ? filter(copy(context), "index(['id', 'make_id', 'bufnr'], v:key) != -1")
                    \ : {}
        call add(g:neomake_test_messages, [a:level, a:msg, context])
        if index(['.', '!', ')', ']'], a:msg[-1:-1]) == -1
            Assert 0, 'Log msg does not end with punctuation: "'.a:msg.'".'
        endif
    elseif verbosity >= a:level
        redraw
        if a:level ==# 0
            echohl ErrorMsg
        endif
        if verbosity > 2
            if !exists('timediff')
                let timediff = s:reltime_lastmsg()
            endif
            echom 'Neomake ['.timediff.']: '.msg
        else
            echom 'Neomake: '.msg
        endif
        if a:level ==# 0
            echohl None
        endif
    endif
    if !empty(logfile) && type(logfile) ==# type('')
        if !exists('s:logfile_writefile_opts')
            " Use 'append' with writefile, but only if it is available.  Otherwise, just
            " overwrite the file.  'S' is used to disable fsync in Neovim
            " (https://github.com/neovim/neovim/pull/6427).
            let s:can_append_to_logfile = v:version > 704 || (v:version == 704 && has('patch503'))
            if !s:can_append_to_logfile
                redraw
                echohl WarningMsg
                echom 'Neomake: appending to the logfile is not supported in your Vim version.'
                echohl NONE
            endif
            let s:logfile_writefile_opts = s:can_append_to_logfile ? 'aS' : ''
        endif

        let date = strftime('%H:%M:%S')
        if !exists('timediff')
            let timediff = s:reltime_lastmsg()
        endif
        try
            call writefile([printf('%s [%s %s] %s',
                        \ date, s:short_level_to_name[a:level], timediff, msg)],
                        \ logfile, s:logfile_writefile_opts)
        catch
            unlet g:neomake_logfile
            call neomake#utils#ErrorMessage(printf('Error when trying to write to logfile %s: %s.  Unsetting g:neomake_logfile.', logfile, v:exception))
        endtry
    endif
    " @vimlint(EVL104, 0, l:timediff)
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
        for [k, V] in items(a:obj)
            if type(V) == type(function('tr'))
                let fname = substitute(string(V), ', {\zs.*\ze})', '…', '')
                call add(ls, k.': '.fname)
            else
                call add(ls, k.': '.neomake#utils#Stringify(V))
            endif
            unlet V  " vim73
        endfor
        return '{'.join(ls, ', ').'}'
    elseif type(a:obj) == type(function('tr'))
        return string(a:obj)
    else
        return a:obj
    endif
endfunction

function! neomake#utils#DebugObject(msg, obj) abort
    call neomake#utils#DebugMessage(a:msg.': '.neomake#utils#Stringify(a:obj).'.')
endfunction

function! neomake#utils#wstrpart(mb_string, start, len) abort
    return matchstr(a:mb_string, '.\{,'.a:len.'}', 0, a:start+1)
endfunction

" This comes straight out of syntastic.
"print as much of a:msg as possible without "Press Enter" prompt appearing
function! neomake#utils#WideMessage(msg) abort " {{{2
    let old_ruler = &ruler
    let old_showcmd = &showcmd

    " Replace newlines (typically in the msg) with a single space.  This
    " might happen with writegood.
    let msg = substitute(a:msg, '\r\?\n', ' ', 'g')

    "convert tabs to spaces so that the tabs count towards the window
    "width as the proper amount of characters
    let chunks = split(msg, "\t", 1)
    let msg = join(map(chunks[:-2], "v:val . repeat(' ', &tabstop - strwidth(v:val) % &tabstop)"), '') . chunks[-1]
    let msg = neomake#utils#wstrpart(msg, 0, &columns - 1)

    set noruler noshowcmd
    redraw

    call neomake#utils#DebugMessage('WideMessage: echo '.msg.'.')
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

" Get directory/path separator.
function! neomake#utils#Slash() abort
    return (!exists('+shellslash') || &shellslash) ? '/' : '\'
endfunction

function! neomake#utils#Exists(exe) abort
    " DEPRECATED: just use executable() directly.
    return executable(a:exe)
endfunction

let s:command_maker = {
            \ 'remove_invalid_entries': 0,
            \ '_get_fname_for_args': get(g:neomake#core#command_maker_base, '_get_fname_for_args'),
            \ }
function! s:command_maker.fn(jobinfo) dict abort
    " Return a cleaned up copy of self.
    let maker = filter(deepcopy(self), "v:key !~# '^__' && v:key !=# 'fn'")

    let command = self.__command
    if type(command) == type('')
        let argv = split(&shell) + split(&shellcmdflag)
        let maker.exe = argv[0]
        let maker.args = argv[1:] + [command]
    else
        let maker.exe = command[0]
        let maker.args = command[1:]
    endif
    let fname = self._get_fname_for_args(a:jobinfo)
    if !empty(fname)
        if type(command) == type('')
            let maker.args[-1] .= ' '.fname
        else
            call add(maker.args, fname)
        endif
    endif
    return maker
endfunction

" @vimlint(EVL103, 1, a:jobinfo)
function! s:command_maker._get_argv(jobinfo) abort dict
    return neomake#compat#get_argv(self.exe, self.args, 1)
endfunction
" @vimlint(EVL103, 0, a:jobinfo)

" Create a maker object, with a "fn" callback.
" Args: command (string or list).  Gets wrapped in a shell in case it is a
"       string.
function! neomake#utils#MakerFromCommand(command) abort
    let maker = copy(s:command_maker)
    let maker.__command = a:command
    return maker
endfunction

let s:super_ft_cache = {}
function! neomake#utils#GetSupersetOf(ft) abort
    if !has_key(s:super_ft_cache, a:ft)
        call neomake#utils#load_ft_makers(a:ft)
        let SupersetOf = 'neomake#makers#ft#'.a:ft.'#SupersetOf'
        if exists('*'.SupersetOf)
            let s:super_ft_cache[a:ft] = call(SupersetOf, [])
        else
            let s:super_ft_cache[a:ft] = ''
        endif
    endif
    return s:super_ft_cache[a:ft]
endfunction

let s:loaded_ft_maker_runtime = []
function! neomake#utils#load_ft_makers(ft) abort
    " Load ft maker, but only once (for performance reasons and to allow for
    " monkeypatching it in tests).
    if index(s:loaded_ft_maker_runtime, a:ft) == -1
        if !exists('*neomake#makers#ft#'.a:ft.'#EnabledMakers')
            silent exe 'runtime! autoload/neomake/makers/ft/'.a:ft.'.vim'
        endif
        call add(s:loaded_ft_maker_runtime, a:ft)
    endif
endfunction

let s:loaded_global_maker_runtime = 0
function! neomake#utils#load_global_makers() abort
    " Load global makers, but only once (for performance reasons and to allow
    " for monkeypatching it in tests).
    if !s:loaded_global_maker_runtime
        exe 'runtime! autoload/neomake/makers/*.vim'
        let s:loaded_global_maker_runtime = 1
    endif
endfunction

function! neomake#utils#get_ft_confname(ft, ...) abort
    return substitute(a:ft, '\W', a:0 ? a:1 : '_', 'g')
endfunction

" Resolve filetype a:ft into a list of filetypes suitable for config vars
" (i.e. 'foo.bar' => ['foo_bar', 'foo', 'bar']).
function! neomake#utils#get_config_fts(ft, ...) abort
    let r = []
    let fts = split(a:ft, '\.')
    for ft in fts
        call add(r, ft)
        let super_ft = neomake#utils#GetSupersetOf(ft)
        while !empty(super_ft)
            if index(fts, super_ft) == -1
                call add(r, super_ft)
            endif
            let super_ft = neomake#utils#GetSupersetOf(super_ft)
        endwhile
    endfor
    if len(fts) > 1
        call insert(r, a:ft, 0)
    endif
    let delim = a:0 ? a:1 : '_'
    return map(r, 'neomake#utils#get_ft_confname(v:val, delim)')
endfunction

let s:unset = {}  " Sentinel.

" Get a setting by key, based on filetypes, from the buffer or global
" namespace, defaulting to default.
function! neomake#utils#GetSetting(key, maker, default, ft, bufnr, ...) abort
    let maker_only = a:0 ? a:1 : 0

    " Check new-style config.
    if exists('g:neomake') || !empty(getbufvar(a:bufnr, 'neomake'))
        let context = {'ft': a:ft, 'maker': a:maker, 'bufnr': a:bufnr, 'maker_only': maker_only}
        let Ret = neomake#config#get(a:key, g:neomake#config#undefined, context)
        if Ret isnot g:neomake#config#undefined
            return Ret
        endif
    endif

    return s:get_oldstyle_setting(a:key, a:maker, a:default, a:ft, a:bufnr, maker_only)
endfunction

function! s:get_oldstyle_setting(key, maker, default, ft, bufnr, maker_only) abort
    let maker_name = has_key(a:maker, 'name') ? a:maker.name : ''
    if a:maker_only && empty(maker_name)
        if has_key(a:maker, a:key)
            return get(a:maker, a:key)
        endif
        return a:default
    endif

    if !empty(a:ft)
        let fts = neomake#utils#get_config_fts(a:ft) + ['']
    else
        let fts = ['']
    endif
    for ft in fts
        " Look through the override vars for a filetype maker, like
        " neomake_scss_sasslint_exe (should be a string), and
        " neomake_scss_sasslint_args (should be a list).
        let part = join(filter([ft, maker_name], '!empty(v:val)'), '_')
        if empty(part)
            break
        endif
        let config_var = 'neomake_'.part.'_'.a:key
        unlet! Bufcfgvar  " vim73
        let Bufcfgvar = neomake#compat#getbufvar(a:bufnr, config_var, s:unset)
        if Bufcfgvar isnot s:unset
            return copy(Bufcfgvar)
        endif
        if has_key(g:, config_var)
            return copy(get(g:, config_var))
        endif
    endfor

    if has_key(a:maker, a:key)
        return get(a:maker, a:key)
    endif

    let key = a:maker_only ? maker_name.'_'.a:key : a:key
    " Look for 'neomake_'.key in the buffer and global namespace.
    let bufvar = neomake#compat#getbufvar(a:bufnr, 'neomake_'.key, s:unset)
    if bufvar isnot s:unset
        return bufvar
    endif
    if a:key !=# 'enabled_makers' && has_key(g:, 'neomake_'.key)
        return get(g:, 'neomake_'.key)
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

" Deprecated: moved to neomake#postprocess#compress_whitespace.
function! neomake#utils#CompressWhitespace(entry) abort
    call neomake#postprocess#compress_whitespace(a:entry)
endfunction

function! neomake#utils#redir(cmd) abort
    " @vimlint(EVL108, 1)
    if exists('*execute') && has('nvim-0.2.0')
    " @vimlint(EVL108, 0)
        " NOTE: require Neovim, since Vim has at least an issue when using
        "       this in a :command-completion function.
        "       Ref: https://github.com/neomake/neomake/issues/650.
        "       Neovim 0.1.7 also parses 'highlight' wrongly.
        return execute(a:cmd)
    endif
    if type(a:cmd) == type([])
        let r = ''
        for cmd in a:cmd
            let r .= neomake#utils#redir(cmd)
        endfor
        return r
    endif
    try
        redir => neomake_redir
        silent exe a:cmd
    catch /^Vim(redir):E121:/
        throw printf('Neomake: neomake#utils#redir: called with outer :redir (error: %s).',
                    \ v:exception)
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
    let ret = map(copy(a:args),
                \ 'substitute(v:val, '
                \ . '''\(\%(\\\@<!\\\)\@<!%\%(%\|\%(:[phtre]\+\)*\)\ze\)\w\@!'', '
                \ . '''\=(submatch(1) == "%%" ? "%" : expand(submatch(1)))'', '
                \ . '''g'')')
    let ret = map(ret,
                \ 'substitute(v:val, '
                \ . '''\(\%(\\\@<!\\\)\@<!\~\)'', '
                \ . 'expand(''~''), '
                \ . '''g'')')
    return ret
endfunction

function! neomake#utils#log_exception(error, ...) abort
    let log_context = a:0 ? a:1 : {'bufnr': bufnr('%')}
    redraw
    echom printf('Neomake error in: %s', v:throwpoint)
    call neomake#utils#ErrorMessage(a:error, log_context)
    call neomake#utils#DebugMessage(printf('(in %s)', v:throwpoint), log_context)
endfunction

let s:hook_context_stack = []
function! neomake#utils#hook(event, context, ...) abort
    if exists('#User#'.a:event)
        let jobinfo = a:0 ? a:1 : (
                    \ has_key(a:context, 'jobinfo') ? a:context.jobinfo : {})

        let args = [printf('Calling User autocmd %s with context: %s.',
                    \ a:event, string(map(copy(a:context), "v:key ==# 'jobinfo' ? '…' : v:val")))]
        if !empty(jobinfo)
            let args += [jobinfo]
        endif
        call call('neomake#utils#LoudMessage', args)

        if exists('g:neomake_hook_context')
            call add(s:hook_context_stack, g:neomake_hook_context)
        endif
        unlockvar g:neomake_hook_context
        let g:neomake_hook_context = a:context
        lockvar 1 g:neomake_hook_context
        try
            if v:version >= 704 || (v:version == 703 && has('patch442'))
                exec 'doautocmd <nomodeline> User ' . a:event
            else
                exec 'doautocmd User ' . a:event
            endif
        catch
            call neomake#utils#log_exception(printf(
                        \ 'Error during User autocmd for %s: %s.',
                        \ a:event, v:exception), jobinfo)
        finally
            if !empty(s:hook_context_stack)
                unlockvar g:neomake_hook_context
                let g:neomake_hook_context = remove(s:hook_context_stack, -1)
                lockvar 1 g:neomake_hook_context
            else
                unlet g:neomake_hook_context
            endif
        endtry
    endif
endfunction

function! neomake#utils#diff_dict(old, new) abort
    let diff = {}
    let keys = keys(a:old) + keys(a:new)
    for k in keys
        if !has_key(a:new, k)
            if !has_key(diff, 'removed')
                let diff['removed'] = {}
            endif
            let diff['removed'][k] = a:old[k]
        elseif !has_key(a:old, k)
            if !has_key(diff, 'added')
                let diff['added'] = {}
            endif
            let diff['added'][k] = a:new[k]
        elseif type(a:old[k]) !=# type(a:new[k]) || a:old[k] !=# a:new[k]
            if !has_key(diff, 'changed')
                let diff['changed'] = {}
            endif
            let diff['changed'][k] = [a:old[k], a:new[k]]
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

" Find a file matching `a:glob` (using `globpath()`) by going up the
" directories from the start directory (a:1, defaults to `expand('%:p:h')`,
" i.e. the directory of the current buffer's file).)
function! neomake#utils#FindGlobFile(glob, ...) abort
    let curDir = a:0 ? a:1 : expand('%:p:h')
    let fileFound = []
    while 1
        let fileFound = neomake#compat#globpath_list(curDir, a:glob, 1)
        if !empty(fileFound)
            return fileFound[0]
        endif
        let lastFolder = curDir
        let curDir = fnamemodify(curDir, ':h')
        if curDir ==# lastFolder
            break
        endif
    endwhile
    return ''
endfunction

function! neomake#utils#JSONdecode(json) abort
    return neomake#compat#json_decode(a:json)
endfunction

" Smarter shellescape, via vim-fugitive.
function! s:gsub(str,pat,rep) abort
    return substitute(a:str,'\v\C'.a:pat,a:rep,'g')
endfunction

function! neomake#utils#shellescape(arg) abort
    if a:arg =~# '^[A-Za-z0-9_/.=-]\+$'
        return a:arg
    elseif &shell =~? 'cmd' || exists('+shellslash') && !&shellslash
        return '"'.s:gsub(s:gsub(a:arg, '"', '""'), '\%', '"%"').'"'
    endif
    return shellescape(a:arg)
endfunction

function! neomake#utils#get_buffer_lines(bufnr) abort
    let buflines = getbufline(a:bufnr, 1, '$')
    " Special case: empty buffer; do not write an empty line in this case.
    if len(buflines) > 1 || buflines != ['']
        if getbufvar(a:bufnr, '&endofline')
                    \ || (!getbufvar(a:bufnr, '&binary')
                    \     && (!exists('+fixendofline') || getbufvar(a:bufnr, '&fixendofline')))
            call add(buflines, '')
        endif
    endif
    return buflines
endfunction

function! neomake#utils#write_tempfile(bufnr, temp_file) abort
    call writefile(neomake#utils#get_buffer_lines(a:bufnr), a:temp_file, 'b')
endfunction

" Wrapper around fnamemodify that handles special buffers (e.g. fugitive).
function! neomake#utils#fnamemodify(bufnr, modifier) abort
    let bufnr = +a:bufnr
    if !empty(getbufvar(bufnr, 'fugitive_type'))
        let fug_buffer = fugitive#buffer(bufnr)
        let path = fnamemodify(fug_buffer.repo().translate(fug_buffer.path()), ':.')
    else
        let path = bufname(bufnr)
    endif
    return empty(path) ? '' : fnamemodify(path, a:modifier)
endfunction

function! neomake#utils#fix_self_ref(obj, ...) abort
    if type(a:obj) != type({})
        return a:obj
    endif
    let obj = copy(a:obj)
    for k in keys(obj)
        if a:0
            let self_ref = filter(copy(a:1), 'v:val[1][0] is obj[k]')
            if !empty(self_ref)
                let obj[k] = printf('<self-ref-%d: %s>', self_ref[0][0], self_ref[0][1][1])
                continue
            endif
        endif
        if type(obj[k]) == type({})
            let obj[k] = neomake#utils#fix_self_ref(obj[k], a:0 ? a:1 + [[len(a:1)+1, [a:obj, k]]] : [[1, [a:obj, k]]])
        elseif has('nvim')
            " Ensure that it can be used as a string.
            " Ref: https://github.com/neovim/neovim/issues/7432
            try
                call string(obj[k])
            catch /^Vim(call):E724:/
                let obj[k] = '<unrepresentable object, type='.type(obj).'>'
            endtry
        endif
    endfor
    return obj
endfunction

function! neomake#utils#parse_highlight(group) abort
    let output = neomake#utils#redir('highlight '.a:group)
    return join(split(output)[2:])
endfunction

function! neomake#utils#highlight_is_defined(group) abort
    if !hlexists(a:group)
        return 0
    endif
    return neomake#utils#parse_highlight(a:group) !=# 'cleared'
endfunction

function! neomake#utils#get_project_root(bufnr) abort
    let ft = getbufvar(a:bufnr, '&filetype')
    call neomake#utils#load_ft_makers(ft)

    let project_root_files = ['.git', 'Makefile']

    let ft_project_root_files = 'neomake#makers#ft#'.ft.'#project_root_files'
    if has_key(g:, ft_project_root_files)
        let project_root_files = get(g:, ft_project_root_files) + project_root_files
    endif

    let buf_dir = expand('#'.a:bufnr.':p:h')
    for fname in project_root_files
        let project_root = neomake#utils#FindGlobFile(fname, buf_dir)
        if !empty(project_root)
            return fnamemodify(project_root, ':h')
        endif
    endfor
    return ''
endfunction
