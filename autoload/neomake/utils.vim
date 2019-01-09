" vim: ts=4 sw=4 et
scriptencoding utf-8

" Get verbosity, optionally based on jobinfo's make_id (a:1).
function! neomake#utils#get_verbosity(...) abort
    if a:0 && has_key(a:1, 'make_id')
        return neomake#GetMakeOptions(a:1.make_id).verbosity
    endif
    return get(g:, 'neomake_verbose', 1) + &verbose
endfunction

function! neomake#utils#Stringify(obj) abort
    if type(a:obj) == type([])
        let ls = map(copy(a:obj), 'neomake#utils#Stringify(v:val)')
        return '['.join(ls, ', ').']'
    elseif type(a:obj) == type({})
        let ls = []
        for [k, V] in items(neomake#utils#fix_self_ref(a:obj))
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

    call neomake#log#debug('WideMessage: echo '.msg.'.')
    echo msg

    let &ruler = old_ruler
    let &showcmd = old_showcmd
endfunction " }}}2

" This comes straight out of syntastic.
function! neomake#utils#IsRunningWindows() abort
    return has('win32') || has('win64')
endfunction

" Get directory/path separator.
function! neomake#utils#Slash() abort
    return (!exists('+shellslash') || &shellslash) ? '/' : '\'
endfunction

function! neomake#utils#Exists(exe) abort
    " DEPRECATED: just use executable() directly.
    return executable(a:exe)
endfunction

" Object used with neomake#utils#MakerFromCommand.
let s:maker_from_command = extend(copy(g:neomake#core#command_maker_base), {
            \ 'remove_invalid_entries': 0,
            \ })
function! s:maker_from_command._get_argv(jobinfo) abort dict
    let fname = self._get_fname_for_args(a:jobinfo)
    let args = neomake#utils#ExpandArgs(self.args, a:jobinfo)
    if !empty(fname)
        if self.__command_is_string
            let fname = neomake#utils#shellescape(fname)
            let args[-1] .= ' '.fname
        else
            call add(args, fname)
        endif
    endif
    return neomake#compat#get_argv(self.exe, args, 1)
endfunction

" Create a maker object for a given command.
" Args: command (string or list).  Gets wrapped in a shell in case it is a
"       string.
function! neomake#utils#MakerFromCommand(command) abort
    let maker = copy(s:maker_from_command)
    if type(a:command) == type('')
        let argv = split(&shell) + split(&shellcmdflag)
        let maker.exe = argv[0]
        let maker.args = argv[1:] + [a:command]
        let maker.__command_is_string = 1
    else
        let maker.exe = a:command[0]
        let maker.args = a:command[1:]
        let maker.__command_is_string = 0
    endif
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
    let delim = a:0 ? a:1 : '_'
    let cache_key = a:ft . delim
    if !has_key(s:cache_config_fts, cache_key)
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
        let s:cache_config_fts[cache_key] = map(r, 'neomake#utils#get_ft_confname(v:val, delim)')
    endif
    return s:cache_config_fts[cache_key]
endfunction
let s:cache_config_fts = {}

let s:unset = {}  " Sentinel.

" Get a setting by key, based on filetypes, from the buffer or global
" namespace, defaulting to default.
" Use an empty bufnr ('') to ignore buffer-local settings.
function! neomake#utils#GetSetting(key, maker, default, ft, bufnr, ...) abort
    let maker_only = a:0 ? a:1 : 0

    " Check new-style config.
    if exists('g:neomake') || !empty(getbufvar(a:bufnr, 'neomake'))
        let context = {'ft': a:ft, 'maker': a:maker, 'bufnr': a:bufnr, 'maker_only': maker_only}
        let [Ret, source] = neomake#config#get_with_source(a:key, g:neomake#config#undefined, context)
        " Check old-style setting when source is the maker.
        if source ==# 'maker' && !maker_only
            let tmpmaker = {}
            if has_key(a:maker, 'name')
                let tmpmaker.name = a:maker.name
            endif
            let RetOld = s:get_oldstyle_setting(a:key, tmpmaker, s:unset, a:ft, a:bufnr, 1)
            if RetOld isnot# s:unset
                return RetOld
            endif
        endif
        if Ret isnot g:neomake#config#undefined
            return Ret
        endif
    endif

    return s:get_oldstyle_setting(a:key, a:maker, a:default, a:ft, a:bufnr, maker_only)
endfunction

function! s:get_oldstyle_setting(key, maker, default, ft, bufnr, maker_only) abort
    let maker_name = get(a:maker, 'name', '')
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
        let part = join(filter([ft, maker_name], '!empty(v:val)'), '_')
        if empty(part)
            break
        endif
        let config_var = 'neomake_'.part.'_'.a:key
        if a:bufnr isnot# ''
            let Bufcfgvar = neomake#compat#getbufvar(a:bufnr, config_var, s:unset)
            if Bufcfgvar isnot s:unset
                return copy(Bufcfgvar)
            endif
        endif
        if has_key(g:, config_var)
            return copy(get(g:, config_var))
        endif
        unlet! Bufcfgvar  " vim73
    endfor

    if has_key(a:maker, a:key)
        return get(a:maker, a:key)
    endif

    let key = a:key
    if a:maker_only
        let key = maker_name.'_'.key
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

function! neomake#utils#ExpandArgs(args, jobinfo) abort
    if has_key(a:jobinfo, 'tempfile')
        let fname = a:jobinfo.tempfile
    else
        let fname = bufname('%')
        if !empty(fname)
            let fname = fnamemodify(fname, ':p')
        endif
    endif
    let ret = map(copy(a:args), "substitute(v:val, '%t', fname, 'g')")

    " Expand % in args similar to when using :!
    " \% is ignored
    " \\% is expanded to \\file.ext
    " %% becomes %
    " % must be followed with an expansion keyword
    let ret = map(ret,
                \ 'substitute(v:val, '
                \ . '''\(\%(\\\@<!\\\)\@<!%\%(%\|<\|\%(:[phtreS8.~]\)\+\|\ze\w\@!\)\)'', '
                \ . '''\=(submatch(1) == "%%" ? "%" : expand(submatch(1)))'', '
                \ . '''g'')')
    let ret = map(ret, 'substitute(v:val, ''\v^\~\ze%(/|$)'', expand(''~''), ''g'')')
    return ret
endfunction

if has('patch-7.3.1058')
    function! s:function(name) abort
        return function(a:name)
    endfunction
else
    " Older Vim does not handle s: function references across files.
    function! s:function(name) abort
        return function(substitute(a:name,'^s:',matchstr(expand('<sfile>'), '.*\zs<SNR>\d\+_'),''))
    endfunction
endif

function! s:handle_hook(jobinfo, event, context) abort
    let context_str = string(map(copy(a:context),
                \ "v:key ==# 'make_info' ? 'make_info #'.get(v:val, 'make_id')"
                \ .": (v:key ==# 'options' && has_key(v:val, 'jobs') ? extend(copy(v:val), {'jobs': map(copy(v:val.jobs), 'v:val.maker.name')}, 'force')"
                \ .": (v:key ==# 'jobinfo' ? v:val.as_string()"
                \ .": (v:key ==# 'finished_jobs' ? map(copy(v:val), 'v:val.as_string()') : v:val)))"))

    if exists('g:neomake_hook_context')
        call neomake#log#debug(printf('Queuing User autocmd %s for nested invocation (%s).', a:event, context_str),
                    \ a:jobinfo)
        return neomake#action_queue#add(
                    \ ['Timer', 'BufEnter', 'WinEnter', 'InsertLeave', 'CursorHold', 'CursorHoldI'],
                    \ [s:function('s:handle_hook'), [a:jobinfo, a:event, a:context]])
    endif

    let log_args = [printf('Calling User autocmd %s with context: %s.',
                \ a:event, context_str)]
    if !empty(a:jobinfo)
        let log_args += [a:jobinfo]
    endif
    call call('neomake#log#info', log_args)

    unlockvar g:neomake_hook_context
    let g:neomake_hook_context = a:context
    lockvar 1 g:neomake_hook_context
    try
        call neomake#compat#doautocmd('User '.a:event)
    catch
        let error = v:exception
        if error[-1:] !=# '.'
            let error .= '.'
        endif
        call neomake#log#exception(printf(
                    \ 'Error during User autocmd for %s: %s',
                    \ a:event, error), a:jobinfo)
    finally
        unlet g:neomake_hook_context
    endtry
    return g:neomake#action_queue#processed
endfunction

function! neomake#utils#hook(event, context, ...) abort
    if exists('#User#'.a:event)
        let jobinfo = a:0 ? a:1 : (
                    \ has_key(a:context, 'jobinfo') ? a:context.jobinfo : {})
        return s:handle_hook(jobinfo, a:event, a:context)
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
        if exists('*FugitivePath')
            let path = FugitivePath(bufname(bufnr))
        else
            let fug_buffer = fugitive#buffer(bufnr)
            let path = fug_buffer.repo().translate(fug_buffer.path())
        endif
        if empty(a:modifier)
            let path = fnamemodify(path, ':.')
        endif
    else
        let path = bufname(bufnr)
    endif
    return empty(path) ? '' : fnamemodify(path, a:modifier)
endfunction

function! neomake#utils#fix_self_ref(obj, ...) abort
    if type(a:obj) != type({})
        if type(a:obj) == type([])
            return map(copy(a:obj), 'neomake#utils#fix_self_ref(v:val)')
        endif
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

" Get the root directory of the current project.
" This is determined by looking for specific files (e.g. `.git` and
" `Makefile`), and `g:neomake#makers#ft#X#project_root_files` (if defined for
" filetype "X").
" a:1 buffer number (defaults to current)
function! neomake#utils#get_project_root(...) abort
    let bufnr = a:0 ? a:1 : bufnr('%')
    let ft = getbufvar(bufnr, '&filetype')
    call neomake#utils#load_ft_makers(ft)

    let project_root_files = ['.git', 'Makefile']

    let ft_project_root_files = 'neomake#makers#ft#'.ft.'#project_root_files'
    if has_key(g:, ft_project_root_files)
        let project_root_files = get(g:, ft_project_root_files) + project_root_files
    endif

    let buf_dir = expand('#'.bufnr.':p:h')
    for fname in project_root_files
        let project_root = neomake#utils#FindGlobFile(fname, buf_dir)
        if !empty(project_root)
            return fnamemodify(project_root, ':h')
        endif
    endfor
    return ''
endfunction

" Return the number of lines for a given buffer.
" This returns 0 for unloaded buffers.
if exists('*nvim_buf_line_count')
    function! neomake#utils#get_buf_line_count(bufnr) abort
        if !bufloaded(a:bufnr)
            " https://github.com/neovim/neovim/issues/7688
            return 0
        endif
        return nvim_buf_line_count(a:bufnr)
    endfunction
else
    function! neomake#utils#get_buf_line_count(bufnr) abort
        if a:bufnr == bufnr('%')
            return line('$')
        endif
        " TODO: this should get cached (based on b:changedtick), and cleaned
        "       in BufWipeOut.
        return len(getbufline(a:bufnr, 1, '$'))
    endfunction
endif

" Returns: [error, cd_back_cmd]
function! neomake#utils#temp_cd(dir, ...) abort
    if a:dir ==# '.'
        return ['', '']
    endif
    if a:0
        let cur_wd = a:1
    else
        let cur_wd = getcwd()
        if cur_wd ==# a:dir
            " No need to change directory.
            return ['', '']
        endif
    endif
    let cd = haslocaldir() ? 'lcd' : (exists(':tcd') == 2 && haslocaldir(-1, 0)) ? 'tcd' : 'cd'
    try
        exe cd.' '.fnameescape(a:dir)
    catch
        " Tests fail with E344, but in reality it is E472?!
        " If uncaught, both are shown - let's just catch everything.
        return [v:exception, '']
    endtry
    return ['', cd.' '.fnameescape(cur_wd)]
endfunction

if exists('*nvim_buf_get_lines')
    function! neomake#utils#buf_get_lines(bufnr, start, end) abort
        if a:start < 1
            throw 'neomake#utils#buf_get_lines: start is lower than 1'
        endif
        try
            return nvim_buf_get_lines(a:bufnr, a:start-1, a:end-1, 1)
        catch
            throw 'neomake#utils#buf_get_lines: '.substitute(v:exception, '\v^[^:]+:', '', '')
        endtry
    endfunction
else
    function! neomake#utils#buf_get_lines(bufnr, start, end) abort
        if a:bufnr != bufnr('%')
            throw 'Neomake: neomake#utils#buf_get_lines: used for non-current buffer'
        endif
        if a:start < 1
            throw 'neomake#utils#buf_get_lines: start is lower than 1'
        endif
        if a:end-1 > line('$')
            throw 'neomake#utils#buf_get_lines: end is higher than number of lines'
        endif
        let r = []
        let i = a:start
        while i < a:end
            let r += [getline(i)]
            let i += 1
        endwhile
        return r
    endfunction
endif

if exists('*nvim_buf_set_lines')
    function! neomake#utils#buf_set_lines(bufnr, start, end, replacement) abort
        if a:start < 1
            return 'neomake#utils#buf_set_lines: start is lower than 1'
        endif
        try
            call nvim_buf_set_lines(a:bufnr, a:start-1, a:end-1, 1, a:replacement)
        catch
            " call neomake#log#error('Fixing entry failed (out of bounds)')
            return 'neomake#utils#buf_set_lines: '.substitute(v:exception, '\v^[^:]+:', '', '')
        endtry
        return ''
    endfunction
else
    function! neomake#utils#buf_set_lines(bufnr, start, end, replacement) abort
        if a:bufnr != bufnr('%')
            return 'neomake#utils#buf_set_lines: used for non-current buffer'
        endif

        if a:start < 1
            return 'neomake#utils#buf_set_lines: start is lower than 1'
        endif
        if a:end > line('$')+1
            return 'neomake#utils#buf_set_lines: end is higher than number of lines'
        endif

        if a:start == a:end
            let lnum = a:start < 0 ? line('$') - a:start : a:start
            if append(lnum-1, a:replacement) == 1
                call neomake#log#error(printf('Failed to append line(s): %d (%d).', a:start, lnum), {'bufnr': a:bufnr})
            endif

        else
            let range = a:end - a:start
            if range > len(a:replacement)
                let end = min([a:end, line('$')])
                silent execute a:start.','.end.'d_'
                call setline(a:start, a:replacement)
            else
                let i = 0
                let n = len(a:replacement)
                while i < n
                    call setline(a:start + i, a:replacement[i])
                    let i += 1
                endwhile
            endif
        endif
        return ''
    endfunction
endif

function! neomake#utils#shorten_list_for_log(l, max) abort
    if len(a:l) > a:max
        return a:l[:a:max-1] + ['... ('.len(a:l).' total)']
    endif
    return a:l
endfunction
