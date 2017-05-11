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
let s:maker_defaults = {
            \ 'buffer_output': 1,
            \ 'remove_invalid_entries': 0}
" List of pending outputs by job ID.
let s:pending_outputs = {}
" Keep track of for what maker.exe an error was thrown.
let s:exe_error_thrown = {}
let s:kill_vim_timers = {}

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
        call neomake#utils#ErrorMessage('CancelJob: job not found: '.job_id.'.')
        return 0
    endif
    let ret = 0
    let jobinfo = s:jobs[job_id]
    " Mark it as canceled for the exit handler.
    let jobinfo.canceled = 1
    if get(jobinfo, 'finished')
        call neomake#utils#DebugMessage('Removing already finished job.', jobinfo)
    else
        call neomake#utils#DebugMessage('Stopping job.', jobinfo)
        if has('nvim')
            try
                call jobstop(job_id)
                let ret = 1
            catch /^Vim\%((\a\+)\)\=:\(E474\|E900\):/
                call neomake#utils#LoudMessage(printf(
                            \ 'jobstop failed: %s.', v:exception), jobinfo)
            endtry
        else
            let vim_job = jobinfo.vim_job
            " Use ch_status here, since job_status might be 'dead' already,
            " without the exit handler being called yet.
            if ch_status(vim_job) !=# 'open'
                call neomake#utils#LoudMessage(
                            \ 'job_stop: job was not running anymore.', jobinfo)
            else
                " NOTE: might be "dead" already, but that is fine.
                call job_stop(vim_job)
                let ret = 1

                if job_status(vim_job) ==# 'run'
                    let timer = timer_start(1000, function('s:kill_vimjob_cb'))
                    let s:kill_vim_timers[timer] = jobinfo
                endif
            endif
        endif
    endif
    if ret == 0 || remove_always
        call s:CleanJobinfo(jobinfo)
    endif
    return ret
endfunction

function! s:kill_vimjob_cb(timer) abort
    let jobinfo = s:kill_vim_timers[a:timer]
    let vim_job = jobinfo.vim_job
    if job_status(vim_job) ==# 'run'
        call neomake#utils#DebugMessage('Forcefully killing still running Vim job.', jobinfo)
        call job_stop(vim_job, 'kill')
    endif
    unlet s:kill_vim_timers[a:timer]
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

    let [cd_error, cd_back_cmd] = s:cd_to_jobs_cwd(jobinfo)
    if !empty(cd_error)
        call neomake#utils#ErrorMessage(printf(
                    \ "%s: could not change to maker's cwd (%s): %s.",
                    \ maker.name, cd_back_cmd, cd_error), jobinfo)
        return {}
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
                call neomake#utils#LoudMessage(printf('Starting async job: %s.',
                            \ string(argv)), jobinfo)
                try
                    let job = jobstart(argv, opts)
                catch
                    let error = printf('Failed to start Neovim job: %s: %s.',
                                \ string(argv), v:exception)
                endtry
                if empty(error)
                    if job == 0
                        let error = printf('Failed to start Neovim job: %s: %s.',
                                    \ 'Job table is full or invalid arguments given', string(argv))
                    elseif job == -1
                        let error = printf('Failed to start Neovim job: %s: %s.',
                                    \ 'Executable not found', string(argv))
                    else
                        let jobinfo.id = job
                        let s:jobs[jobinfo.id] = jobinfo

                        if get(jobinfo, 'uses_stdin', 0)
                            call jobsend(job, s:make_info[a:make_id].buffer_lines)
                            call jobclose(job, 'stdin')
                        endif
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
                call neomake#utils#LoudMessage(printf('Starting async job: %s.',
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
                    call neomake#utils#DebugMessage(printf('Vim job: %s.',
                                \ string(job_info(job))), jobinfo)
                    call neomake#utils#DebugMessage(printf('Vim channel: %s.',
                                \ string(ch_info(job))), jobinfo)

                    if get(jobinfo, 'uses_stdin', 0)
                        call ch_sendraw(job, join(s:make_info[a:make_id].buffer_lines, "\n"))
                        call ch_close_in(job)
                    endif
                endif
            endif

            " Bail out on errors.
            if !empty(error)
                let jobinfo.failed_to_start = 1
                call neomake#utils#ErrorMessage(error, jobinfo)
                return s:handle_next_maker(jobinfo)
            endif
        else
            call neomake#utils#DebugMessage('Running synchronously.')
            call neomake#utils#LoudMessage(printf('Starting: %s.', argv), jobinfo)

            let jobinfo.id = job_id
            let s:jobs[job_id] = jobinfo
            let s:make_info[a:make_id].active_jobs += [jobinfo]
            call s:output_handler(job_id, split(system(argv), '\r\?\n', 1), 'stdout')
            call s:exit_handler(job_id, v:shell_error, 'exit')
            return {}
        endif
    finally
        if !empty(cd_back_cmd)
            exe cd_back_cmd
        endif
        if exists('save_env_file')
            " Not possible to unlet environment vars
            " (https://github.com/vim/vim/issues/1116).
            " Should only set it for the job
            " (https://github.com/vim/vim/pull/1160).
            let $NEOMAKE_FILE = save_env_file
        endif
    endtry
    let s:make_info[a:make_id].active_jobs += [jobinfo]
    return jobinfo
