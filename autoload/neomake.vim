" vim: ts=4 sw=4 et
scriptencoding utf-8

if !exists('s:make_id')
    let s:make_id = 0
endif
" A map of make_id to options, e.g. cwd when jobs where started.
if !exists('s:make_info')
    let s:make_info = {}
endif
if !exists('s:job_id')
    let s:job_id = 1
endif
if !exists('s:jobs')
    let s:jobs = {}
endif
if !exists('s:map_job_ids')
    let s:map_job_ids = {}
endif

" Errors by [maker_type][bufnr][lnum]
let s:current_errors = {'project': {}, 'file': {}}
let s:maker_defaults = {
            \ 'buffer_output': 1,
            \ 'remove_invalid_entries': 0}
" List of pending outputs by job ID.
let s:pending_outputs = {}
" Keep track of for what maker.exe an error was thrown.
let s:exe_error_thrown = {}

if !has('nvim')
    let s:kill_vim_timers = {}
endif

" Sentinels.
let s:unset_list = []
let s:unset_dict = {}

let s:async = has('nvim')
            \ || has('channel') && has('job') && has('patch-8.0.0027')
function! neomake#has_async_support() abort
    return s:async
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
                \ 'action_queue': s:action_queue,
                \ }
endfunction

" Not documented, only used internally for now.
function! neomake#GetMakeOptions(...) abort
    let make_id = a:0 ? a:1 : s:make_id
    if !has_key(s:make_info, make_id)
        if exists('*vader#log')
            call vader#log('warning: missing make_info key: '.make_id)
        endif
        return {'verbosity': 3}
    endif
    return s:make_info[make_id]
endfunction

function! neomake#ListJobs() abort
    if !s:async
        echom 'This Vim version has no support for jobs.'
        return
    endif
    let jobs = neomake#GetJobs()
    if empty(jobs)
        return
    endif
    echom 'make_id | job_id | name/maker'
    for jobinfo in jobs
        let desc = !empty(jobinfo.maker.name) && jobinfo.name != jobinfo.maker.name
                    \ ? jobinfo.name. ' ('.jobinfo.maker.name.')'
                    \ : jobinfo.name
        echom printf('%7d | %6d | %s', jobinfo.make_id, jobinfo.id, desc)
    endfor
endfunction

function! neomake#CancelMake(make_id, ...) abort
    if !has_key(s:make_info, a:make_id)
        return 0
    endif
    let bang = a:0 ? a:1 : 0
    let jobs = filter(copy(values(s:jobs)), 'v:val.make_id == a:make_id')
    for job in jobs
        call neomake#CancelJob(job.id, bang)
    endfor
    if has_key(s:make_info, a:make_id)
        " Might have been cleaned by now; do not trigger a debug msg for it.
        call s:clean_make_info(a:make_id, bang)
    endif
    return 1
endfunction

" Returns 1 if a job was canceled, 0 otherwise.
function! neomake#CancelJob(job_id, ...) abort
    let job_id = type(a:job_id) == type({}) ? a:job_id.id : +a:job_id
    let remove_always = a:0 ? a:1 : 0
    let jobinfo = get(s:jobs, a:job_id, {})

    " Remove any queued actions.
    let removed = 0
    for [event, q] in items(s:action_queue)
        let len_before = len(q)
        call filter(q, "get(v:val[1][0], 'id') != a:job_id")
        let len_after = len(q)
        if len_before != len_after
            let removed += (len_before - len_after)
            if !len_after
                call s:clean_action_queue_augroup(event)
            endif
        endif
    endfor
    if removed
        let log_context = empty(jobinfo) ? {'id': a:job_id} : jobinfo
        call neomake#utils#DebugMessage(printf(
                    \ 'Removed %d action queue entries.',
                    \ removed), log_context)
    endif

    if empty(jobinfo)
        call neomake#utils#ErrorMessage('CancelJob: job not found: '.job_id.'.')
        return 0
    endif

    if get(jobinfo, 'canceled', 0)
        call neomake#utils#LoudMessage('Job was canceled already.', jobinfo)
        if remove_always
            call s:CleanJobinfo(jobinfo)
        endif
        return 0
    endif

    let ret = 0
    if get(jobinfo, 'finished')
        call neomake#utils#DebugMessage('Removing already finished job.', jobinfo)
    else
        call neomake#utils#DebugMessage('Stopping job.', jobinfo)
        if has('nvim')
            try
                call jobstop(jobinfo.nvim_job)
                let ret = 1
            catch /^Vim\%((\a\+)\)\=:\(E474\|E900\):/
                call neomake#utils#LoudMessage(printf(
                            \ 'jobstop failed: %s.', v:exception), jobinfo)
            endtry
        else
            let vim_job = jobinfo.vim_job
            " Use ch_status here, since job_status might be 'dead' already,
            " without the exit handler being called yet.
            if job_status(vim_job) !=# 'run'
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
    let jobinfo.canceled = 1

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
    call neomake#utils#DebugMessage(printf('Cancelling %d jobs.', len(s:jobs)))
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

let s:jobinfo_base = {}
function! s:jobinfo_base.get_pid() abort
    if has_key(self, 'vim_job')
        let info = job_info(self.vim_job)
        if info.status ==# 'run'
            return info.process
        endif
        return -1
    endif
    try
        return jobpid(self.nvim_job)
    catch /^Vim(return):E900:/
        return -1
    endtry
endfunction

function! s:jobinfo_base.as_string() abort
    let extra = []
    for k in ['canceled', 'finished']
        if get(self, k, 0)
            let extra += [k]
        endif
    endfor
    return printf('Job %d: %s%s', self.id, self.name,
                \ empty(extra) ? '' : ' ['.join(extra, ', ').']')
endfunction

