" vim: ts=4 sw=4 et
scriptencoding utf-8

let s:make_id = 0
let s:job_id = 1
let s:jobs = {}
" A map of make_id to options, e.g. cwd when jobs where started.
let s:make_info = {}
let s:jobs_by_maker = {}
" Errors by [maker_type][bufnr][lnum]
let s:current_errors = {
    \ 'project': {},
    \ 'file': {}
    \ }
let s:need_errors_cleaning = {
    \ 'project': 1,
    \ 'file': {}
    \ }
let s:maker_defaults = {
            \ 'buffer_output': 1,
            \ 'remove_invalid_entries': 0}
let s:project_job_output = {}
" List of job ids with pending output per buffer.
let s:buffer_job_output = {}
" Keep track of for what maker.exe an error was thrown.
let s:exe_error_thrown = {}

" Sentinels.
let s:unset_list = []
let s:unset_dict = {}

function! neomake#has_async_support() abort
    return has('nvim') ||
                \ has('channel') && has('job') && has('patch-8.0.0027')
endfunction

function! s:sort_jobs(a, b) abort
    return a:a.id - a:b.id
endfunction

function! neomake#GetJobs(...) abort
    if empty(s:jobs)
        return []
    endif
    let jobs = copy(values(s:jobs))
    if a:0
        call filter(jobs, 'index(a:1, v:val.id) != -1')
    endif
    return sort(jobs, function('s:sort_jobs'))
endfunction

function! neomake#GetJob(job_id) abort
    return s:jobs[a:job_id]
endfunction

" Not documented, only used in tests for now.
function! neomake#GetStatus() abort
    return {
                \ 'last_make_id': s:make_id,
                \ 'make_info': s:make_info,
                \ }
endfunction

" Not documented, only used internally for now.
function! neomake#GetMakeOptions(...) abort
    return s:make_info[a:0 ? a:1 : s:make_id]
endfunction

function! neomake#ListJobs() abort
    call neomake#utils#DebugMessage('call neomake#ListJobs()')
    for jobinfo in values(s:jobs)
        echom jobinfo.id.' '.jobinfo.name.' '.jobinfo.maker.name
    endfor
endfunction

function! neomake#CancelJob(job_id, ...) abort
    let remove_always = a:0 ? a:1 : 0
    " Handle '1: foo' format from neomake#CompleteJobs.
    let job_id = a:job_id + 0
    if !has_key(s:jobs, job_id)
        call neomake#utils#ErrorMessage('CancelJob: job not found: '.job_id)
        return 0
    endif
    let ret = 0
    let jobinfo = s:jobs[job_id]
    " Mark it as canceled for the exit handler.
    let jobinfo.canceled = 1
    if get(jobinfo, 'finished')
        call neomake#utils#DebugMessage('Removing already finished job', jobinfo)
    else
        call neomake#utils#DebugMessage('Stopping job', jobinfo)
        if has('nvim')
            try
                call jobstop(job_id)
                let ret = 1
            catch /^Vim\%((\a\+)\)\=:\(E474\|E900\):/
                call neomake#utils#LoudMessage(printf(
                            \ 'jobstop failed: %s', v:exception), jobinfo)
            endtry
        else
            let vim_job = jobinfo.vim_job
            " Use ch_status here, since job_status might be 'dead' already,
            " without the exit handler being called yet.
            if ch_status(vim_job) !=# 'open'
                call neomake#utils#LoudMessage(
                            \ 'job_stop: job was not running anymore', jobinfo)
            else
                call job_stop(vim_job)
                let ret = 1
            endif
        endif
    endif
    if ret == 0 || remove_always
        call s:CleanJobinfo(jobinfo)
    endif
    return ret
endfunction

function! neomake#CancelJobs(bang) abort
    for job_id in keys(s:jobs)
        call neomake#CancelJob(job_id, a:bang)
    endfor
endfunction

function! s:gettabwinvar(t, w, v, d) abort
    " Wrapper around gettabwinvar that has no default (Vim in Travis).
    let r = gettabwinvar(a:t, a:w, a:v)
    if r is# ''
        unlet r
        let r = a:d
    endif
    return r
endfunction

function! s:AddMakeInfoForCurrentWin(job_id) abort
    " Add jobinfo.make_id to current window.
    let tabpagenr = tabpagenr()
    let winnr = winnr()
    let w_ids = s:gettabwinvar(tabpagenr, winnr, 'neomake_make_ids', [])
    let w_ids += [a:job_id]
    call settabwinvar(tabpagenr, winnr, 'neomake_make_ids', w_ids)
endfunction

function! s:MakeJob(make_id, options) abort
    let job_id = s:job_id
    let s:job_id += 1

    " Optional:
    "  - serialize (default: 0)
    "  - serialize_abort_on_error (default: 0)
    "  - exit_callback (string/function, default: 0)
    let jobinfo = extend({
        \ 'name': 'neomake_'.job_id,
        \ 'maker': a:options.maker,
        \ 'bufnr': a:options.bufnr,
        \ 'file_mode': a:options.file_mode,
        \ 'ft': a:options.ft,
        \ }, a:options)

    let maker = jobinfo.maker

    if has_key(maker, 'get_list_entries')
        let entries = maker.get_list_entries(jobinfo)
        call s:ProcessEntries(jobinfo, entries)
        call s:CleanJobinfo(jobinfo)
        return
    endif

    if !executable(maker.exe)
        if !get(maker, 'auto_enabled', 0)
            let error = printf('Exe (%s) of maker %s is not executable.', maker.exe, maker.name)
            if !has_key(s:exe_error_thrown, maker.exe)
                let s:exe_error_thrown[maker.exe] = 1
                call neomake#utils#ErrorMessage(error)
            else
                call neomake#utils#DebugMessage(error)
            endif
            throw 'Neomake: '.error
        endif

        " XXX: mark it as to be skipped earlier?!
        call neomake#utils#DebugMessage(printf(
                    \ 'Exe (%s) of auto-configured maker %s is not executable, skipping.', maker.exe, maker.name))
        return {}
    endif

    let cwd = get(jobinfo, 'cwd', s:make_info[a:make_id].cwd)
    if !empty(cwd)
        let old_wd = getcwd()
        let cd = haslocaldir() ? 'lcd' : (exists(':tcd') == 2 && haslocaldir(-1, 0)) ? 'tcd' : 'cd'
        try
            exe cd fnameescape(cwd)
        " Tests fail with E344, but in reality it is E472?!
        " If uncaught, both are shown.  Let's just catch every error here.
        catch
            call neomake#utils#ErrorMessage(
                        \ maker.name.": could not change to maker's cwd (".cwd.'): '
                        \ .v:exception, jobinfo)
            return {}
        endtry
    endif

    try
        let error = ''
        let argv = maker._get_argv(jobinfo)

        if has_key(jobinfo, 'filename')
            let save_env_file = $NEOMAKE_FILE
            let $NEOMAKE_FILE = jobinfo.filename
        endif
        " Check for already running job for the same maker (from other runs).
        " This used to use this key: maker.name.',ft='.maker.ft.',buf='.maker.bufnr
        if !empty(s:jobs)
            let running_already = values(filter(copy(s:jobs),
                        \ 'v:val.make_id != a:make_id && v:val.maker == maker'
                        \ .' && v:val.bufnr == jobinfo.bufnr'
                        \ ." && !get(v:val, 'canceled')"))
            if !empty(running_already)
                let jobinfo = running_already[0]
                call neomake#utils#LoudMessage(printf(
                            \ 'Restarting already running job (%d.%d) for the same maker.',
                            \ jobinfo.make_id, jobinfo.id), {'make_id': a:make_id})
                call neomake#CancelJob(jobinfo.id)
                return s:MakeJob(a:make_id, a:options)
            endif
        endif

        " Lock maker to make sure it does not get changed accidentally, but
        " only with depth=1, so that a postprocess object can change itself.
        lockvar 1 maker
        if neomake#has_async_support()
            if has('nvim')
                let opts = {
                    \ 'on_stdout': function('s:nvim_output_handler'),
                    \ 'on_stderr': function('s:nvim_output_handler'),
                    \ 'on_exit': function('s:exit_handler')
                    \ }
                call neomake#utils#LoudMessage(printf('Starting async job: %s',
                            \ string(argv)), jobinfo)
                try
                    let job = jobstart(argv, opts)
                catch
                    let error = printf('Failed to start Neovim job: %s: %s',
                                \ string(argv), v:exception)
                endtry
                if empty(error)
                    if job == 0
                        let error = printf('Failed to start Neovim job: %s: %s',
                                    \ 'Job table is full or invalid arguments given', string(argv))
                    elseif job == -1
                        let error = printf('Failed to start Neovim job: %s: %s',
                                    \ 'Executable not found', string(argv))
                    else
                        let jobinfo.id = job
                        let s:jobs[jobinfo.id] = jobinfo
                    endif
                endif
            else
                " vim-async.
                let opts = {
                            \ 'out_cb': function('s:vim_output_handler_stdout'),
                            \ 'err_cb': function('s:vim_output_handler_stderr'),
                            \ 'close_cb': function('s:vim_exit_handler'),
                            \ 'mode': 'raw',
                            \ }
                call neomake#utils#LoudMessage(printf('Starting async job: %s',
                            \ string(argv)), jobinfo)
                try
                    let job = job_start(argv, opts)
                    " Get this as early as possible!
                    let jobinfo.id = ch_info(job)['id']
                catch
                    let error = printf('Failed to start Vim job: %s: %s',
                                \ argv, v:exception)
                endtry
                if empty(error)
                    let jobinfo.vim_job = job
                    let s:jobs[jobinfo.id] = jobinfo
                    call neomake#utils#DebugMessage(printf('Vim job: %s',
                                \ string(job_info(job))), jobinfo)
                    call neomake#utils#DebugMessage(printf('Vim channel: %s',
                                \ string(ch_info(job))), jobinfo)
                endif
            endif

            " Bail out on errors.
            if !empty(error)
                let jobinfo.failed_to_start = 1
                call neomake#utils#ErrorMessage(error, jobinfo)
                return s:handle_next_maker(jobinfo)
            endif
        else
            call neomake#utils#DebugMessage('Running synchronously')
            call neomake#utils#LoudMessage('Starting: '.argv, jobinfo)

            let jobinfo.id = job_id
            let s:jobs[job_id] = jobinfo
            let s:make_info[a:make_id].active_jobs += 1
            call s:output_handler(job_id, split(system(argv), '\r\?\n', 1), 'stdout')
            call s:exit_handler(job_id, v:shell_error, 'exit')
            return {}
        endif
    finally
        if exists('cd') && exists('old_wd')
            exe cd fnameescape(old_wd)
        endif
        if exists('save_env_file')
            " Not possible to unlet environment vars
            " (https://github.com/vim/vim/issues/1116).
            " Should only set it for the job
            " (https://github.com/vim/vim/pull/1160).
            let $NEOMAKE_FILE = save_env_file
        endif
    endtry
    let s:make_info[a:make_id].active_jobs += 1
    return jobinfo