endfunction

let s:maker_base = {}
let s:command_maker_base = {}
" Check if a temporary file is used, and set it in s:make_info in case it is.
function! s:command_maker_base._get_tempfilename(jobinfo) abort dict
    if get(self, 'supports_stdin', 0)
        let a:jobinfo.uses_stdin = 1
        return get(self, 'tempfile_name', '-')
    endif

    if has_key(self, 'tempfile_name')
        return self.tempfile_name
    endif

    let tempfile_enabled = neomake#utils#GetSetting('tempfile_enabled', self, 0, a:jobinfo.ft, a:jobinfo.bufnr)
    if !tempfile_enabled
        return ''
    endif

    let make_id = a:jobinfo.make_id
    if !has_key(s:make_info[make_id], 'tempfile_name')
        if !exists('s:pid')
            let s:pid = getpid()
        endif
        let slash = neomake#utils#Slash()
        let bufname = bufname(a:jobinfo.bufnr)
        if empty(bufname)
            let temp_file = tempname() . slash . 'neomaketmp.'.a:jobinfo.ft
        else
            let orig_file = neomake#utils#fnamemodify(a:jobinfo.bufnr, ':p')
            if empty(orig_file)
                let bufname = fnamemodify(bufname, ':t')
                let s:make_info[make_id].tempfile_dir = tempname()
                let temp_file = s:make_info[make_id].tempfile_dir . slash . bufname
            else
                let temp_file = fnamemodify(orig_file, ':h')
                            \ .slash.'.'.fnamemodify(orig_file, ':t')
                            \ .'@neomake_'.s:pid.'_'.make_id
                            \ .'.'.fnamemodify(orig_file, ':e')
            endif
        endif
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
                        \ 'Using tempfile for unnamed buffer: "%s".', temp_file),
                        \ a:jobinfo)
        else
            throw 'Neomake: no file name.'
        endif
    elseif getbufvar(bufnr, '&modified')
        let temp_file = self._get_tempfilename(a:jobinfo)
        if !empty(temp_file)
            call neomake#utils#DebugMessage(printf(
                        \ 'Using tempfile for modified buffer: "%s".', temp_file),
                        \ a:jobinfo)
        else
            call neomake#utils#DebugMessage('warning: buffer is modified. You might want to enable tempfiles.',
                        \ a:jobinfo)
        endif
    elseif !filereadable(bufname)
        let temp_file = self._get_tempfilename(a:jobinfo)
        if !empty(temp_file)
            call neomake#utils#DebugMessage(printf(
                        \ 'Using tempfile for unreadable buffer: "%s".', temp_file),
                        \ a:jobinfo)
        else
            " Using ':p' as modifier is unpredictable as per doc, but OK.
            throw printf('Neomake: file is not readable (%s)', fnamemodify(bufname, ':p'))
        endif
    else
        let bufname = fnamemodify(bufname, ':p')
    endif

    let make_info = s:make_info[a:jobinfo.make_id]
    if !empty(temp_file)
        let bufname = temp_file
        let uses_stdin = get(a:jobinfo, 'uses_stdin', 0)
        if uses_stdin && neomake#has_async_support()
            if !has_key(make_info, 'buffer_lines')
                let make_info.buffer_lines = getbufline(bufnr, 1, '$')
            endif
        else
            if uses_stdin
                " Use a real temporary file to pass into system().
                let temp_file = tempname()
                call neomake#utils#DebugMessage(printf(
                            \ 'Creating tempfile for non-async stdin: "%s".', temp_file),
                            \ a:jobinfo)
            endif
            if !has_key(make_info, 'tempfiles')
                let make_info.tempfiles = [temp_file]
                let make_info.created_dirs = s:create_dirs_for_file(temp_file)
                call neomake#utils#write_tempfile(bufnr, temp_file)
            elseif temp_file !=# make_info.tempfiles[0]
                call extend(make_info.created_dirs, s:create_dirs_for_file(temp_file))
                call writefile(readfile(make_info.tempfiles[0], 'b'), temp_file, 'b')
                call add(make_info.tempfiles, temp_file)
            endif
        endif
        let a:jobinfo.tempfile = temp_file
    endif
    let a:jobinfo.filename = bufname
    return bufname