function! s:MakeJob(make_id, options) abort
    let job_id = s:job_id
    let s:job_id += 1

    " Optional:
    "  - serialize (default: 0 for async (and get_list_entries),
    "                        1 for non-async)
    "  - serialize_abort_on_error (default: 0)
    "  - exit_callback (string/function, default: 0)
    let jobinfo = extend(copy(s:jobinfo_base), extend({
        \ 'id': job_id,
        \ 'name': empty(get(a:options.maker, 'name', '')) ? 'neomake_'.job_id : a:options.maker.name,
        \ 'maker': a:options.maker,
        \ 'bufnr': a:options.bufnr,
        \ 'file_mode': a:options.file_mode,
        \ 'ft': a:options.ft,
        \ 'output_stream': get(a:options, 'output_stream', get(a:options.maker, 'output_stream', 'both')),
        \ }, a:options))

    let maker = jobinfo.maker

    if has_key(maker, 'get_list_entries')
        let jobinfo.serialize = 0
        call neomake#utils#LoudMessage(printf(
                    \ '%s: getting entries via get_list_entries.',
                    \ maker.name), jobinfo)
        let entries = maker.get_list_entries(jobinfo)
        if type(entries) != type([])
            call neomake#utils#ErrorMessage(printf('The get_list_entries method for maker %s did not return a list, but: %s.', jobinfo.maker.name, string(entries)[:100]), jobinfo)
        else
            call s:ProcessEntries(jobinfo, entries)
        endif
        call s:CleanJobinfo(jobinfo)
        return jobinfo
    endif

    let [cd_error, cwd, cd_back_cmd] = s:cd_to_jobs_cwd(jobinfo)
    if !empty(cd_error)
        throw printf("Neomake: %s: could not change to maker's cwd (%s): %s.",
                    \ maker.name, cwd, cd_error)
    endif

    try
        let error = ''
        let jobinfo.argv = maker._get_argv(jobinfo)
        call neomake#utils#hook('NeomakeJobInit', {'jobinfo': jobinfo})

        if s:async
            call neomake#utils#LoudMessage(printf('Starting async job: %s.', string(jobinfo.argv)), jobinfo)
        else
            call neomake#utils#LoudMessage(printf('Starting: %s.', jobinfo.argv), jobinfo)
        endif
        if empty(cd_back_cmd)
            call neomake#utils#DebugMessage('cwd: '.cwd.'.', jobinfo)
        else
            call neomake#utils#DebugMessage('cwd: '.cwd.' (changed).', jobinfo)
        endif

        if has_key(jobinfo, 'filename')
            let save_env_file = $NEOMAKE_FILE
            let $NEOMAKE_FILE = jobinfo.filename
        endif

        " Lock maker to make sure it does not get changed accidentally, but
        " only with depth=1, so that a postprocess object can change itself.
        lockvar 1 maker
        if s:async
            if has('nvim')
                let opts = {
                    \ 'on_stdout': function('s:nvim_output_handler'),
                    \ 'on_stderr': function('s:nvim_output_handler'),
                    \ 'on_exit': function('s:nvim_exit_handler')
                    \ }
                try
                    let job = jobstart(jobinfo.argv, opts)
                catch
                    let error = printf('Failed to start Neovim job: %s: %s.',
                                \ string(jobinfo.argv), v:exception)
                endtry
                if empty(error)
                    if job == 0
                        let error = printf('Failed to start Neovim job: %s: %s.',
                                    \ 'Job table is full or invalid arguments given', string(jobinfo.argv))
                    elseif job == -1
                        let error = printf('Failed to start Neovim job: %s: %s.',
                                    \ 'Executable not found', string(jobinfo.argv))
                    else
                        let s:map_job_ids[job] = jobinfo.id
                        let jobinfo.nvim_job = job
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
                try
                    let job = job_start(jobinfo.argv, opts)
                    " Get this as early as possible!
                    let channel_id = ch_info(job)['id']
                catch
                    " NOTE: not covered in tests. Vim seems to always return
                    " a job. Might be able to trigger this using custom opts?!
                    let error = printf('Failed to start Vim job: %s: %s',
                                \ jobinfo.argv, v:exception)
                endtry
                if empty(error)
                    let jobinfo.vim_job = job
                    let s:map_job_ids[channel_id] = jobinfo.id
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
                throw 'Neomake: '.error
            endif

            call neomake#utils#hook('NeomakeJobStarted', {'jobinfo': jobinfo})
        else
            " vim-sync.
            " Use a temporary file to capture stderr.
            let stderr_file = tempname()
            let argv = jobinfo.argv . ' 2>'.stderr_file

            try
                if get(jobinfo, 'uses_stdin', 0)
                    let output = system(argv, join(s:make_info[a:make_id].buffer_lines, "\n"))
                else
                    let output = system(argv)
                endif
            catch /^Vim(let):E484:/
                throw printf('Neomake: Could not run %s: %s.', argv, v:exception)
            endtry

            let jobinfo.id = job_id
            let s:jobs[job_id] = jobinfo
            let s:make_info[a:make_id].active_jobs += [jobinfo]

            call s:output_handler(jobinfo, split(output, '\r\?\n', 1), 'stdout')
            let stderr_output = readfile(stderr_file)
            if !empty(stderr_output)
                call map(stderr_output, "substitute(v:val, '\\r$', '', '')")
                call s:output_handler(jobinfo, stderr_output, 'stderr')
            endif
            call delete(stderr_file)

            call s:exit_handler(jobinfo, v:shell_error)
            return jobinfo
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

    let tempfile_enabled = neomake#utils#GetSetting('tempfile_enabled', self, 1, a:jobinfo.ft, a:jobinfo.bufnr)
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
                let dir = tempname()
                let filename = fnamemodify(bufname, ':t')
                let s:make_info[make_id].tempfile_dir = dir
            else
                let dir = fnamemodify(orig_file, ':h')
                if filewritable(dir) != 2
                    let dir = tempname()
                    let s:make_info[make_id].tempfile_dir = dir
                    call neomake#utils#DebugMessage('Using temporary directory for non-writable parent directory.')
                endif
                let filename = fnamemodify(orig_file, ':t')
                            \ .'@neomake_'.s:pid.'_'.make_id
                let ext = fnamemodify(orig_file, ':e')
                if !empty(ext)
                    let filename .= '.'.ext
                endif
                " Use hidden files to make e.g. pytest not trying to import it.
                if filename[0] !=# '.'
                    let filename = '.' . filename
                endif
            endif
            let temp_file = dir . slash . filename
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
        if uses_stdin
            if !has_key(make_info, 'buffer_lines')
                let make_info.buffer_lines = getbufline(bufnr, 1, '$')
            endif
        elseif !has_key(make_info, 'tempfiles')
            let make_info.tempfiles = [temp_file]
            let make_info.created_dirs = s:create_dirs_for_file(temp_file)
            call neomake#utils#write_tempfile(bufnr, temp_file)
        elseif temp_file !=# make_info.tempfiles[0]
            call extend(make_info.created_dirs, s:create_dirs_for_file(temp_file))
            call writefile(readfile(make_info.tempfiles[0], 'b'), temp_file, 'b')
            call add(make_info.tempfiles, temp_file)
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
    return neomake#compat#get_argv(exe, args, args_is_list)
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
        throw printf('Neomake: Invalid maker name: "%s"', a:name_or_maker)
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
                throw 'Neomake: Project maker not found: '.a:name_or_maker
            endif
        endif
        if type(maker) != type({})
            throw printf('Neomake: Got non-dict for maker %s: %s',
                        \ a:name_or_maker, maker)
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
            let maker[key] = neomake#utils#GetSetting(key, maker, default, ft, bufnr, 1)
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
                let log_context = get(get(s:make_info, s:make_id, {}), 'options', {})
                if auto_enabled
                    call neomake#utils#DebugMessage(error, log_context)
                else
                    call neomake#utils#ErrorMessage(error, log_context)
                endif
                continue
            endtry
            let maker.auto_enabled = auto_enabled
            let enabled_makers += [maker]
        endfor
    endif
    return enabled_makers