endfunction

let s:maker_base = {}
let s:command_maker_base = {}
" Check if a temporary file is used, and set it in s:make_info in case it is.
function! s:command_maker_base._get_tempfilename(jobinfo) abort dict
    if has_key(self, 'tempfile_name')
        return self.tempfile_name
    endif

    let tempfile_enabled = neomake#utils#GetSetting('tempfile_enabled', self, 0, a:jobinfo.ft, a:jobinfo.bufnr)
    if !tempfile_enabled
        return ''
    endif

    let make_id = a:jobinfo.make_id
    if !has_key(s:make_info[make_id], 'tempfile_name')
        let bufname = bufname(a:jobinfo.bufnr)
        if !empty(bufname)
            let bufname = fnamemodify(bufname, ':t')
        else
            let bufname = 'neomake_tmp.'.a:jobinfo.ft
        endif
        let temp_file = tempname() . (has('win32') ? '\' : '/') . bufname
        let s:make_info[make_id].tempfile_name = temp_file
    endif
    return s:make_info[make_id].tempfile_name
endfunction

" Get the filename to use for a:jobinfo's make/buffer.
function! s:command_maker_base._get_fname_for_buffer(jobinfo) abort
    let bufnr = a:jobinfo.bufnr
    let bufname = bufname(bufnr)
    let temp_file = ''
    if empty(bufname)
        let temp_file = self._get_tempfilename(a:jobinfo)
        if !empty(temp_file)
            call neomake#utils#DebugMessage(printf(
                        \ 'Using tempfile for unnamed buffer: %s', temp_file),
                        \ a:jobinfo)
        else
            throw 'Neomake: no file name'
        endif

    elseif getbufvar(bufnr, '&modified')
        let temp_file = self._get_tempfilename(a:jobinfo)
        if !empty(temp_file)
            call neomake#utils#DebugMessage(printf(
                        \ 'Using tempfile for modified buffer: %s', temp_file),
                        \ a:jobinfo)
        else
            call neomake#utils#DebugMessage('warning: buffer is modified',
                        \ a:jobinfo)
        endif

    elseif !filereadable(bufname)
        let temp_file = self._get_tempfilename(a:jobinfo)
        if !empty(temp_file)
            call neomake#utils#DebugMessage(printf(
                        \ 'Using tempfile for unreadable buffer: %s', temp_file),
                        \ a:jobinfo)
        else
            throw 'Neomake: file is not readable ('.fnamemodify(bufname, ':p').')'
        endif
    else
        let bufname = fnamemodify(bufname, ':p')
    endif

    if !empty(temp_file)
        let temp_dir = fnamemodify(temp_file, ':h')
        if !isdirectory(temp_dir)
            call mkdir(temp_dir, 'p', 0750)
        endif
        let make_info = s:make_info[a:jobinfo.make_id]
        if !has_key(make_info, 'tempfile')
            let make_info.tempfile = temp_file
            call neomake#utils#write_tempfile(bufnr, temp_file)
        elseif temp_file !=# make_info.tempfile
            call writefile(readfile(make_info.tempfile, 'b'), temp_file, 'b')
        endif
        let bufname = temp_file
    endif
    let a:jobinfo.filename = bufname
    return bufname
endfunction

function! s:command_maker_base._bind_args() abort dict
    " Resolve args, which might be a function or dictionary.
    if type(self.args) == type(function('tr'))
        let args = call(self.args, [])
    elseif type(self.args) == type({})
        let args = call(self.args.fn, [], self.args)
    else
        let args = copy(self.args)
    endif
    let args_is_list = type(args) == type([])
    if args_is_list
        call neomake#utils#ExpandArgs(args)
    endif
    let self.args = args
endfunction

function! s:command_maker_base._get_argv(jobinfo) abort dict
    " Resolve exe, which might be a function or dictionary.
    if type(self.exe) == type(function('tr'))
        let exe = call(self.exe, [])
    elseif type(self.exe) == type({})
        let exe = call(self.exe.fn, [], self.exe)
    else
        let exe = self.exe
    endif

    let args = copy(self.args)
    let args_is_list = type(args) == type([])

    if a:jobinfo.file_mode && neomake#utils#GetSetting('append_file', self, 1, a:jobinfo.ft, a:jobinfo.bufnr)
        let filename = self._get_fname_for_buffer(a:jobinfo)
        if args_is_list
            call add(args, filename)
        else
            let args .= ' '.fnameescape(filename)
        endif
    endif

    if has('nvim')
        if args_is_list
            let argv = [exe] + args
        else
            let argv = exe . (!empty(args) ? ' ' . args : '')
        endif
    elseif neomake#has_async_support()
        " Vim jobs, need special treatment on Windows..
        if neomake#utils#IsRunningWindows()
            " Windows needs a subshell to handle PATH/%PATHEXT% etc.
            if args_is_list
                let argv = join(map(copy([exe] + args), 'neomake#utils#shellescape(v:val)'))
            else
                let argv = exe.' '.args
            endif
            let argv = &shell.' '.&shellcmdflag.' '.argv

        elseif !args_is_list
            " Use a shell to handle argv properly (Vim splits at spaces).
            let argv = [&shell, &shellcmdflag, exe.' '.args]
        else
            let argv = [exe] + args
        endif
    else
        " Vim-async, via system().
        if args_is_list
            let argv = join(map(copy([exe] + args), 'neomake#utils#shellescape(v:val)'))
        else
            let argv = exe.' '.args
        endif
    endif
    return argv