endfunction

function! s:create_dirs_for_file(fpath) abort
    let created_dirs = []
    let last_dir = a:fpath
    while 1
        let temp_dir = fnamemodify(last_dir, ':h')
        if isdirectory(temp_dir) || last_dir ==# temp_dir
            break
        endif
        call insert(created_dirs, temp_dir)
        let last_dir = temp_dir
    endwhile
    for dir in created_dirs
        call mkdir(dir, '', 0700)
    endfor
    return created_dirs
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

    " Append file?  (defaults to 1 in file_mode)
    let append_file = neomake#utils#GetSetting('append_file', self, a:jobinfo.file_mode, a:jobinfo.ft, a:jobinfo.bufnr)
    " Use/generate a filename?  (defaults to 1 if tempfile_name is set)
    let uses_filename = append_file || neomake#utils#GetSetting('uses_filename', self, has_key(self, 'tempfile_name'), a:jobinfo.ft, a:jobinfo.bufnr)
    if append_file || uses_filename
        let filename = self._get_fname_for_buffer(a:jobinfo)
        if append_file
            if args_is_list
                call add(args, filename)
            else
                let args .= (empty(args) ? '' : ' ').fnameescape(filename)
            endif
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
        if get(a:jobinfo, 'uses_stdin', 0)
            let tempfile = get(a:jobinfo, 'tempfile')
            if !empty(tempfile)
                let argv .= ' < '.tempfile
            endif
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
        call neomake#utils#ErrorMessage('Invalid maker name: "'.a:name_or_maker.'".')
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
            unlet default  " for Vim without patch-7.4.1546
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
                let error = substitute(v:exception, '^Neomake: ', '', '').'.'
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
                \ 'active_jobs': [],
                \ 'finished_jobs': 0,
                \ 'options': options,
                \ }
    let make_info = s:make_info[make_id]
    if &verbose
        let make_info.verbosity += &verbose
        call neomake#utils#DebugMessage(printf(
                    \ 'Adding &verbose (%d) to verbosity level: %d.',
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
                \ 'Running makers: %s.', maker_info), log_context)

    let make_info.jobs_queue = jobs

    if file_mode
        " XXX: this clears counts for job's buffer only, but we add counts for
        " the entry's buffers, which might be different!
        call neomake#statusline#ResetCountsForBuf(bufnr)
        if g:neomake_place_signs
            call neomake#signs#Reset(bufnr, 'file')
        endif
    else
        call neomake#statusline#ResetCountsForProject()
        if g:neomake_place_signs
            call neomake#signs#ResetProject()
        endif
    endif

    let w:neomake_make_ids = add(get(w:, 'neomake_make_ids', []), make_id)

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

    if has_key(s:make_info, make_id) && empty(s:make_info[make_id].active_jobs)
        " Might have been removed through s:CleanJobinfo already.
        call s:clean_make_info(make_id)
    endif
    return job_ids
endfunction