endfunction

let s:prev_windows = []
function! s:save_prev_windows() abort
    let aw = winnr('#')
    let pw = winnr()
    if exists('*win_getid')
        let aw_id = win_getid(aw)
        let pw_id = win_getid(pw)
    else
        let aw_id = 0
        let pw_id = 0
    endif
    call add(s:prev_windows, [aw, pw, aw_id, pw_id])
endfunction

function! s:restore_prev_windows() abort
    let [aw, pw, aw_id, pw_id] = remove(s:prev_windows, 0)
    if winnr() != pw
        " Go back, maintaining the '#' window (CTRL-W_p).
        if pw_id
            let aw = win_id2win(aw_id)
            let pw = win_id2win(pw_id)
        endif
        if pw
            if aw
                exec aw . 'wincmd w'
            endif
            exec pw . 'wincmd w'
        endif
    endif
endfunction

function! s:HandleLoclistQflistDisplay(file_mode) abort
    let open_val = get(g:, 'neomake_open_list', 0)
    if !open_val
        return
    endif
    let height = get(g:, 'neomake_list_height', 10)
    if !height
        return
    endif
    if a:file_mode
        call neomake#utils#DebugMessage('Handling location list: executing lwindow.')
        let cmd = 'lwindow'
    else
        call neomake#utils#DebugMessage('Handling quickfix list: executing cwindow.')
        let cmd = 'cwindow'
    endif
    if open_val == 2
        call s:save_prev_windows()
        exe cmd height
        call s:restore_prev_windows()
    else
        exe cmd height
    endif
endfunction