endfunction

function! neomake#GetMaker(name_or_maker, ...) abort
    if a:0
        let file_mode = 1
        let ft = a:1
    else
        let file_mode = 0
        let ft = ''
    endif
    if type(a:name_or_maker) == type({})
        let maker = a:name_or_maker
    elseif a:name_or_maker ==# 'makeprg'
        let maker = neomake#utils#MakerFromCommand(&makeprg)
    elseif a:name_or_maker !~# '\v^\w+$'
        call neomake#utils#ErrorMessage('Invalid maker name: '.a:name_or_maker)
        return {}
    else
        let maker = neomake#utils#GetSetting('maker', {'name': a:name_or_maker}, s:unset_dict, ft, bufnr('%'))
        if maker is# s:unset_dict
            if file_mode
                for config_ft in neomake#utils#get_config_fts(ft)
                    call neomake#utils#load_ft_maker(config_ft)
                    let f = 'neomake#makers#ft#'.config_ft.'#'.a:name_or_maker
                    if exists('*'.f)
                        let maker = call(f, [])
                        break
                    endif
                endfor
            else
                try
                    let maker = eval('neomake#makers#'.a:name_or_maker.'#'.a:name_or_maker.'()')
                catch /^Vim\%((\a\+)\)\=:E117/
                endtry
            endif
        endif
        if maker is# s:unset_dict
            if file_mode
                throw printf('Neomake: Maker not found (for %s): %s',
                            \ !empty(ft) ? 'filetype '.ft : 'empty filetype',
                            \ a:name_or_maker)
            else
                throw 'Neomake: project maker not found: '.a:name_or_maker
            endif
        endif
    endif

    " Create the maker object.
    let bufnr = bufnr('%')
    let GetEntries = neomake#utils#GetSetting('get_list_entries', maker, -1, ft, bufnr)
    if GetEntries isnot# -1
        let maker = extend(copy(s:maker_base), copy(maker))
        let maker.get_list_entries = GetEntries
    else
        let maker = extend(copy(s:command_maker_base), copy(maker))
    endif
    if !has_key(maker, 'name')
        if type(a:name_or_maker) == type('')
            let maker.name = a:name_or_maker
        else
            let maker.name = 'unnamed_maker'
        endif
    endif
    if !has_key(maker, 'get_list_entries')
        " Set defaults for command/job based makers.
        let defaults = copy(s:maker_defaults)
        call extend(defaults, {
            \ 'exe': maker.name,
            \ 'args': [],
            \ 'errorformat': &errorformat,
            \ })
        for [key, default] in items(defaults)
            let maker[key] = neomake#utils#GetSetting(key, maker, default, ft, bufnr)
            unlet! default  " workaround for old Vim (7.3.429)
        endfor
    endif
    return maker
endfunction

function! s:get_makers_for_pattern(pattern) abort
    if exists('*getcompletion')
        " Get function prefix based on pattern, until the first backslash.
        let prefix = substitute(a:pattern, '\v\\.*', '', '')

        " NOTE: the pattern uses &ignorecase.
        let funcs = getcompletion(prefix.'[a-z]', 'function')
        call filter(funcs, 'v:val =~# a:pattern')
        " Remove prefix.
        call map(funcs, 'v:val['.len(prefix).':]')
        " Only keep lowercase function names.
        call filter(funcs, "v:val =~# '\\m^[a-z].*('")
        " Remove parenthesis and #.* (for project makers).
        return sort(map(funcs, "substitute(v:val, '\\v[(#].*', '', '')"))
    endif

    let funcs_output = neomake#utils#redir('fun /'.a:pattern)
    return sort(map(split(funcs_output, '\n'),
                \ "substitute(v:val, '\\v^.*#(.*)\\(.*$', '\\1', '')"))
endfunction

function! neomake#GetMakers(ft) abort
    " Get all makers for a given filetype.  This is used from completion.
    " XXX: this should probably use a callback or some other more stable
    " approach to get the list of makers (than looking at the lowercase
    " functions)?!

    let makers = []
    for ft in neomake#utils#get_config_fts(a:ft)
        call neomake#utils#load_ft_maker(ft)

        let maker_names = s:get_makers_for_pattern('neomake#makers#ft#'.ft.'#\l')
        for maker_name in maker_names
            if index(makers, maker_name) == -1
                let makers += [maker_name]
            endif
        endfor
        for v in extend(keys(g:), keys(b:))
            let maker_name = matchstr(v, '\v^neomake_'.ft.'_\zs\l+\ze_maker$')
            if !empty(maker_name)
                let makers += [maker_name]
            endif
        endfor
    endfor
    return makers
endfunction