function! s:AddExprCallback(jobinfo, prev_index) abort
    let maker = a:jobinfo.maker
    let file_mode = a:jobinfo.file_mode
    let list = file_mode ? getloclist(0) : getqflist()
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
    let default_type = 'unset'

    let entries = []
    let changed_entries = {}
    let removed_entries = []
    let llen = len(list)
    while index < llen - 1
        let index += 1
        let entry = list[index]
        let entry.maker_name = has_key(maker, 'name') ? maker.name : 'makeprg'

        let before = copy(entry)
        if file_mode && has_key(make_info, 'tempfiles')
            if entry.bufnr
                for tempfile in make_info.tempfiles
                    let tempfile_bufnr = bufnr(tempfile)
                    if tempfile_bufnr != -1 && entry.bufnr == tempfile_bufnr
                        call neomake#utils#DebugMessage(printf(
                                    \ 'Setting bufnr according to tempfile for entry: %s.', string(entry)), a:jobinfo)
                        let entry.bufnr = a:jobinfo.bufnr
                    endif
                endfor
            endif
        endif
        if has_key(entry, 'bufnr') && entry.bufnr != a:jobinfo.bufnr
            call neomake#utils#DebugMessage(printf('WARN: entry.bufnr (%d) is different from jobinfo.bufnr (%d) (current buffer %d): %s.', entry.bufnr, a:jobinfo.bufnr, bufnr('%'), string(entry)))
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
            let changed_entries[index] = entry
            if debug
                call neomake#utils#DebugMessage(printf(
                  \ 'Modified list entry (postprocess): %s.',
                  \ join(values(map(neomake#utils#diff_dict(before, entry)[0],
                  \ "v:key.': '.string(v:val[0]).' => '.string(v:val[1])")))))

            endif
        endif

        if entry.valid <= 0
            if entry.valid < 0 || maker.remove_invalid_entries
                call insert(removed_entries, index)
                let entry_copy = copy(entry)
                call neomake#utils#DebugMessage(printf(
                            \ 'Removing invalid entry: %s (%s).',
                            \ remove(entry_copy, 'text'),
                            \ string(entry_copy)), a:jobinfo)
                continue
            endif
        endif

        if empty(entry.type)
            if default_type ==# 'unset'
                let default_type = neomake#utils#GetSetting('default_entry_type', maker, 'W', a:jobinfo.ft, a:jobinfo.bufnr)
            endif
            if !empty(default_type)
                let entry.type = default_type
                let changed_entries[index] = entry
            endif
        endif
        call add(entries, entry)
    endwhile

    if !empty(changed_entries) || !empty(removed_entries)
        let list = file_mode ? getloclist(0) : getqflist()
        if !empty(changed_entries)
            for k in keys(changed_entries)
                let list[k] = changed_entries[k]
            endfor
        endif
        if !empty(removed_entries)
            for k in removed_entries
                call remove(list, k)
            endfor
        endif
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
    call neomake#utils#DebugMessage('Cleaning jobinfo.', a:jobinfo)

    let make_info = s:make_info[a:jobinfo.make_id]
    call filter(make_info.active_jobs, 'v:val != a:jobinfo')

    if has_key(s:jobs, get(a:jobinfo, 'id', -1))
        call remove(s:jobs, a:jobinfo.id)

        if has_key(s:pending_outputs, a:jobinfo.id)
            unlet s:pending_outputs[a:jobinfo.id]
        endif
    endif

    if !get(a:jobinfo, 'canceled', 0)
                \ && !get(a:jobinfo, 'failed_to_start', 0)
        call neomake#utils#hook('NeomakeJobFinished', {'jobinfo': a:jobinfo})
        let make_info.finished_jobs += 1
    endif

    " Trigger autocmd if all jobs for a s:Make instance have finished.
    if !empty(make_info.active_jobs)
        return
    endif

    if !empty(s:make_info[a:jobinfo.make_id].jobs_queue)
        return
    endif

    if make_info.finished_jobs
        call s:clean_for_new_make(a:jobinfo)

        " Clean old signs after all jobs have finished, so that they can be
        " reused, avoiding flicker and keeping them for longer in general.
        if g:neomake_place_signs
            if a:jobinfo.file_mode
                call neomake#signs#CleanOldSigns(a:jobinfo.bufnr, 'file')
            else
                call neomake#signs#CleanAllOldSigns('project')
            endif
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

    let tempfiles = get(s:make_info[a:make_id], 'tempfiles')
    if !empty(tempfiles)
        for tempfile in tempfiles
            call neomake#utils#DebugMessage(printf('Removing temporary file: "%s".',
                        \ tempfile))
            call delete(tempfile)
            if bufexists(tempfile) && !buflisted(tempfile)
                exe 'bwipe' tempfile
            endif
        endfor

        " Only delete the dir, if Vim supports it.  It will be cleaned up
        " when quitting Vim in any case.
        if v:version >= 705 || (v:version == 704 && has('patch1107'))
            for dir in reverse(copy(get(s:make_info[a:make_id], 'created_dirs')))
                call delete(dir, 'd')
            endfor
        endif
    endif

    unlet s:make_info[a:make_id]