let s:action_queue = {'WinEnter': []}
" Queue an action to be processed later for autocmd a:event.
" It will call a:data[0], with a:data[1] as args (where the first should be
" a jobinfo object).  The callback should return 1 if it was successful,
" with 0 it will be re-queued.
" When called recursively (queueing the same event/data again, it will be
" re-queued also).
function! s:queue_action(event, data) abort
    let jobinfo = a:data[1][0]
    call neomake#utils#DebugMessage(printf('Queueing action: %s for %s.',
                \ a:data[0], a:event), jobinfo)
    call add(s:action_queue[a:event], a:data)

    if !exists('#neomake_event_queue#'.a:event)
        augroup neomake_event_queue
            exe 'autocmd '.a:event.' * call s:process_action_queue('''.a:event.''')'
        augroup END
    endif
endfunction

function! s:process_action_queue(event) abort
    let queue = s:action_queue[a:event]
    let queue_len = len(queue)
    call neomake#utils#DebugMessage(printf('action queue: processing for %s (%d items, winnr: %d).',
                \ a:event, queue_len, winnr()), {'bufnr': bufnr('%')})

    let requeue = []
    for _ in range(0, queue_len-1)
        let data = remove(queue, 0)
        let jobinfo = data[1][0]
        if !empty(filter(copy(requeue), 'v:val[1][0] == jobinfo'))
            call neomake#utils#DebugMessage(printf(
                        \ 'action queue: requeueing %s for already requeued action.',
                        \ data[0]), jobinfo)
        else
            call neomake#utils#DebugMessage(printf('action queue: calling %s.',
                        \ data[0]), jobinfo)
            if call(data[0], data[1])
                continue
            else
                call neomake#utils#DebugMessage(printf(
                            \ 'action queue: requeueing %s for failed call.',
                            \ data[0]), jobinfo)
            endif
        endif
        let requeue += [data]
    endfor
    call neomake#utils#DebugMessage(printf('action queue: processed %d items.',
                \ queue_len - len(requeue)), {'bufnr': bufnr('%')})

    " Requeue, but handle already queued actions from nested calls.
    for q in requeue
        if index(queue, q) == -1
            call add(queue, q)
        endif
    endfor
    if empty(queue)
        call s:clean_action_queue_augroup(a:event)
    endif
endfunction

function! s:clean_action_queue_augroup(event) abort
    for v in values(s:action_queue)
        if !empty(v)
            augroup neomake_event_queue
                exe 'au! '.a:event
            augroup END
            return
        endif
    endfor
    autocmd! neomake_event_queue
    augroup! neomake_event_queue
endfunction

function! s:Make(options) abort
    let is_automake = !empty(expand('<abuf>'))
    if is_automake
        let disabled = neomake#config#get_with_source('disabled', 0)
        if disabled[0]
            call neomake#utils#DebugMessage(printf(
                        \ 'Disabled via %s.', disabled[1]))
            return []
        endif
    endif

    let s:make_id += 1
    let make_id = s:make_id
    let options = copy(a:options)
    call extend(options, {
                \ 'file_mode': 1,
                \ 'bufnr': bufnr('%'),
                \ 'ft': &filetype,
                \ 'make_id': make_id,
                \ }, 'keep')
    let bufnr = options.bufnr
    let file_mode = options.file_mode

    let s:make_info[make_id] = {
                \ 'cwd': getcwd(),
                \ 'verbosity': get(g:, 'neomake_verbose', 1),
                \ 'active_jobs': [],
                \ 'finished_jobs': [],
                \ 'options': options,
                \ }
    let make_info = s:make_info[make_id]
    if &verbose
        let make_info.verbosity += &verbose
        call neomake#utils#DebugMessage(printf(
                    \ 'Adding &verbose (%d) to verbosity level: %d.',
                    \ &verbose, make_info.verbosity), options)
    endif

    if has_key(options, 'enabled_makers')
        let makers = options.enabled_makers
        unlet options.enabled_makers
    else
        let makers = call('neomake#GetEnabledMakers', file_mode ? [options.ft] : [])
        if empty(makers)
            if file_mode
                call neomake#utils#DebugMessage('Nothing to make: no enabled file mode makers (filetype='.options.ft.').', options)
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
        call neomake#utils#DebugMessage('Nothing to make: no valid makers.', options)
        call s:clean_make_info(make_id)
        return []
    endif

    let maker_info = join(map(copy(jobs),
                \ "v:val.maker.name . (get(v:val.maker, 'auto_enabled', 0) ? ' (auto)' : '')"), ', ')
    call neomake#utils#DebugMessage(printf(
                \ 'Running makers: %s.', maker_info), options)

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

    " Cancel any already running jobs for the makers from these jobs.
    if !empty(s:jobs)
        " @vimlint(EVL102, 1, l:job)
        for job in jobs
            let running_already = values(filter(copy(s:jobs),
                        \ 'v:val.maker == job.maker'
                        \ .' && v:val.bufnr == job.bufnr'
                        \ ." && !get(v:val, 'canceled')"))
            if !empty(running_already)
                let jobinfo = running_already[0]
                call neomake#utils#LoudMessage(printf(
                            \ 'Cancelling already running job (%d.%d) for the same maker.',
                            \ jobinfo.make_id, jobinfo.id), {'make_id': make_id})
                call neomake#CancelJob(jobinfo.id, 1)
            endif
        endfor
    endif

    " Start all jobs in the queue (until serialized).
    let jobinfos = []
    while 1
        if empty(make_info.jobs_queue)
            break
        endif
        let jobinfo = s:handle_next_job({})
        if empty(jobinfo)
            call s:clean_make_info(make_id)
            break
        endif
        call add(jobinfos, jobinfo)
        if jobinfo.serialize
            " Break and continue through exit handler.
            break
        endif
    endwhile
    return jobinfos
endfunction

function! s:AddExprCallback(jobinfo, prev_list) abort
    if s:need_to_postpone_loclist(a:jobinfo)
        return s:queue_action('WinEnter', ['s:AddExprCallback',
                    \ [a:jobinfo, a:prev_list] + a:000])
    endif
    let maker = a:jobinfo.maker
    let file_mode = a:jobinfo.file_mode
    let list = file_mode ? getloclist(0) : getqflist()
    let index = len(a:prev_list)-1
    unlet! s:postprocess  " vim73
    let s:postprocess = neomake#utils#GetSetting('postprocess', maker, function('neomake#utils#CompressWhitespace'), a:jobinfo.ft, a:jobinfo.bufnr)
    if type(s:postprocess) != type([])
        let s:postprocessors = [s:postprocess]
    else
        let s:postprocessors = s:postprocess
    endif
    let debug = neomake#utils#get_verbosity(a:jobinfo) >= 3 || !empty(get(g:, 'neomake_logfile'))
    let make_info = s:make_info[a:jobinfo.make_id]
    let default_type = 'unset'

    let entries = []
    let changed_entries = {}
    let removed_entries = []
    let different_bufnrs = {}
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
        if debug && entry.bufnr && entry.bufnr != a:jobinfo.bufnr
            if !has_key(different_bufnrs, entry.bufnr)
                let different_bufnrs[entry.bufnr] = 1
            else
                let different_bufnrs[entry.bufnr] += 1
            endif
        endif
        if !empty(s:postprocessors)
            let g:neomake_postprocess_context = {'jobinfo': a:jobinfo}
            try
                for s:f in s:postprocessors
                    if type(s:f) == type({})
                        call call(s:f.fn, [entry], s:f)
                    else
                        call call(s:f, [entry], maker)
                    endif
                    unlet! s:f  " vim73
                endfor
            finally
                unlet! g:neomake_postprocess_context  " Might be unset already with sleep in postprocess.
            endtry
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

    if !empty(different_bufnrs)
        call neomake#utils#DebugMessage(printf('WARN: seen entries with bufnr different from jobinfo.bufnr (%d): %s, current bufnr: %d.', a:jobinfo.bufnr, string(different_bufnrs), bufnr('%')))
    endif

    return s:ProcessEntries(a:jobinfo, entries, a:prev_list)
endfunction

function! s:CleanJobinfo(jobinfo, ...) abort
    if get(a:jobinfo, 'pending_output', 0) && !get(a:jobinfo, 'canceled', 0)
        call neomake#utils#DebugMessage(
                    \ 'Output left to be processed, not cleaning job yet.', a:jobinfo)
        return
    endif

    " Check if there are any queued actions for this job.
    let queued_actions = []
    for q in values(s:action_queue)
        for v in q
            if v[1][0] == a:jobinfo
                let queued_actions += [v[0]]
            endif
        endfor
    endfor
    if !empty(queued_actions)
        call neomake#utils#DebugMessage(printf(
                    \ 'Skipping cleaning of job info because of queued actions: %s.',
                    \ join(queued_actions, ', ')), a:jobinfo)
        return s:queue_action('WinEnter', ['s:CleanJobinfo', [a:jobinfo]])
    endif

    call neomake#utils#DebugMessage('Cleaning jobinfo.', a:jobinfo)

    let make_info = s:make_info[a:jobinfo.make_id]
    call filter(make_info.active_jobs, 'v:val != a:jobinfo')

    if has_key(s:jobs, get(a:jobinfo, 'id', -1))
        call remove(s:jobs, a:jobinfo.id)
        call filter(s:map_job_ids, 'v:val != a:jobinfo.id')

        if has_key(s:pending_outputs, a:jobinfo.id)
            unlet s:pending_outputs[a:jobinfo.id]
        endif
    endif

    if exists('s:kill_vim_timers')
        for [timer, job] in items(s:kill_vim_timers)
            if job == a:jobinfo
                call timer_stop(+timer)
                unlet s:kill_vim_timers[timer]
                break
            endif
        endfor
    endif

    if !get(a:jobinfo, 'canceled', 0)
                \ && !get(a:jobinfo, 'failed_to_start', 0)
        call neomake#utils#hook('NeomakeJobFinished', {'jobinfo': a:jobinfo})
        let make_info.finished_jobs += [a:jobinfo]
    endif

    " Trigger autocmd if all jobs for a s:Make instance have finished.
    if !empty(make_info.active_jobs)
        return
    endif

    if !empty(make_info.jobs_queue)
        return
    endif

    call s:clean_make_info(a:jobinfo.make_id)
    return 1
endfunction

function! s:clean_make_info(make_id, ...) abort
    let make_info = get(s:make_info, a:make_id, {})
    if empty(make_info)
        call neomake#utils#DebugMessage('Make info was cleaned already.', {'make_id': a:make_id})
        return
    endif
    let bang = a:0 ? a:1 : 0
    if !bang && !empty(make_info.active_jobs)
        call neomake#utils#DebugMessage(printf(
                    \ 'Skipping cleaning of make info: %d active jobs.',
                    \ len(make_info.active_jobs)), {'make_id': a:make_id})
        return
    endif
    let queued_jobs = []
    for q in values(s:action_queue)
        for v in q
            if has_key(v[1][0], 'make_id')
                let jobinfo = v[1][0]
                if jobinfo.make_id == a:make_id && v[0] !=# 's:CleanJobinfo'
                    let queued_jobs += [jobinfo.id]
                endif
            else
                let make_id = v[1][0].options.make_id
                if make_id == a:make_id
                    call add(queued_jobs, s:make_info.queued_jobs)
                endif
            endif
        endfor
    endfor
    if !empty(queued_jobs)
        call neomake#utils#DebugMessage(printf(
                    \ 'Skipping cleaning of make info because of queued jobs: %s.',
                    \ join(queued_jobs, ', ')), {'make_id': a:make_id})
        return
    endif

    if !empty(make_info.finished_jobs)
        " Clean old signs after all jobs have finished, so that they can be
        " reused, avoiding flicker and keeping them for longer in general.
        if g:neomake_place_signs
            if make_info.options.file_mode
                call neomake#signs#CleanOldSigns(make_info.options.bufnr, 'file')
            else
                call neomake#signs#CleanAllOldSigns('project')
            endif
        endif
        call neomake#EchoCurrentError(1)
        call s:clean_for_new_make(make_info)
        call s:handle_locqf_list_for_finished_jobs(make_info)
    else
        call s:do_clean_make_info(a:make_id)
    endif
endfunction

function! s:do_clean_make_info(make_id) abort
    let make_info = get(s:make_info, a:make_id, {})

    call neomake#utils#DebugMessage('Cleaning make info.', {'make_id': a:make_id})
    " Remove make_id from its window.
    let [t, w] = s:GetTabWinForMakeId(a:make_id)
    let make_ids = s:gettabwinvar(t, w, 'neomake_make_ids', [])
    let idx = index(make_ids, a:make_id)
    if idx != -1
        call remove(make_ids, idx)
        call settabwinvar(t, w, 'neomake_make_ids', make_ids)
    endif

    let tempfiles = get(make_info, 'tempfiles')
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
            for dir in reverse(copy(get(make_info, 'created_dirs')))
                call delete(dir, 'd')
            endfor
        endif
    endif

    unlet s:make_info[a:make_id]
endfunction

function! s:handle_locqf_list_for_finished_jobs(make_info) abort
    let file_mode = a:make_info.options.file_mode
    let create_list = !get(a:make_info, 'created_locqf_list', 0)

    let open_val = get(g:, 'neomake_open_list', 0)
    let height = open_val ? get(g:, 'neomake_list_height', 10) : 0
    if height
        let close_list = create_list || empty(file_mode ? getloclist(0) : getqflist())
    else
        let close_list = 0
    endif

    if file_mode
        if create_list && !bufexists(a:make_info.options.bufnr)
            call neomake#utils#LoudMessage('No buffer found for location list!', a:make_info.options)
            let create_list = 0
            let close_list = 0
        elseif (create_list || close_list)
            if index(get(w:, 'neomake_make_ids', []), a:make_info.options.make_id) == -1
                call neomake#utils#DebugMessage(
                            \ 'Postponing final location list handling (in another window).',
                            \ {'make_id': a:make_info.options.make_id, 'winnr': winnr()})
                return s:queue_action('WinEnter', ['s:handle_locqf_list_for_finished_jobs',
                            \ [a:make_info] + a:000])
            endif

            let mode = mode()
            if index(['n', 'i'], mode) == -1
                call neomake#utils#DebugMessage(printf(
                            \ 'Postponing final location list handling for mode "%s".', mode),
                            \ a:make_info.options)
                return s:queue_action('WinEnter', ['s:handle_locqf_list_for_finished_jobs',
                            \ [a:make_info] + a:000])
            endif
        endif
    endif

    if create_list
        if file_mode
            call neomake#utils#DebugMessage('Cleaning location list.', {'make_id': a:make_info.options.make_id})
            call setloclist(0, [])
        else
            call neomake#utils#DebugMessage('Cleaning quickfix list.', {'make_id': a:make_info.options.make_id})
            call setqflist([])
        endif
    endif

    " Close empty list.
    if close_list
        if file_mode
            call neomake#utils#DebugMessage('Handling location list: executing lclose.', {'winnr': winnr()})
            lclose
        else
            call neomake#utils#DebugMessage('Handling quickfix list: executing cclose.')
            cclose
        endif
    endif

    " TODO: remove/deprecate jobinfo.
    let hook_context = {
                \ 'make_id': a:make_info.options.make_id,
                \ 'options': a:make_info.options,
                \ 'finished_jobs': a:make_info.finished_jobs,
                \ 'jobinfo': extend(copy(a:make_info.options), {'DEPRECATED': 1}),
                \ }
    call neomake#utils#hook('NeomakeFinished', hook_context)
    call s:do_clean_make_info(a:make_info.options.make_id)
    return 1
endfunction

function! neomake#VimLeave() abort
    call neomake#utils#DebugMessage('Calling VimLeave.')
    for make_id in keys(s:make_info)
        call neomake#CancelMake(make_id)
    endfor
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

function! s:create_locqf_list(make_id, ...) abort
    let make_info = s:make_info[a:make_id]
    if get(make_info, 'created_locqf_list', 0)
        return
    endif
    let make_info.created_locqf_list = 1

    let file_mode = make_info.options.file_mode
    if file_mode
        call neomake#utils#DebugMessage('Creating location list.', {'make_id': a:make_id})
        call setloclist(0, [])
    else
        call neomake#utils#DebugMessage('Creating quickfix list.', {'make_id': a:make_id})
        call setqflist([])
    endif
endfunction

function! s:clean_for_new_make(make_info) abort
    if get(a:make_info, 'cleaned_for_make', 0)
        return
    endif
    let file_mode = a:make_info.options.file_mode
    " XXX: needs to handle buffers for list entries?!
    " See "get_list_entries: minimal example (from doc)" in
    " tests/makers.vader.
    if file_mode
        let bufnr = a:make_info.options.bufnr
        if has_key(s:current_errors['file'], bufnr)
            unlet s:current_errors['file'][bufnr]
        endif
        call neomake#highlights#ResetFile(bufnr)
        call neomake#utils#DebugMessage('File-level errors cleaned.',
                    \ {'make_id': a:make_info.options.make_id, 'bufnr': bufnr})
    else
        " TODO: test
        for buf in keys(s:current_errors.project)
            unlet s:current_errors['project'][buf]
            call neomake#highlights#ResetProject(+buf)
        endfor
    endif
    let a:make_info.cleaned_for_make = 1
endfunction

" Change to a job's cwd, if any.
" Returns: a list:
"  - error (empty for success)
"  - directory changed into (empty if skipped)
"  - command to change back to the current workding dir (might be empty)
function! s:cd_to_jobs_cwd(jobinfo) abort
    let cwd = get(a:jobinfo, 'cwd', s:make_info[a:jobinfo.make_id].cwd)
    if empty(cwd)
        return ['', '', '']
    endif
    let cwd = substitute(fnamemodify(cwd, ':p'), '[\/]$', '', '')
    let cur_wd = getcwd()
    if cwd !=? cur_wd
        let cd = haslocaldir() ? 'lcd' : (exists(':tcd') == 2 && haslocaldir(-1, 0)) ? 'tcd' : 'cd'
        try
            exe cd.' '.fnameescape(cwd)
        catch
            " Tests fail with E344, but in reality it is E472?!
            " If uncaught, both are shown - let's just catch everything.
            let cd_back_cmd = cur_wd ==# getcwd() ? '' : cd.' '.fnameescape(cur_wd)
            return [v:exception, cwd, cd_back_cmd]
        endtry
        return ['', cwd, cd.' '.fnameescape(cur_wd)]
    endif
    return ['', cwd, '']
endfunction

" Call a:fn with a:args and queue it, in case if fails with E48/E523.
function! s:pcall(fn, args) abort
    let jobinfo = a:args[0]
    try
        return call(a:fn, a:args + [1])
    catch /^\%(Vim\%((\a\+)\)\=:\%(E48\|E523\)\)/  " only E48/E523 (sandbox / not allowed here)
        call neomake#utils#DebugMessage('Error during pcall: '.v:exception.'.', jobinfo)
        call neomake#utils#DebugMessage(printf('(in %s)', v:throwpoint), jobinfo)
        call s:queue_action('WinEnter', [a:fn, a:args])
    endtry
    return 0
endfunction

" Do we need to replace (instead of append) the location/quickfix list, for
" :lwindow to not open it with only invalid entries?!
" Without patch-7.4.379 this does not work though, and a new list needs to
" be created (which is not done).
" @vimlint(EVL108, 1)
let s:needs_to_replace_qf_for_lwindow = has('patch-7.4.379')
            \ && (!has('patch-7.4.1752') || (has('nvim') && !has('nvim-0.2.0')))
" @vimlint(EVL108, 0)

function! s:ProcessEntries(jobinfo, entries, ...) abort
    if s:need_to_postpone_loclist(a:jobinfo)
        return s:queue_action('WinEnter', ['s:ProcessEntries',
                    \ [a:jobinfo, a:entries] + a:000])
    endif
    if !a:0 || type(a:[len(a:000)]) != 0
        return s:pcall('s:ProcessEntries', [a:jobinfo, a:entries] + a:000)
    endif
    let file_mode = a:jobinfo.file_mode

    call neomake#utils#DebugMessage(printf(
                \ 'Processing %d entries.', len(a:entries)), a:jobinfo)

    call s:create_locqf_list(a:jobinfo.make_id)
    call s:clean_for_new_make(s:make_info[a:jobinfo.make_id])

    if a:0 > 1
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

        let [cd_error, cwd, cd_back_cmd] = s:cd_to_jobs_cwd(a:jobinfo)
        if !empty(cd_error)
            call neomake#utils#DebugMessage(printf(
                        \ "Could not change to job's cwd (%s): %s.",
                        \ cwd, cd_error), a:jobinfo)
        endif
        try
            if file_mode
                if s:needs_to_replace_qf_for_lwindow
                    call setloclist(0, getloclist(0) + a:entries, 'r')
                else
                    call setloclist(0, a:entries, 'a')
                endif
            else
                if s:needs_to_replace_qf_for_lwindow
                    call setqflist(getqflist() + a:entries, 'r')
                else
                    call setqflist(a:entries, 'a')
                endif
            endif
        finally
            if empty(cd_error)
                exe cd_back_cmd
            endif
        endtry
        if file_mode
            let parsed_entries = getloclist(0)[len(prev_list):]
        else
            let parsed_entries = getqflist()[len(prev_list):]
        endif
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
        " Assert !counts_changed, string([file_mode, prev_list, getloclist(0)])
    endif
    if counts_changed
        call neomake#utils#hook('NeomakeCountsChanged', {'reset': 0, 'jobinfo': a:jobinfo})
    endif

    call s:HandleLoclistQflistDisplay(a:jobinfo.file_mode)
    call neomake#highlights#ShowHighlights()
    return 1
endfunction

function! s:ProcessJobOutput(jobinfo, lines, source, ...) abort
    if s:need_to_postpone_loclist(a:jobinfo)
        return s:queue_action('WinEnter', ['s:ProcessJobOutput',
                    \ [a:jobinfo, a:lines, a:source]])
    endif
    if !a:0
        return s:pcall('s:ProcessJobOutput', [a:jobinfo, a:lines, a:source])
    endif

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
            return s:ProcessEntries(a:jobinfo, entries)
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

        let [cd_error, cwd, cd_back_cmd] = s:cd_to_jobs_cwd(a:jobinfo)
        if !empty(cd_error)
            call neomake#utils#DebugMessage(printf(
                        \ "Could not change to job's cwd (%s): %s.",
                        \ cwd, cd_error), a:jobinfo)
        endif

        call s:create_locqf_list(a:jobinfo.make_id)
        let prev_list = file_mode ? getloclist(0) : getqflist()

        if exists('g:loaded_qf')
            let vimqf_var = file_mode ? 'qf_auto_open_loclist' : 'qf_auto_open_quickfix'
            let vimqf_val = get(g:, vimqf_var, s:unset_dict)
            if vimqf_val isnot# 0
                let restore_vimqf = [vimqf_var, vimqf_val]
                let g:[vimqf_var] = 0
            endif
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
            if empty(cd_error)
                exe cd_back_cmd
            endif
            if exists('restore_vimqf')
                if restore_vimqf[1] is# s:unset_dict
                    unlet g:[restore_vimqf[0]]
                else
                    let g:[restore_vimqf[0]] = restore_vimqf[1]
                endif
            endif
        endtry

        call s:AddExprCallback(a:jobinfo, prev_list)
    catch /^\%(Vim\%((\a\+)\)\=:\%(E48\|E523\)\)\@!/  " everything, but E48/E523 (sandbox / not allowed here)
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
    return 1
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
                let w:neomake_make_ids = add(get(w:, 'neomake_make_ids', []), jobinfo.make_id)
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

" Do we need to postpone location list processing (creation and :laddexpr)?
function! s:need_to_postpone_loclist(jobinfo) abort
    if !a:jobinfo.file_mode
        return 0
    endif
    if index(get(w:, 'neomake_make_ids', []), a:jobinfo.make_id) != -1
        return 0
    endif
    call neomake#utils#DebugMessage('Postponing location list processing.', a:jobinfo)
    return 1
endfunction

function! s:RegisterJobOutput(jobinfo, lines, source) abort
    if a:jobinfo.output_stream !=# 'both' && a:jobinfo.output_stream !=# a:source
        if !has_key(a:jobinfo, 'unexpected_output')
            let a:jobinfo.unexpected_output = {}
        endif
        if !has_key(a:jobinfo.unexpected_output, a:source)
            let a:jobinfo.unexpected_output[a:source] = []
        endif
        let a:jobinfo.unexpected_output[a:source] += a:lines
        return
    endif

    if s:CanProcessJobOutput() && !s:need_to_postpone_loclist(a:jobinfo)
        if !empty(s:pending_outputs)
            call s:ProcessPendingOutputs()
        endif
        call s:ProcessJobOutput(a:jobinfo, a:lines, a:source)
        return
    endif
    call s:add_pending_output(a:jobinfo, a:source, a:lines)
endfunction

function! s:vim_output_handler(channel, output, event_type) abort
    let channel_id = ch_info(a:channel)['id']
    let jobinfo = get(s:jobs, get(s:map_job_ids, channel_id, -1), {})
    if empty(jobinfo)
        call neomake#utils#DebugMessage(printf("output [%s]: job '%s' not found.", a:event_type, a:channel))
        return
    endif

    let data = split(a:output, '\v\r?\n', 1)

    if exists('jobinfo._vim_in_handler')
        call neomake#utils#DebugMessage(printf('Queueing: %s: %s: %s.',
                    \ a:event_type, jobinfo.maker.name, string(data)), jobinfo)
        let jobinfo._vim_in_handler += [[jobinfo, data, a:event_type]]
        return
    else
        let jobinfo._vim_in_handler = []
    endif

    call s:output_handler(jobinfo, data, a:event_type)

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
            call s:exit_handler(jobinfo, jobinfo._exited_while_in_handler)
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
    let channel_id = ch_info(a:channel)['id']
    let jobinfo = get(s:jobs, get(s:map_job_ids, channel_id, -1), {})
    if empty(jobinfo)
        try
            let job_info = job_info(ch_getjob(a:channel))
        catch /^Vim(let):E916:/
            call neomake#utils#DebugMessage(printf('exit: job not found: %s.', a:channel))
            return
        endtry
        call neomake#utils#DebugMessage(printf('exit: job not found: %s (%s).', a:channel, job_info))
        return
    endif
    let job_info = job_info(ch_getjob(a:channel))

    " Handle failing starts from Vim here.
    let status = job_info['exitval']
    if status == 122  " Vim uses EXEC_FAILED, but only on Unix?!
        let jobinfo.failed_to_start = 1
        " The error is on stderr.
        let error = 'Vim job failed to run: '.substitute(join(jobinfo.stderr), '\v\s+$', '', '').'.'
        let jobinfo.stderr = []
        call neomake#utils#ErrorMessage(error)
        call s:CleanJobinfo(jobinfo)
    else
        call s:exit_handler(jobinfo, status)
    endif
endfunction

" @vimlint(EVL108, 1)
if has('nvim-0.2.0')
" @vimlint(EVL108, 0)
    function! s:nvim_output_handler(job_id, data, event_type) abort
        let jobinfo = get(s:jobs, get(s:map_job_ids, a:job_id, -1), {})
        if empty(jobinfo)
            call neomake#utils#DebugMessage(printf('output [%s]: job %d not found.', a:event_type, a:job_id))
            return
        endif
        let data = map(copy(a:data), "substitute(v:val, '\\r$', '', '')")
        call s:output_handler(jobinfo, data, a:event_type)
    endfunction
else
    " Neovim: register output from jobs as quick as possible, and trigger
    " processing through a timer.
    " This works around https://github.com/neovim/neovim/issues/5889).
    let s:nvim_output_handler_queue = []
    function! s:nvim_output_handler(job_id, data, event_type) abort
        let jobinfo = get(s:jobs, get(s:map_job_ids, a:job_id, -1), {})
        if empty(jobinfo)
            call neomake#utils#DebugMessage(printf('output [%s]: job %d not found.', a:event_type, a:job_id))
            return
        endif
        let data = map(copy(a:data), "substitute(v:val, '\\r$', '', '')")
        let args = [jobinfo, data, a:event_type]
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
            let jobinfo = args[0]
            call call('s:output_handler', args)
            let jobinfo._nvim_in_handler -= 1

            if !jobinfo._nvim_in_handler
                " Trigger previously delayed exit handler.
                unlet jobinfo._nvim_in_handler
                if exists('jobinfo._exited_while_in_handler')
                    call neomake#utils#DebugMessage('Trigger delayed exit.', jobinfo)
                    call s:exit_handler(jobinfo, jobinfo._exited_while_in_handler)
                endif
            endif
        endwhile
        unlet! s:nvim_output_handler_timer
    endfunction
    " @vimlint(EVL103, 0, a:timer)
endif

" @vimlint(EVL103, 1, a:event_type)
function! s:nvim_exit_handler(job_id, data, event_type) abort
    let jobinfo = get(s:jobs, get(s:map_job_ids, a:job_id, -1), {})
    if empty(jobinfo)
        call neomake#utils#DebugMessage(printf('exit: job not found: %d.', a:job_id))
        return
    endif
    call s:exit_handler(jobinfo, a:data)
endfunction
" @vimlint(EVL103, 0, a:event_type)

function! s:exit_handler(jobinfo, data) abort
    let jobinfo = a:jobinfo
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
    call neomake#utils#DebugMessage(printf('exit: %s: %s.',
                \ maker.name, string(a:data)), jobinfo)

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
            try
                if type(l:ExitCallback) == type('')
                    let l:ExitCallback = function(l:ExitCallback)
                endif
                call call(l:ExitCallback, [callback_dict], jobinfo)
            catch
                call neomake#utils#ErrorMessage(printf(
                            \ 'Error during exit_callback: %s.', v:exception),
                            \ jobinfo)
            endtry
        endif
    endif

    if s:async
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

    if has_key(jobinfo, 'unexpected_output')
        redraw
        for [source, output] in items(jobinfo.unexpected_output)
            let msg = printf('%s: unexpected output on %s: ', maker.name, source)
            call neomake#utils#DebugMessage(msg . join(output, '\n') . '.', jobinfo)

            echohl WarningMsg
            echom printf('Neomake: %s%s', msg, output[0])
            for line in output[1:-1]
                echom line
            endfor
            echohl None
        endfor
        call neomake#utils#ErrorMessage(printf(
                    \ '%s: unexpected output. See :messages for more information.', maker.name), jobinfo)
    endif
    call s:handle_next_job(jobinfo)
endfunction

function! s:output_handler(jobinfo, data, event_type) abort
    let jobinfo = a:jobinfo
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
        call neomake#utils#LoudMessage('Aborting next makers: '.next_makers.'.', {'make_id': a:make_id})
        let s:make_info[a:make_id].jobs_queue = []
    endif
endfunction

function! s:handle_next_job(prev_jobinfo) abort
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

    " Create job from the start of the queue, returning it.
    while !empty(make_info.jobs_queue)
        let options = remove(make_info.jobs_queue, 0)
        let maker = options.maker
        if empty(maker)
            continue
        endif

        " Serialization of jobs, always for non-async Vim.
        if !has_key(options, 'serialize')
            if !s:async || neomake#utils#GetSetting('serialize', maker, 0, options.ft, options.bufnr)
                let options.serialize = 1
            else
                let options.serialize = 0
            endif
        endif
        try
            let jobinfo = s:MakeJob(make_id, options)
        catch /^Neomake: /
            let error = substitute(v:exception, '^Neomake: ', '', '')
            call neomake#utils#ErrorMessage(error, {'make_id': make_id})

            if options.serialize && neomake#utils#GetSetting('serialize_abort_on_error', maker, 0, options.ft, options.bufnr)
                call s:abort_next_makers(make_id)
                break
            endif
            if options.serialize
                if neomake#utils#GetSetting('serialize_abort_on_error', maker, 0, options.ft, options.bufnr)
                    call s:abort_next_makers(make_id)
                    break
                endif
                if empty(make_info.jobs_queue)
                    call s:clean_make_info(make_id)
                endif
            endif
            continue
        endtry
        if !empty(jobinfo)
            return jobinfo
        endif
    endwhile
    return {}
endfunction

function! neomake#GetCurrentErrorMsg() abort
    let buf = bufnr('%')
    let ln = line('.')
    let ln_errors = []

    for maker_type in ['file', 'project']
        let buf_errors = get(s:current_errors[maker_type], buf, {})
        let ln_errors += get(buf_errors, ln, [])
    endfor

    if empty(ln_errors)
        return ''
    endif

    if len(ln_errors) > 1
        let ln_errors = copy(ln_errors)
        call sort(ln_errors, function('neomake#utils#sort_by_col'))
    endif
    let entry = ln_errors[0]
    let r = entry.maker_name . ': ' . entry.text
    let suffix = entry.type . (entry.nr != -1 ? entry.nr : '')
    if !empty(suffix)
        let r .= ' ('.suffix.')'
    endif
    return r
endfunction

function! neomake#EchoCurrentError(...) abort
    " a:1 might be a timer from the VimResized event.
    let force = a:0 ? a:1 : 0
    if !force && !get(g:, 'neomake_echo_current_error', 1)
        return
    endif

    let message = neomake#GetCurrentErrorMsg()
    if empty(message)
        if exists('s:neomake_last_echoed_error')
            echon ''
            unlet s:neomake_last_echoed_error
        endif
        return
    endif
    if !force && exists('s:neomake_last_echoed_error')
                \ && s:neomake_last_echoed_error == message
        return
    endif
    let s:neomake_last_echoed_error = message
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
                            call neomake#utils#ErrorMessage(error, options)
                        else
                            call neomake#utils#DebugMessage(error, options)
                        endif
                    else
                        call neomake#utils#DebugMessage(printf(
                                    \ 'Exe (%s) of auto-configured maker %s is not executable, skipping.', maker.exe, maker.name), options)
                    endif
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
    return map(copy(s:Make(options)), 'v:val.id')
endfunction

function! neomake#ShCommand(bang, sh_command, ...) abort
    let maker = neomake#utils#MakerFromCommand(a:sh_command)
    let maker.name = 'sh: '.a:sh_command
    let maker.buffer_output = !a:bang
    let maker.errorformat = '%m'
    let maker.default_entry_type = ''
    let options = {
                \ 'enabled_makers': [maker],
                \ 'file_mode': 0,
                \ 'output_stream': 'both'}
    if a:0
        call extend(options, a:1)
    endif
    let jobinfos = s:Make(options)
    return empty(jobinfos) ? -1 : jobinfos[0].id
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
    if &verbose
        echo '#### Neomake debug information'
        echo 'Async support: '.s:async
        echo 'Current filetype: '.ft
        echo 'Windows: '.neomake#utils#IsRunningWindows()
        echo '[shell, shellcmdflag, shellslash]:' [&shell, &shellcmdflag, &shellslash]
        echo "\n"
    else
        echo '#### Neomake information (use ":verbose NeomakeInfo" extra output)'
    endif
    echo '##### Enabled makers'
    echo 'For the current filetype ("'.ft.'", used with :Neomake):'
    call s:display_maker_info(ft)
    if empty(ft)
        echo 'NOTE: the current buffer does not have a filetype.'
    else
        let conf_ft = neomake#utils#get_ft_confname(ft)
        echo 'NOTE: you can define g:neomake_'.conf_ft.'_enabled_makers'
                    \ .' to configure it (or b:neomake_'.conf_ft.'_enabled_makers).'
    endif
    echo "\n"
    echo 'For the project (used with :Neomake!):'
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
    verb set makeprg?
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