function! neomake#GetProjectMakers() abort
    runtime! autoload/neomake/makers/*.vim
    return s:get_makers_for_pattern('neomake#makers#\(ft#\)\@!\l')
endfunction

function! neomake#GetEnabledMakers(...) abort
    let file_mode = a:0
    if !file_mode
        " If we have no filetype, use the global default makers.
        " This variable is also used for project jobs, so it has no
        " buffer local ('b:') counterpart for now.
        let enabled_makers = copy(get(g:, 'neomake_enabled_makers', []))
        call map(enabled_makers, "extend(neomake#GetMaker(v:val),
                    \ {'auto_enabled': 0}, 'error')")
    else
        let enabled_makers = []
        let makers = neomake#utils#GetSetting('enabled_makers', {}, s:unset_list, a:1, bufnr('%'))
        if makers is# s:unset_list
            let auto_enabled = 1
            for config_ft in neomake#utils#get_config_fts(a:1)
                call neomake#utils#load_ft_maker(config_ft)
                let fnname = 'neomake#makers#ft#'.config_ft.'#EnabledMakers'
                if exists('*'.fnname)
                    let makers = call(fnname, [])
                    break
                endif
            endfor
        else
            let auto_enabled = 0
        endif

        for m in makers
            try
                let maker = neomake#GetMaker(m, a:1)
            catch /^Neomake: /
                let error = substitute(v:exception, '^Neomake: ', '', '')
                let jobinfo = {}
                if has_key(s:make_info, s:make_id)
                    let jobinfo.make_id = s:make_id
                endif
                if auto_enabled
                    call neomake#utils#DebugMessage(error, jobinfo)
                else
                    call neomake#utils#ErrorMessage(error, jobinfo)
                endif
                continue
            endtry
            let maker.auto_enabled = auto_enabled
            let enabled_makers += [maker]
        endfor
    endif
    return enabled_makers
endfunction

function! s:HandleLoclistQflistDisplay(file_mode) abort
    let open_val = get(g:, 'neomake_open_list')
    if open_val
        let height = get(g:, 'neomake_list_height', 10)
        let win_val = winnr()
        if a:file_mode
            exe 'lwindow' height
        else
            exe 'cwindow' height
        endif
        if open_val == 2 && win_val != winnr()
            wincmd p
        endif
    endif
endfunction

function! s:Make(options) abort
    let s:make_id += 1
    let make_id = s:make_id
    let options = copy(a:options)
    call extend(options, {
                \ 'file_mode': 1,
                \ 'bufnr': bufnr('%'),
                \ 'ft': '',
                \ 'make_id': make_id,
                \ }, 'keep')
    let bufnr = options.bufnr
    let file_mode = options.file_mode

    let s:make_info[make_id] = {
                \ 'cwd': getcwd(),
                \ 'verbosity': get(g:, 'neomake_verbose', 1),
                \ 'active_jobs': 0,
                \ 'finished_jobs': 0,
                \ 'options': options,
                \ }
    let make_info = s:make_info[make_id]
    if &verbose
        let make_info.verbosity += &verbose
        call neomake#utils#DebugMessage(printf(
                    \ 'Adding &verbose (%d) to verbosity level: %d',
                    \ &verbose, make_info.verbosity),
                    \ {'make_id': make_id})
    endif

    if has_key(options, 'enabled_makers')
        let makers = options.enabled_makers
        unlet options.enabled_makers
    else
        let makers = call('neomake#GetEnabledMakers', file_mode ? [options.ft] : [])
        if empty(makers)
            if file_mode
                call neomake#utils#DebugMessage('Nothing to make: no enabled file mode makers (filetype='.options.ft.').', {'make_id': make_id})
                call s:clean_make_info(make_id)
                return []
            else
                let makers = ['makeprg']
            endif
        endif
    endif

    " Instantiate all makers in the beginning (so expand() gets used in
    " the current buffer's context).
    let args = [options, makers]
    if file_mode
        let args += [options.ft]
    endif
    lockvar options
    let jobs = call('s:map_makers', args)
    if empty(jobs)
        call neomake#utils#DebugMessage('Nothing to make: no valid makers.')
        call s:clean_make_info(make_id)
        return []
    endif

    let maker_info = join(map(copy(jobs),
                \ "v:val.maker.name . (get(v:val.maker, 'auto_enabled', 0) ? ' (auto)' : '')"), ', ')
    let log_context = {'make_id': make_id}
    if file_mode
        let log_context.bufnr = bufnr
    endif
    call neomake#utils#DebugMessage(printf(
                \ 'Running makers: %s', maker_info), log_context)

    let make_info.jobs_queue = jobs

    if file_mode
        " XXX: this clears counts for job's buffer only, but we add counts for
        " the entry's buffers, which might be different!
        call neomake#statusline#ResetCountsForBuf(bufnr)
    else
        call neomake#statusline#ResetCountsForProject()
    endif

    call s:AddMakeInfoForCurrentWin(make_id)

    " TODO: return jobinfos?!
    let job_ids = []
    while 1
        let jobinfo = s:handle_next_maker({})
        if empty(jobinfo)
            break
        endif
        let job_id = jobinfo.id
        if job_id >= 0
            call add(job_ids, job_id)
        endif
        if get(jobinfo, 'serialize', 0)
            break
        endif
    endwhile

    if has_key(s:make_info, make_id) && !s:make_info[make_id].active_jobs
        " Might have been removed through s:CleanJobinfo already.
        call s:clean_make_info(make_id)
    endif
    return job_ids
endfunction

function! s:AddExprCallback(jobinfo, prev_index) abort
    let maker = a:jobinfo.maker
    let file_mode = a:jobinfo.file_mode
    let list = file_mode ? getloclist(0) : getqflist()
    let list_modified = 0
    let index = a:prev_index
    unlet! s:postprocess  " vim73
    let s:postprocess = get(maker, 'postprocess', function('neomake#utils#CompressWhitespace'))
    if type(s:postprocess) != type([])
        let s:postprocessors = [s:postprocess]
    else
        let s:postprocessors = s:postprocess
    endif
    let debug = neomake#utils#get_verbosity(a:jobinfo) >= 3
    let make_info = s:make_info[a:jobinfo.make_id]

    let entries = []
    while index < len(list)
        let entry = list[index]
        let entry.maker_name = has_key(maker, 'name') ? maker.name : 'makeprg'
        let index += 1

        let before = copy(entry)
        if file_mode && has_key(make_info, 'tempfile')
            let entry.bufnr = a:jobinfo.bufnr
        endif
        if !empty(s:postprocessors)
            let g:neomake_hook_context = {'jobinfo': a:jobinfo}
            for s:f in s:postprocessors
                if type(s:f) == type({})
                    call call(s:f.fn, [entry], s:f)
                else
                    call call(s:f, [entry], maker)
                endif
                unlet! s:f  " vim73
            endfor
            unlet! g:neomake_hook_context  " Might be unset already with sleep in postprocess.
        endif
        if entry != before
            let list_modified = 1
            if debug
                call neomake#utils#DebugMessage(printf(
                  \ 'Modified list entry (postprocess): %s',
                  \ join(values(map(neomake#utils#diff_dict(before, entry)[0],
                  \ "v:key.': '.string(v:val[0]).' => '.string(v:val[1])")))))

            endif
        endif

        if entry.valid <= 0
            if entry.valid < 0 || maker.remove_invalid_entries
                let index -= 1
                call remove(list, index)
                let list_modified = 1
                let entry_copy = copy(entry)
                call neomake#utils#DebugMessage(printf(
                            \ 'Removing invalid entry: %s (%s)',
                            \ remove(entry_copy, 'text'),
                            \ string(entry_copy)), a:jobinfo)
            endif
            continue
        endif

        call add(entries, entry)
    endwhile

    if list_modified
        if file_mode
            call setloclist(0, list, 'r')
        else
            call setqflist(list, 'r')
        endif
    endif

    return entries
endfunction

function! s:CleanJobinfo(jobinfo) abort
    if get(a:jobinfo, 'pending_output', 0) && !get(a:jobinfo, 'canceled', 0)
        call neomake#utils#DebugMessage(
                    \ 'Output left to be processed, not cleaning job yet.', a:jobinfo)
        return
    endif
    call neomake#utils#DebugMessage('Cleaning jobinfo', a:jobinfo)

    let make_info = s:make_info[a:jobinfo.make_id]

    if has_key(s:jobs, get(a:jobinfo, 'id', -1))
        call remove(s:jobs, a:jobinfo.id)
        let make_info.active_jobs -= 1

        let [t, w] = s:GetTabWinForMakeId(a:jobinfo.make_id)
        let jobs_output = s:gettabwinvar(t, w, 'neomake_jobs_output', {})
        if has_key(jobs_output, a:jobinfo.id)
            unlet jobs_output[a:jobinfo.id]
        endif
        if has_key(s:project_job_output, a:jobinfo.id)
            unlet s:project_job_output[a:jobinfo.id]
        endif
    endif

    if !get(a:jobinfo, 'canceled', 0)
                \ && !get(a:jobinfo, 'failed_to_start', 0)
        call neomake#utils#hook('NeomakeJobFinished', {'jobinfo': a:jobinfo})
        let make_info.finished_jobs += 1
    endif

    " Trigger autocmd if all jobs for a s:Make instance have finished.
    if make_info.active_jobs
        return
    endif

    if !empty(s:make_info[a:jobinfo.make_id].jobs_queue)
        return
    endif

    if make_info.finished_jobs
        call s:init_job_output(a:jobinfo)

        " If signs were not cleared before this point, then the maker did not return
        " any errors, so all signs must be removed
        if a:jobinfo.file_mode
            call neomake#CleanOldFileSignsAndErrors(a:jobinfo.bufnr)
        else
            call neomake#CleanOldProjectSignsAndErrors()
        endif

        call neomake#utils#hook('NeomakeFinished', {
                    \ 'file_mode': a:jobinfo.file_mode,
                    \ 'make_id': a:jobinfo.make_id,
                    \ 'jobinfo': a:jobinfo})
    endif

    call s:clean_make_info(a:jobinfo.make_id)
endfunction

function! s:clean_make_info(make_id) abort
    " Remove make_id from its window.
    let [t, w] = s:GetTabWinForMakeId(a:make_id)
    let make_ids = s:gettabwinvar(t, w, 'neomake_make_ids', [])
    let idx = index(make_ids, a:make_id)
    if idx != -1
        call remove(make_ids, idx)
        call settabwinvar(t, w, 'neomake_make_ids', make_ids)
    endif

    let tempfile = get(s:make_info[a:make_id], 'tempfile')
    if !empty(tempfile)
        call neomake#utils#DebugMessage(printf('Removing temporary file: %s',
                    \ tempfile))
        call delete(tempfile)
        " Only delete the dir, if Vim supports it.  It will be cleaned up
        " when quitting Vim in any case.
        if v:version >= 705 || (v:version == 704 && has('patch1107'))
            call delete(fnamemodify(tempfile, ':h'), 'd')
        endif
    endif

    unlet s:make_info[a:make_id]
endfunction

function! s:CanProcessJobOutput() abort
    " We can only process output (change the location/quickfix list) in
    " certain modes, otherwise e.g. the visual selection gets lost.
    if index(['n', 'i'], mode()) == -1
        call neomake#utils#DebugMessage('Not processing output for mode '.mode())
    elseif exists('*getcmdwintype') && getcmdwintype() !=# ''
        call neomake#utils#DebugMessage('Not processing output from command-line window '.getcmdwintype())
    else
        return 1
    endif
    return 0
endfunction

function! s:init_job_output(jobinfo) abort
    if get(s:make_info[a:jobinfo.make_id], 'initialized_for_output', 0)
        return
    endif

    " Empty the quickfix/location list (using a valid 'errorformat' setting).
    let l:efm = &errorformat
    try
        let &errorformat = '%-G'
        if a:jobinfo.file_mode
            lgetexpr ''
        else
            cgetexpr ''
        endif
    finally
        let &errorformat = l:efm
    endtry
    call s:HandleLoclistQflistDisplay(a:jobinfo.file_mode)

    if a:jobinfo.file_mode
        if g:neomake_place_signs
            call neomake#signs#ResetFile(a:jobinfo.bufnr)
        endif
        let s:need_errors_cleaning['file'][a:jobinfo.bufnr] = 1
    else
        if g:neomake_place_signs
            call neomake#signs#ResetProject()
        endif
        let s:need_errors_cleaning['project'] = 1
    endif
    let s:make_info[a:jobinfo.make_id].initialized_for_output = 1
endfunction

function! s:ProcessEntries(jobinfo, entries, ...) abort
    let file_mode = a:jobinfo.file_mode

    if a:0
        let prev_list = a:1
    else
        " Fix entries with get_list_entries/process_output.
        call map(a:entries, 'extend(v:val, {'
                    \ . "'bufnr': str2nr(get(v:val, 'bufnr', a:jobinfo.bufnr)),"
                    \ . "'lnum': str2nr(v:val.lnum),"
                    \ . "'col': str2nr(get(v:val, 'col', 0)),"
                    \ . "'vcol': str2nr(get(v:val, 'vcol', 0)),"
                    \ . "'type': get(v:val, 'type', 'E'),"
                    \ . "'nr': get(v:val, 'nr', -1),"
                    \ . "'maker_name': a:jobinfo.maker.name,"
                    \ . '})')

        call s:init_job_output(a:jobinfo)
        let prev_list = file_mode ? getloclist(0) : getqflist()
        if file_mode
            call setloclist(0, a:entries, 'a')
        else
            call setqflist(a:entries, 'a')
        endif
    endif

    let counts_changed = 0
    let cleaned_signs = []
    let ignored_signs = []
    let maker_type = file_mode ? 'file' : 'project'
    let do_highlight = get(g:, 'neomake_highlight_columns', 1)
                \ || get(g:, 'neomake_highlight_lines', 0)
    for entry in a:entries
        if !file_mode
            if neomake#statusline#AddQflistCount(entry)
                let counts_changed = 1
            endif
        endif

        if !entry.bufnr
            continue
        endif

        if file_mode
            if neomake#statusline#AddLoclistCount(entry.bufnr, entry)
                let counts_changed = 1
            endif
        endif

        if index(cleaned_signs, entry.bufnr) == -1
            if file_mode
                call neomake#CleanOldFileSignsAndErrors(entry.bufnr)
            else
                call neomake#CleanOldProjectSignsAndErrors()
            endif
            call add(cleaned_signs, entry.bufnr)
        endif

        " Track all errors by buffer and line
        let s:current_errors[maker_type][entry.bufnr] = get(s:current_errors[maker_type], entry.bufnr, {})
        let s:current_errors[maker_type][entry.bufnr][entry.lnum] = get(
            \ s:current_errors[maker_type][entry.bufnr], entry.lnum, [])
        call add(s:current_errors[maker_type][entry.bufnr][entry.lnum], entry)

        if g:neomake_place_signs
            if entry.lnum is 0
                let ignored_signs += [entry]
            else
                call neomake#signs#PlaceSign(entry, maker_type)
            endif
        endif
        if do_highlight
            call neomake#highlights#AddHighlight(entry, maker_type)
        endif
    endfor

    if !empty(ignored_signs)
        call neomake#utils#DebugMessage(printf(
                    \ 'Could not place signs for %d entries without line number: %s.',
                    \ len(ignored_signs), string(ignored_signs)))
    endif

    if !counts_changed
        let counts_changed = (file_mode && getloclist(0) != prev_list)
                    \ || (!file_mode && getqflist() != prev_list)
    endif
    if counts_changed
        call neomake#utils#hook('NeomakeCountsChanged', {
                    \ 'file_mode': file_mode,
                    \ 'bufnr': a:jobinfo.bufnr,
                    \ 'jobinfo': a:jobinfo})
    endif

    call s:HandleLoclistQflistDisplay(a:jobinfo.file_mode)
    call neomake#highlights#ShowHighlights()
    call neomake#EchoCurrentError()
endfunction

function! s:ProcessJobOutput(jobinfo, lines, source) abort
    let maker = a:jobinfo.maker
    let file_mode = a:jobinfo.file_mode

    call neomake#utils#DebugMessage(printf(
                \ '%s: processing %d lines of output.',
                \ maker.name, len(a:lines)), a:jobinfo)

    if has_key(maker, 'process_output')
        let entries = call(maker.process_output, [{
                    \ 'output': a:lines,
                    \ 'source': a:source,
                    \ 'jobinfo': a:jobinfo}])
        call s:ProcessEntries(a:jobinfo, entries)
        return
    endif

    call s:init_job_output(a:jobinfo)

    " Old-school handling through errorformat.
    let prev_list = file_mode ? getloclist(0) : getqflist()
    if has_key(maker, 'mapexpr')
        let l:neomake_bufname = bufname(a:jobinfo.bufnr)
        " @vimlint(EVL102, 1, l:neomake_bufdir)
        let l:neomake_bufdir = fnamemodify(neomake_bufname, ':h')
        " @vimlint(EVL102, 1, l:neomake_output_source)
        let l:neomake_output_source = a:source
        call map(a:lines, maker.mapexpr)
    endif

    let olderrformat = &errorformat
    let &errorformat = maker.errorformat
    try
        if file_mode
            laddexpr a:lines
        else
            caddexpr a:lines
        endif
    finally
        let &errorformat = olderrformat
    endtry

    let entries = s:AddExprCallback(a:jobinfo, len(prev_list))
    call s:ProcessEntries(a:jobinfo, entries, prev_list)
endfunction

function! neomake#ProcessCurrentWindow() abort
    if s:CanProcessJobOutput()
        let outputs = get(w:, 'neomake_jobs_output', {})
        if !empty(outputs)
            unlet w:neomake_jobs_output
            call s:ProcessPendingOutput(outputs)
        endif
    endif
endfunction

function! s:ProcessPendingOutput(outputs) abort
    for job_id in sort(keys(a:outputs), 'N')
        let output = a:outputs[job_id]
        let jobinfo = s:jobs[job_id]
        for [source, lines] in items(output)
            call s:ProcessJobOutput(jobinfo, lines, source)
        endfor

        if jobinfo.file_mode
            call filter(s:buffer_job_output[jobinfo.bufnr], 'v:val != job_id')
        else
            unlet a:outputs[job_id]
        endif

        if has_key(jobinfo, 'pending_output')
            if !s:has_pending_output(jobinfo)
                call neomake#utils#DebugMessage('Processed pending output', jobinfo)
                let jobinfo.pending_output = 0
                call s:CleanJobinfo(jobinfo)
            endif
        endif
    endfor
endfunction

function! neomake#ProcessPendingOutput() abort
    if !s:CanProcessJobOutput()
        return
    endif
    call neomake#ProcessCurrentWindow()
    if !empty(s:project_job_output)
        call s:ProcessPendingOutput(s:project_job_output)
    endif
    call neomake#highlights#ShowHighlights()
endfunction

" Get tabnr and winnr for a given job ID.
function! s:GetTabWinForMakeId(make_id) abort
    for t in [tabpagenr()] + range(1, tabpagenr()-1) + range(tabpagenr()+1, tabpagenr('$'))
        for w in range(1, tabpagewinnr(t, '$'))
            if index(s:gettabwinvar(t, w, 'neomake_make_ids', []), a:make_id) != -1
                return [t, w]
            endif
        endfor
    endfor
    return [-1, -1]
endfunction

" Returns 1 when output has been registered (needs further processing).
function! s:RegisterJobOutput(jobinfo, lines, source) abort
    if !a:jobinfo.file_mode
        if s:CanProcessJobOutput()
            call s:ProcessJobOutput(a:jobinfo, a:lines, a:source)
            return 0
        else
            if !exists('s:project_job_output[a:jobinfo.id]')
                let s:project_job_output[a:jobinfo.id] = {}
            endif
            if !exists('s:project_job_output[a:jobinfo.id][a:source]')
                let s:project_job_output[a:jobinfo.id][a:source] = []
            endif
            let s:project_job_output[a:jobinfo.id][a:source] += a:lines
        endif
        return 1
    endif

    " Process the window directly if we can.
    if s:CanProcessJobOutput() && index(get(w:, 'neomake_make_ids', []), a:jobinfo.make_id) != -1
        call s:ProcessJobOutput(a:jobinfo, a:lines, a:source)
        call neomake#highlights#ShowHighlights()
        return 0
    endif

    " file mode: append lines to jobs's window's output.
    let [t, w] = s:GetTabWinForMakeId(a:jobinfo.make_id)
    if w == -1
        call neomake#utils#LoudMessage('No window found for output!', a:jobinfo)
        return 0
    endif
    let w_output = s:gettabwinvar(t, w, 'neomake_jobs_output', {})
    if !has_key(w_output, a:jobinfo.id)
        let w_output[a:jobinfo.id] = {}
    endif
    if !has_key(w_output[a:jobinfo.id], a:source)
        let w_output[a:jobinfo.id][a:source] = []

        if !exists('s:buffer_job_output[a:jobinfo.bufnr]')
            let s:buffer_job_output[a:jobinfo.bufnr] = []
        endif
        let s:buffer_job_output[a:jobinfo.bufnr] += [a:jobinfo.id]
    endif
    let w_output[a:jobinfo.id][a:source] += a:lines
    call settabwinvar(t, w, 'neomake_jobs_output', w_output)
    return 1
endfunction

function! s:vim_output_handler(channel, output, event_type) abort
    let job_id = ch_info(a:channel)['id']
    let jobinfo = s:jobs[job_id]

    let data = split(a:output, '\v\r?\n', 1)

    if exists('jobinfo._vim_in_handler')
        call neomake#utils#DebugMessage(printf('Queueing: %s: %s: %s',
                    \ a:event_type, jobinfo.maker.name, string(data)), jobinfo)
        let jobinfo._vim_in_handler += [[job_id, data, a:event_type]]
        return
    else
        let jobinfo._vim_in_handler = []
    endif

    call s:output_handler(job_id, data, a:event_type)

    " Process queued events that might have arrived by now.
    " The attribute might be unset here, since output_handler might have
    " been interrupted.
    if exists('jobinfo._vim_in_handler')
        while has_key(jobinfo, '_vim_in_handler') && !empty(jobinfo._vim_in_handler)
            let args = remove(jobinfo._vim_in_handler, 0)
            call call('s:output_handler', args)
        endwhile
        unlet! jobinfo._vim_in_handler
        " call neomake#utils#DebugMessage('Queued events processed', jobinfo)

        " Trigger previously delayed exit handler.
        if exists('jobinfo._exited_while_in_handler')
            call neomake#utils#DebugMessage('Trigger delayed exit', jobinfo)
            call s:exit_handler(jobinfo.id, jobinfo._exited_while_in_handler, 'exit')
        endif
    endif
endfunction

function! s:vim_output_handler_stdout(channel, output) abort
    call s:vim_output_handler(a:channel, a:output, 'stdout')
endfunction

function! s:vim_output_handler_stderr(channel, output) abort
    call s:vim_output_handler(a:channel, a:output, 'stderr')
endfunction

function! s:vim_exit_handler(channel) abort
    let job_info = job_info(ch_getjob(a:channel))
    let job_id = ch_info(a:channel)['id']

    " Handle failing starts from Vim here.
    let status = job_info['exitval']
    if status == 122  " Vim uses EXEC_FAILED, but only on Unix?!
        let jobinfo = s:jobs[job_id]
        let jobinfo.failed_to_start = 1
        " The error is on stderr.
        let error = 'Vim job failed to run: '.substitute(join(jobinfo.stderr), '\v\s+$', '', '')
        let jobinfo.stderr = []
        call neomake#utils#ErrorMessage(error)
        call s:CleanJobinfo(jobinfo)
    else
        call s:exit_handler(job_id, status, 'exit')
    endif
endfunction

function! s:has_pending_output(jobinfo) abort
    if index(get(s:buffer_job_output, a:jobinfo.bufnr, []), a:jobinfo.id) != -1
        return 1
    endif
    if has_key(s:project_job_output, a:jobinfo.id)
        return 1
    endif
    return 0
endfunction

" Noevim: register output from jobs as quick as possible, and trigger its
" processing through a timer.
" This works around https://github.com/neovim/neovim/issues/5889).
" NOTE: can be skipped with Neovim 0.2.0+.
let s:nvim_output_handler_queue = []
function! s:nvim_output_handler(job_id, data, event_type) abort
    let data = map(copy(a:data), "substitute(v:val, '\\r$', '', '')")
    " @vimlint(EVL108, 1)
    if has('nvim-0.2.0')
        call s:output_handler(a:job_id, data, a:event_type)
        return
    endif
    " @vimlint(EVL108, 0)
    let jobinfo = s:jobs[a:job_id]
    let args = [a:job_id, data, a:event_type]
    call add(s:nvim_output_handler_queue, args)
    if !exists('jobinfo._nvim_in_handler')
        let jobinfo._nvim_in_handler = 1
    else
        let jobinfo._nvim_in_handler += 1
    endif
    if !exists('s:nvim_output_handler_timer')
        let s:nvim_output_handler_timer = timer_start(0, function('s:nvim_output_handler_cb'))
    endif
endfunction

" @vimlint(EVL103, 1, a:timer)
function! s:nvim_output_handler_cb(timer) abort
    while !empty(s:nvim_output_handler_queue)
        let args = remove(s:nvim_output_handler_queue, 0)
        let job_id = args[0]
        let jobinfo = s:jobs[job_id]
        call call('s:output_handler', args)
        let jobinfo._nvim_in_handler -= 1

        if !jobinfo._nvim_in_handler
            " Trigger previously delayed exit handler.
            unlet jobinfo._nvim_in_handler
            if exists('jobinfo._exited_while_in_handler')
                call neomake#utils#DebugMessage('Trigger delayed exit', jobinfo)
                call s:exit_handler(jobinfo.id, jobinfo._exited_while_in_handler, 'exit')
            endif
        endif
    endwhile
    unlet! s:nvim_output_handler_timer
endfunction
" @vimlint(EVL103, 0, a:timer)

function! s:exit_handler(job_id, data, event_type) abort
    if !has_key(s:jobs, a:job_id)
        call neomake#utils#QuietMessage('exit: job not found: '.string(a:job_id))
        return
    endif
    let jobinfo = s:jobs[a:job_id]
    if get(jobinfo, 'canceled')
        call neomake#utils#DebugMessage('exit: job was canceled.', jobinfo)
        call s:CleanJobinfo(jobinfo)
        return
    endif
    let maker = jobinfo.maker

    if exists('jobinfo._vim_in_handler') || exists('jobinfo._nvim_in_handler')
        let jobinfo._exited_while_in_handler = a:data
        call neomake#utils#DebugMessage(printf('exit (delayed): %s: %s',
                    \ maker.name, string(a:data)), jobinfo)
        return
    endif
    call neomake#utils#DebugMessage(printf('%s: %s: %s',
                \ a:event_type, maker.name, string(a:data)), jobinfo)

    " Handle any unfinished lines from stdout/stderr callbacks.
    let has_pending_output = 0
    for event_type in ['stdout', 'stderr']
        if has_key(jobinfo, event_type)
            let lines = jobinfo[event_type]
            if !empty(lines)
                if lines[-1] ==# ''
                    call remove(lines, -1)
                endif
                if !empty(lines)
                    if s:RegisterJobOutput(jobinfo, lines, event_type)
                        let has_pending_output = 1
                    endif
                endif
                unlet jobinfo[event_type]
            endif
        endif
    endfor

    let status = a:data
    let jobinfo.exit_code = a:data
    if !get(jobinfo, 'failed_to_start')
        let l:ExitCallback = neomake#utils#GetSetting('exit_callback',
                    \ extend(copy(jobinfo), maker), 0, jobinfo.ft, jobinfo.bufnr)
        if l:ExitCallback isnot# 0
            let callback_dict = { 'status': status,
                                \ 'name': maker.name,
                                \ 'has_next': !empty(s:make_info[jobinfo.make_id].jobs_queue) }
            if type(l:ExitCallback) == type('')
                let l:ExitCallback = function(l:ExitCallback)
            endif
            try
                call call(l:ExitCallback, [callback_dict], jobinfo)
            catch /^Vim\%((\a\+)\)\=:E117/
            endtry
        endif
    endif

    if neomake#has_async_support()
        if has('nvim') || status != 122
            call neomake#utils#DebugMessage(printf(
                        \ '%s: completed with exit code %d.',
                        \ maker.name, status), jobinfo)
        endif
        if has_pending_output || s:has_pending_output(jobinfo)
            let jobinfo.pending_output = 1
            let jobinfo.finished = 1
        endif
    endif
    call s:handle_next_maker(jobinfo)
endfunction

function! s:output_handler(job_id, data, event_type) abort
    let jobinfo = s:jobs[a:job_id]

    call neomake#utils#DebugMessage(printf('%s: %s: %s',
                \ a:event_type, jobinfo.maker.name, string(a:data)), jobinfo)
    if get(jobinfo, 'canceled')
        call neomake#utils#DebugMessage('Ignoring output, job was canceled.', jobinfo)
        return
    endif
    let last_event_type = get(jobinfo, 'event_type', a:event_type)

    " a:data is a list of 'lines' read. Each element *after* the first
    " element represents a newline.
    if has_key(jobinfo, a:event_type)
        let lines = jobinfo[a:event_type]
        " As per https://github.com/neovim/neovim/issues/3555
        let jobinfo[a:event_type] = lines[:-2]
                    \ + [lines[-1] . get(a:data, 0, '')]
                    \ + a:data[1:]
    else
        let jobinfo[a:event_type] = a:data
    endif

    if !jobinfo.maker.buffer_output || last_event_type !=# a:event_type
        let lines = jobinfo[a:event_type][:-2]
        let jobinfo[a:event_type] = jobinfo[a:event_type][-1:]

        if !empty(lines)
            call s:RegisterJobOutput(jobinfo, lines, a:event_type)
        endif
    endif
endfunction

function! s:abort_next_makers(make_id) abort
    let jobs_queue = s:make_info[a:make_id].jobs_queue
    if !empty(jobs_queue)
        let next_makers = '['.join(map(copy(jobs_queue), 'v:val.maker.name'), ', ').']'
        call neomake#utils#LoudMessage('Aborting next makers '.next_makers)
        let s:make_info[a:make_id].jobs_queue = []
    endif
endfunction

function! s:handle_next_maker(prev_jobinfo) abort
    let make_id = get(a:prev_jobinfo, 'make_id', s:make_id)
    if !has_key(s:make_info, make_id)
        return {}
    endif
    let make_info = s:make_info[make_id]

    if !empty(a:prev_jobinfo)
        let status = get(a:prev_jobinfo, 'exit_code', 0)
        if status != 0 && index([122, 127], status) == -1
            if neomake#utils#GetSetting('serialize_abort_on_error', a:prev_jobinfo.maker, 0, a:prev_jobinfo.ft, a:prev_jobinfo.bufnr)
                call s:abort_next_makers(make_id)
                call s:CleanJobinfo(a:prev_jobinfo)
                return {}
            endif
        endif
        call s:CleanJobinfo(a:prev_jobinfo)
        if !has_key(s:make_info, make_id)
            " Last job was cleaned.
            return {}
        endif
    endif

    while !empty(make_info.jobs_queue)
        let options = remove(make_info.jobs_queue, 0)
        let maker = options.maker
        if empty(maker)
            continue
        endif

        " Serialization of jobs, always for non-async Vim.
        if !neomake#has_async_support()
                    \ || neomake#utils#GetSetting('serialize', maker, 0, options.ft, options.bufnr)
            let options.serialize = 1
        endif

        try
            let jobinfo = s:MakeJob(make_id, options)
            if !empty(jobinfo)
                return jobinfo
            endif
        catch /^Neomake: /
            let error = substitute(v:exception, '^Neomake: ', '', '')
            call neomake#utils#ErrorMessage(error, {'make_id': make_id})

            if get(options, 'serialize', 0)
                        \ && neomake#utils#GetSetting('serialize_abort_on_error', maker, 0, options.ft, options.bufnr)
                call s:abort_next_makers(make_id)
                break
            endif
            continue
        endtry
    endwhile
    return {}
endfunction

function! neomake#CleanOldProjectSignsAndErrors() abort
    if s:need_errors_cleaning['project']
        for buf in keys(s:current_errors.project)
            unlet s:current_errors['project'][buf]
            call neomake#highlights#ResetProject(buf + 0)
        endfor
        let s:need_errors_cleaning['project'] = 0
        call neomake#utils#DebugMessage('All project-level errors cleaned.')
    endif
    if g:neomake_place_signs
        call neomake#signs#CleanAllOldSigns('project')
    endif
endfunction

function! neomake#CleanOldFileSignsAndErrors(...) abort
    let bufnr = a:0 ? a:1 : bufnr('%')
    if get(s:need_errors_cleaning['file'], bufnr, 0)
        if has_key(s:current_errors['file'], bufnr)
            unlet s:current_errors['file'][bufnr]
        endif
        unlet s:need_errors_cleaning['file'][bufnr]
        call neomake#highlights#ResetFile(bufnr)
        call neomake#utils#DebugMessage('File-level errors cleaned in buffer '.bufnr)
    endif
    if g:neomake_place_signs
        call neomake#signs#CleanOldSigns(bufnr, 'file')
    endif
endfunction

function! neomake#EchoCurrentError(...) abort
    " a:1 might be a timer from the VimResized event.
    let force = a:0 ? a:1 : 0
    if !force && !get(g:, 'neomake_echo_current_error', 1)
        return
    endif

    let buf = bufnr('%')
    let ln = line('.')
    let ln_errors = []

    for maker_type in ['file', 'project']
        let buf_errors = get(s:current_errors[maker_type], buf, {})
        let ln_errors += get(buf_errors, ln, [])
    endfor

    if empty(ln_errors)
        if exists('s:neomake_last_echoed_error')
            echon ''
            unlet s:neomake_last_echoed_error
        endif
        return
    endif

    if len(ln_errors) > 1
        let ln_errors = copy(ln_errors)
        call sort(ln_errors, function('neomake#utils#sort_by_col'))
    endif
    let error_entry = ln_errors[0]
    if !force && exists('s:neomake_last_echoed_error')
                \ && s:neomake_last_echoed_error == error_entry
        return
    endif
    let s:neomake_last_echoed_error = error_entry

    let message = error_entry.maker_name.': '.error_entry.text
    call neomake#utils#WideMessage(message)
endfunction

function! neomake#CursorMoved() abort
    call neomake#EchoCurrentError()
endfunction

function! s:cursormoved_delayed_cb(...) abort
    if getpos('.') == s:cursormoved_last_pos
        call neomake#CursorMoved()
    endif
endfunction
function! neomake#CursorMovedDelayed() abort
    if exists('s:cursormoved_timer')
        call timer_stop(s:cursormoved_timer)
    endif
    let s:cursormoved_timer = timer_start(get(g:, 'neomake_cursormoved_delay', 100), function('s:cursormoved_delayed_cb'))
    let s:cursormoved_last_pos = getpos('.')
endfunction

function! neomake#CompleteMakers(ArgLead, CmdLine, ...) abort
    if a:ArgLead =~# '[^A-Za-z0-9]'
        return []
    endif
    if a:CmdLine !~# '\s'
        " Just 'Neomake!' without following space.
        return [' ']
    endif
    let file_mode = a:CmdLine =~# '\v^(Neomake|NeomakeFile)\s'
    let makers = file_mode ? neomake#GetMakers(&filetype) : neomake#GetProjectMakers()
    return filter(makers, "v:val =~? '^".a:ArgLead."'")
endfunction

function! neomake#CompleteJobs(...) abort
    return join(map(neomake#GetJobs(), "v:val.id.': '.v:val.maker.name"), "\n")
endfunction

" Map/bind a:makers to a list of job options, using a:options.
function! s:map_makers(options, makers, ...) abort
    let r = []
    for maker_or_name in a:makers
        let options = copy(a:options)
        try
            let maker = call('neomake#GetMaker', [maker_or_name] + a:000)

            " Call .fn function in maker object, if any.
            if has_key(maker, 'fn')
                " TODO: Allow to throw and/or return 0 to abort/skip?!
                let returned_maker = call(maker.fn, [options], maker)
                if returned_maker isnot# 0
                    " This conditional assignment allows to both return a copy
                    " (factory), while also can be used as a init method.
                    let maker = returned_maker
                endif
            endif

            if has_key(maker, 'cwd')
                let cwd = maker.cwd
                if cwd =~# '\m^%:'
                    let cwd = neomake#utils#fnamemodify(options.bufnr, cwd[1:])
                else
                    let cwd = expand(cwd, 1)
                endif
                let options.cwd = fnamemodify(cwd, ':p')
            endif

            if has_key(maker, '_bind_args')
                call maker._bind_args()
                if !executable(maker.exe)
                    if !get(maker, 'auto_enabled', 0)
                        let error = printf('Exe (%s) of maker %s is not executable.', maker.exe, maker.name)
                        if !has_key(s:exe_error_thrown, maker.exe)
                            let s:exe_error_thrown[maker.exe] = 1
                            call neomake#utils#ErrorMessage(error)
                        else
                            call neomake#utils#DebugMessage(error)
                        endif
                        throw 'Neomake: '.error
                    endif

                    call neomake#utils#DebugMessage(printf(
                                \ 'Exe (%s) of auto-configured maker %s is not executable, skipping.', maker.exe, maker.name))
                    continue
                endif
            endif

        catch /^Neomake: /
            let error = substitute(v:exception, '^Neomake: ', '', '')
            call neomake#utils#ErrorMessage(error, {'make_id': options.make_id})
            continue
        endtry
        let options.maker = maker
        let r += [options]
    endfor
    return r
endfunction

function! neomake#Make(file_mode_or_options, ...) abort
    if type(a:file_mode_or_options) == type({})
        return s:Make(a:file_mode_or_options)
    endif

    let file_mode = a:file_mode_or_options
    let options = {'file_mode': file_mode}
    if file_mode
        let options.ft = &filetype
    endif
    if a:0
        if !empty(a:1)
            let options.enabled_makers = a:1
        endif
        if a:0 > 1
            let options.exit_callback = a:2
        endif
    endif
    return s:Make(options)
endfunction

function! neomake#ShCommand(bang, sh_command, ...) abort
    let maker = neomake#utils#MakerFromCommand(a:sh_command)
    let maker.name = 'sh: '.a:sh_command
    let maker.buffer_output = !a:bang
    let maker.errorformat = '%m'
    let options = {'enabled_makers': [maker], 'file_mode': 0}
    if a:0
        call extend(options, a:1)
    endif
    return get(s:Make(options), 0, -1)
endfunction

function! neomake#Sh(sh_command, ...) abort
    " Deprecated, but documented.
    let options = a:0 ? { 'exit_callback': a:1 } : {}
    return neomake#ShCommand(0, a:sh_command, options)
endfunction

" Optional arg: ft
function! s:display_maker_info(...) abort
    let maker_names = call('neomake#GetEnabledMakers', a:000)
    if empty(maker_names)
        echon ' None.'
        return
    endif
    for maker_name in maker_names
        let maker = call('neomake#GetMaker', [maker_name] + a:000)
        echo ' - '.maker.name
        for [k, V] in sort(copy(items(maker)))
            if k !=# 'name' && k !=# 'ft' && k !~# '^_'
                if !has_key(s:maker_defaults, k)
                            \ || type(V) != type(s:maker_defaults[k])
                            \ || V !=# s:maker_defaults[k]
                    echo '   - '.k.': '.string(V)
                endif
            endif
            unlet V  " vim73
        endfor

        let issues = neomake#debug#validate_maker(maker)
        if !empty(issues)
            for type in sort(copy(keys(issues)))
                let items = issues[type]
                if !empty(items)
                    echo '   '.toupper(type) . ':'
                    for issue in items
                        echo '    - ' . issue
                    endfor
                endif
            endfor
        endif
    endfor
endfunction

function! neomake#DisplayInfo() abort
    let ft = &filetype
    echo '#### Neomake debug information'
    echo 'Async support: '.neomake#has_async_support()
    echo 'Current filetype: '.ft
    echo "\n"
    echo '##### Enabled makers'
    echo 'For the current filetype (with :Neomake):'
    call s:display_maker_info(ft)
    if empty(ft)
        echo 'NOTE: the current buffer does not have a filetype.'
    else
        let conf_ft = neomake#utils#get_ft_confname(ft)
        echo 'NOTE: you can define g:neomake_'.conf_ft.'_enabled_makers'
                    \ .' to configure it (or b:neomake_'.conf_ft.'_enabled_makers).'
    endif
    echo "\n"
    echo 'For the project (with :Neomake!):'
    call s:display_maker_info()
    echo 'NOTE: you can define g:neomake_enabled_makers to configure it.'
    echo "\n"
    echo 'Default maker settings:'
    for [k, v] in items(s:maker_defaults)
        echo ' - '.k.': '.string(v)
        unlet! v  " Fix variable type mismatch with Vim 7.3.
    endfor
    echo "\n"
    echo '##### Settings'
    echo '```'
    for [k, V] in sort(items(filter(copy(g:), "v:key =~# '^neomake_'")))
        echo 'g:'.k.' = '.string(V)
        unlet! V  " Fix variable type mismatch with Vim 7.3.
    endfor
    echo "\n"
    echo 'Windows: '.neomake#utils#IsRunningWindows()
    echo '[shell, shellcmdflag, shellslash]:' [&shell, &shellcmdflag, &shellslash]
    echo '```'
    if &verbose
        echo "\n"
        echo '#### :version'
        echo '```'
        version
        echo '```'
        echo "\n"
        echo '#### :messages'
        echo '```'
        messages
        echo '```'
    endif
endfunction