endfunction

function! s:CanProcessJobOutput() abort
    " We can only process output (change the location/quickfix list) in
    " certain modes, otherwise e.g. the visual selection gets lost.
    if index(['n', 'i'], mode()) == -1
        call neomake#utils#DebugMessage('Not processing output for mode "'.mode().'".')
    elseif exists('*getcmdwintype') && getcmdwintype() !=# ''
        call neomake#utils#DebugMessage('Not processing output from command-line window "'.getcmdwintype().'".')
    else
        return 1
    endif
    return 0
endfunction

function! s:create_locqf_list(jobinfo) abort
    " TODO: queue this when in non-normal mode(s)
    " Error detected while processing function Tabline[29]..TabLabel[16]..<SNR>134_exit_handler[71]..<SNR>134_handle_next_maker[16]..<SNR>134_CleanJobinfo[40]..<SNR>134_clean_for_new_make[5]..<SNR>134_create_locqf_list:
    " E523: Not allowed here:             lgetexpr ''
    if get(s:make_info[a:jobinfo.make_id], 'created_locqf_list', 0)
        return
    endif
    let s:make_info[a:jobinfo.make_id].created_locqf_list = 1

    let file_mode = a:jobinfo.file_mode
    call neomake#utils#DebugMessage(printf(
                \ 'Creating %s list.',
                \ file_mode ? 'location' : 'quickfix'), a:jobinfo)
    " Empty the quickfix/location list (using a valid 'errorformat' setting).
    let save_efm = &errorformat
    let &errorformat = '%-G'
    try
        if file_mode
            lgetexpr ''
        else
            cgetexpr ''
        endif
    finally
        let &errorformat = save_efm
    endtry
    " TODO: correct?!
    call s:HandleLoclistQflistDisplay(a:jobinfo.file_mode)
endfunction

function! s:clean_for_new_make(jobinfo) abort
    if get(s:make_info[a:jobinfo.make_id], 'cleaned_for_make', 0)
        return
    endif
    call s:create_locqf_list(a:jobinfo)
    " XXX: needs to handle buffers for list entries?!
    " See "get_list_entries: minimal example (from doc)" in
    " tests/makers.vader.
    if a:jobinfo.file_mode
        if has_key(s:current_errors['file'], a:jobinfo.bufnr)
            unlet s:current_errors['file'][a:jobinfo.bufnr]
        endif
        call neomake#highlights#ResetFile(a:jobinfo.bufnr)
        " TODO: reword/move
        call neomake#utils#DebugMessage('File-level errors cleaned in buffer '.a:jobinfo.bufnr.'.')
    else
        " TODO: test
        for buf in keys(s:current_errors.project)
            unlet s:current_errors['project'][buf]
            call neomake#highlights#ResetProject(+buf)
        endfor
    endif
    let s:make_info[a:jobinfo.make_id].cleaned_for_make = 1
endfunction

function! s:cd_to_jobs_cwd(jobinfo) abort
    let cwd = get(a:jobinfo, 'cwd', s:make_info[a:jobinfo.make_id].cwd)
    if empty(cwd)
        return ['', '']
    endif
    let cwd = fnamemodify(cwd, ':p')
    let cur_wd = getcwd()
    if cwd !=? cur_wd
        let cd = haslocaldir() ? 'lcd' : (exists(':tcd') == 2 && haslocaldir(-1, 0)) ? 'tcd' : 'cd'
        try
            exe cd.' '.fnameescape(cwd)
        catch
            " Tests fail with E344, but in reality it is E472?!
            " If uncaught, both are shown - let's just catch everything.
            return [v:exception, cwd]
        endtry
        return ['', cd.' '.fnameescape(cur_wd)]
    endif
endfunction

function! s:ProcessEntries(jobinfo, entries, ...) abort
    let file_mode = a:jobinfo.file_mode

    call neomake#utils#DebugMessage(printf(
                \ 'Processing %d entries.', len(a:entries)), a:jobinfo)

    call s:clean_for_new_make(a:jobinfo)

    if a:0
        " Via errorformat processing, where the list has been set already.
        let prev_list = a:1
    else
        " Fix entries with get_list_entries/process_output.
        call map(a:entries, 'extend(v:val, {'
                    \ . "'bufnr': str2nr(get(v:val, 'bufnr', 0)),"
                    \ . "'lnum': str2nr(v:val.lnum),"
                    \ . "'col': str2nr(get(v:val, 'col', 0)),"
                    \ . "'vcol': str2nr(get(v:val, 'vcol', 0)),"
                    \ . "'type': get(v:val, 'type', 'E'),"
                    \ . "'nr': get(v:val, 'nr', -1),"
                    \ . "'maker_name': a:jobinfo.maker.name,"
                    \ . '})')

        let prev_list = file_mode ? getloclist(0) : getqflist()

        let [cd_error, cd_back_cmd] = s:cd_to_jobs_cwd(a:jobinfo)
        if !empty(cd_error)
            call neomake#utils#DebugMessage(printf(
                        \ "Could not change to job's cwd (%s): %s.",
                        \ cd_back_cmd, cd_error), a:jobinfo)
        endif
        try
            if file_mode
                call setloclist(0, a:entries, 'a')
                let parsed_entries = getloclist(0)[len(prev_list):]
            else
                call setqflist(a:entries, 'a')
                let parsed_entries = getqflist()[len(prev_list):]
            endif
        finally
            if empty(cd_error)
                exe cd_back_cmd
            endif
        endtry
        let idx = 0
        for e in parsed_entries
            if a:entries[idx].bufnr != e.bufnr
                call neomake#utils#DebugMessage(printf(
                            \ 'Updating entry bufnr: %s => %s.',
                            \ a:entries[idx].bufnr, e.bufnr))
                let a:entries[idx].bufnr = e.bufnr
            endif
            let idx += 1
        endfor
    endif

    let counts_changed = 0
    let ignored_signs = []
    let maker_type = file_mode ? 'file' : 'project'
    let do_highlight = get(g:, 'neomake_highlight_columns', 1)
                \ || get(g:, 'neomake_highlight_lines', 0)
    let signs_by_bufnr = {}
    let skipped_without_bufnr = 0
    for entry in a:entries
        if !file_mode
            if neomake#statusline#AddQflistCount(entry)
                let counts_changed = 1
            endif
        endif

        if !entry.bufnr
            let skipped_without_bufnr += 1
            continue
        endif

        if file_mode
            if neomake#statusline#AddLoclistCount(entry.bufnr, entry)
                let counts_changed = 1
            endif
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
                if !has_key(signs_by_bufnr, entry.bufnr)
                    let signs_by_bufnr[entry.bufnr] = []
                endif
                call add(signs_by_bufnr[entry.bufnr], entry)
            endif
        endif
        if do_highlight
            call neomake#highlights#AddHighlight(entry, maker_type)
        endif
    endfor

    for [bufnr, entries] in items(signs_by_bufnr)
        call neomake#signs#PlaceSigns(bufnr, entries, maker_type)
    endfor

    if !empty(ignored_signs)
        call neomake#utils#DebugMessage(printf(
                    \ 'Could not place signs for %d entries without line number: %s.',
                    \ len(ignored_signs), string(ignored_signs)))
    endif

    if !empty(skipped_without_bufnr)
        call neomake#utils#DebugMessage(printf('Skipped %d entries without bufnr.',
                    \ skipped_without_bufnr), a:jobinfo)
    endif

    if !counts_changed
        let counts_changed = (file_mode ? getloclist(0) : getqflist()) != prev_list
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

    try
        if has_key(maker, 'process_output')
            let entries = call(maker.process_output, [{
                        \ 'output': a:lines,
                        \ 'source': a:source,
                        \ 'jobinfo': a:jobinfo}], maker)
            call s:ProcessEntries(a:jobinfo, entries)
            return
        endif

        " Old-school handling through errorformat.
        if has_key(maker, 'mapexpr')
            let l:neomake_bufname = bufname(a:jobinfo.bufnr)
            " @vimlint(EVL102, 1, l:neomake_bufdir)
            let l:neomake_bufdir = fnamemodify(neomake_bufname, ':h')
            " @vimlint(EVL102, 1, l:neomake_output_source)
            let l:neomake_output_source = a:source
            call map(a:lines, maker.mapexpr)
        endif

        call s:create_locqf_list(a:jobinfo)
        let prev_list = file_mode ? getloclist(0) : getqflist()
        let olderrformat = &errorformat
        let &errorformat = maker.errorformat

        let [cd_error, cd_back_cmd] = s:cd_to_jobs_cwd(a:jobinfo)
        if !empty(cd_error)
            call neomake#utils#DebugMessage(printf(
                        \ "Could not change to job's cwd (%s): %s.",
                        \ cd_back_cmd, cd_error), a:jobinfo)
        endif
        try
            if file_mode
                laddexpr a:lines
            else
                caddexpr a:lines
            endif
        finally
            let &errorformat = olderrformat
            if empty(cd_error)
                exe cd_back_cmd
            endif
        endtry

        let entries = s:AddExprCallback(a:jobinfo, len(prev_list)-1)
        call s:ProcessEntries(a:jobinfo, entries, prev_list)
    catch
        if v:exception ==# 'NeomakeTestsException'
            throw v:exception
        endif
        redraw
        echom printf('Neomake error in: %s', v:throwpoint)
        call neomake#utils#ErrorMessage(printf(
                    \ 'Error during output processing for %s: %s.',
                    \ a:jobinfo.maker.name, v:exception), a:jobinfo)
        call neomake#utils#DebugMessage(printf('(in %s)', v:throwpoint), a:jobinfo)
        return
    endtry
endfunction

function! s:ProcessPendingOutputs() abort
    let bufnr = bufnr('%')
    let window_make_ids = get(w:, 'neomake_make_ids', [])

    let skipped_other_buffer = []
    let skipped_other_window = []
    for job_id in sort(keys(s:pending_outputs), 'N')
        let output = s:pending_outputs[job_id]
        let jobinfo = s:jobs[job_id]
        if jobinfo.file_mode
            if index(window_make_ids, jobinfo.make_id) == -1
                if !bufexists(jobinfo.bufnr)
                    call neomake#utils#LoudMessage('No buffer found for output!', jobinfo)
                    let jobinfo.pending_output = 0
                    call s:CleanJobinfo(jobinfo)
                    continue
                endif
                if jobinfo.bufnr != bufnr
                    let skipped_other_buffer += [jobinfo]
                    continue
                endif
                if s:GetTabWinForMakeId(jobinfo.make_id) != [-1, -1]
                    let skipped_other_window += [jobinfo]
                    continue
                endif
                call neomake#utils#DebugMessage("Processing pending output for job's buffer in new window.", jobinfo)
            endif
        endif
        for [source, lines] in items(output)
            call s:ProcessJobOutput(jobinfo, lines, source)
        endfor

        if has_key(jobinfo, 'pending_output')
            call neomake#utils#DebugMessage('Processed pending output.', jobinfo)
            let jobinfo.pending_output = 0
            call s:CleanJobinfo(jobinfo)
        endif
    endfor
    for jobinfo in skipped_other_buffer
        call neomake#utils#DebugMessage('Skipped pending job output for another buffer.', jobinfo)
    endfor
    for jobinfo in skipped_other_window
        call neomake#utils#DebugMessage('Skipped pending job output (not in origin window).', jobinfo)
    endfor
    if empty(s:pending_outputs)
        au! neomake_process_pending
    endif
endfunction

function! s:add_pending_output(jobinfo, source, lines) abort
    if !exists('s:pending_outputs[a:jobinfo.id]')
        let s:pending_outputs[a:jobinfo.id] = {}
    endif
    if !exists('s:pending_outputs[a:jobinfo.id][a:source]')
        let s:pending_outputs[a:jobinfo.id][a:source] = []
    endif
    call extend(s:pending_outputs[a:jobinfo.id][a:source], a:lines)

    if !exists('#neomake_process_pending#BufEnter')
        augroup neomake_process_pending
            au!
            au BufEnter * call s:ProcessPendingOutputs()
            " TODO: could use more events or a timer here.
            au CursorHold * call s:ProcessPendingOutputs()
        augroup END
    endif
endfunction

" Get tabnr and winnr for a given make ID.
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

function! s:RegisterJobOutput(jobinfo, lines, source) abort
    if s:CanProcessJobOutput()
        if !a:jobinfo.file_mode
                    \ || index(get(w:, 'neomake_make_ids', []), a:jobinfo.make_id) != -1
            if !empty(s:pending_outputs)
                call s:ProcessPendingOutputs()
            endif
            call s:ProcessJobOutput(a:jobinfo, a:lines, a:source)
            return
        endif
    endif
    call s:add_pending_output(a:jobinfo, a:source, a:lines)
endfunction

function! s:vim_output_handler(channel, output, event_type) abort
    let job_id = ch_info(a:channel)['id']
    let jobinfo = s:jobs[job_id]

    let data = split(a:output, '\v\r?\n', 1)

    if exists('jobinfo._vim_in_handler')
        call neomake#utils#DebugMessage(printf('Queueing: %s: %s: %s.',
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

        " Trigger previously delayed exit handler.
        if exists('jobinfo._exited_while_in_handler')
            call neomake#utils#DebugMessage('Trigger delayed exit.', jobinfo)
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
        let error = 'Vim job failed to run: '.substitute(join(jobinfo.stderr), '\v\s+$', '', '').'.'
        let jobinfo.stderr = []
        call neomake#utils#ErrorMessage(error)
        call s:CleanJobinfo(jobinfo)
    else
        call s:exit_handler(job_id, status, 'exit')
    endif
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
                call neomake#utils#DebugMessage('Trigger delayed exit.', jobinfo)
                call s:exit_handler(jobinfo.id, jobinfo._exited_while_in_handler, 'exit')
            endif
        endif
    endwhile
    unlet! s:nvim_output_handler_timer
endfunction
" @vimlint(EVL103, 0, a:timer)

function! s:exit_handler(job_id, data, event_type) abort
    if !has_key(s:jobs, a:job_id)
        call neomake#utils#QuietMessage(printf('exit: job not found: %s.', a:job_id))
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
        call neomake#utils#DebugMessage(printf('exit (delayed): %s: %s.',
                    \ maker.name, string(a:data)), jobinfo)
        return
    endif
    call neomake#utils#DebugMessage(printf('%s: %s: %s.',
                \ a:event_type, maker.name, string(a:data)), jobinfo)

    " Handle any unfinished lines from stdout/stderr callbacks.
    for event_type in ['stdout', 'stderr']
        if has_key(jobinfo, event_type)
            let lines = jobinfo[event_type]
            if !empty(lines)
                if lines[-1] ==# ''
                    call remove(lines, -1)
                endif
                if !empty(lines)
                    call s:RegisterJobOutput(jobinfo, lines, event_type)
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
        if has_key(s:pending_outputs, jobinfo.id)
            let jobinfo.pending_output = 1
        endif
        let jobinfo.finished = 1
    endif
    call s:handle_next_maker(jobinfo)
endfunction

function! s:output_handler(job_id, data, event_type) abort
    let jobinfo = s:jobs[a:job_id]

    call neomake#utils#DebugMessage(printf('%s: %s: %s.',
                \ a:event_type, jobinfo.maker.name, string(a:data)), jobinfo)
    if get(jobinfo, 'canceled')
        call neomake#utils#DebugMessage('Ignoring output (job was canceled).', jobinfo)
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
        let next_makers = join(map(copy(jobs_queue), 'v:val.maker.name'), ', ')
        call neomake#utils#LoudMessage('Aborting next makers: '.next_makers.'.')
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
                let options.cwd = substitute(fnamemodify(cwd, ':p'), '[\/]$', '', '')
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
            let error = substitute(v:exception, '^Neomake: ', '', '').'.'
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
    let maker.default_entry_type = ''
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
                    echo '   - '.toupper(type) . ':'
                    for issue in items
                        echo '     - ' . issue
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
