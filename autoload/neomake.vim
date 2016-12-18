" vim: ts=4 sw=4 et
scriptencoding utf-8

let s:make_id = 0
let s:job_id = 1
let s:jobs = {}
let s:jobs_by_maker = {}
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
            \ 'remove_invalid_entries': 1}
let s:project_job_output = {}
" List of job ids with pending output per buffer.
let s:buffer_job_output = {}

function! neomake#has_async_support() abort
    return has('nvim') ||
                \ has('channel') && has('job') && has('patch-8.0.0027')
endfunction

function! s:sort_jobs(a, b) abort
    return a:a.id - a:b.id
endfunction

function! neomake#GetJobs(...) abort
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
                \ }
endfunction

function! neomake#ListJobs() abort
    call neomake#utils#DebugMessage('call neomake#ListJobs()')
    for jobinfo in values(s:jobs)
        echom jobinfo.id.' '.jobinfo.name
    endfor
endfunction

function! neomake#CancelJob(job_id, ...) abort
    let remove_on_error = a:0 ? a:1 : 0
    " Handle '1: foo' format from neomake#CompleteJobs.
    let job_id = a:job_id + 0
    if !has_key(s:jobs, job_id)
        call neomake#utils#ErrorMessage('CancelJob: job not found: '.job_id)
        return 0
    endif
    let jobinfo = s:jobs[job_id]
    if get(jobinfo, 'finished')
        call neomake#utils#DebugMessage('Removing already finished job: '.job_id)
        call s:CleanJobinfo(jobinfo)
    else
        " Mark it as canceled for the exit handler.
        let jobinfo.canceled = 1
        call neomake#utils#DebugMessage('Stopping job: '.job_id, jobinfo)
        if has('nvim')
            try
                call jobstop(job_id)
            catch /^Vim\%((\a\+)\)\=:\(E474\|E900\):/
                call neomake#utils#LoudMessage(printf(
                            \ 'jobstop failed: %s', v:exception), jobinfo)
                if remove_on_error
                    unlet s:jobs[job_id]
                endif
                return 0
            endtry
        else
            if v:version < 800 || v:version == 800 && !has('patch45')
                " Vim before 8.0.0045 might fail to stop a job right away.
                sleep 50m
            endif
            let vim_job = s:jobs[job_id].vim_job
            if job_status(vim_job) !=# 'run'
                call neomake#utils#LoudMessage(
                            \ 'job_stop: job was not running anymore', jobinfo)
                if remove_on_error
                    unlet s:jobs[job_id]
                endif
                return 0
            endif
            call job_stop(vim_job)
        endif
    endif
    return 1
endfunction

function! neomake#CancelJobs(bang) abort
    for job in neomake#GetJobs()
        call neomake#CancelJob(job.id, a:bang)
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

function! s:AddJobinfoForCurrentWin(job_id) abort
    " Add jobinfo to current window.
    let tabpagenr = tabpagenr()
    let winnr = winnr()
    let win_jobs = s:gettabwinvar(tabpagenr, winnr, 'neomake_jobs', [])
    let win_jobs += [a:job_id]
    call settabwinvar(tabpagenr, winnr, 'neomake_jobs', win_jobs)
endfunction

function! s:MakeJob(make_id, options) abort
    let job_id = s:job_id
    let s:job_id += 1
    let maker = a:options.maker
    let jobinfo = {
        \ 'name': 'neomake_'.job_id,
        \ 'winnr': winnr(),
        \ 'bufnr': bufnr('%'),
        \ 'file_mode': a:options.file_mode,
        \ 'maker': maker,
        \ 'make_id': a:make_id,
        \ }

    " Resolve exe/args, which might be a function or dictionary.
    if type(maker.exe) == type(function('tr'))
        let exe = call(maker.exe, [])
    elseif type(maker.exe) == type({})
        let exe = call(maker.exe.fn, [], maker.exe)
    else
        let exe = maker.exe
    endif
    if type(maker.args) == type(function('tr'))
        let args = call(maker.args, [])
    elseif type(maker.args) == type({})
        let args = call(maker.args.fn, [], maker.args)
    else
        let args = copy(maker.args)
    endif
    let args_is_list = type(args) == type([])

    if a:options.file_mode && get(maker, 'append_file', 1)
        if args_is_list
            call neomake#utils#ExpandArgs(args)
            call add(args, expand('%:p'))
        else
            let args .= ' '.fnameescape(expand('%:p'))
        endif
    endif

    if has_key(maker, 'cwd')
        let old_wd = getcwd()
        let cwd = expand(maker.cwd, 1)
        try
            exe 'cd' fnameescape(cwd)
        " Tests fail with E344, but in reality it is E472?!
        " If uncaught, both are shown.  Let's just catch every error here.
        catch
            call neomake#utils#ErrorMessage(
                        \ maker.name.": could not change to maker's cwd (".cwd.'): '
                        \ .v:exception, jobinfo)
            return -1
        endtry
    endif

    try
        let error = ''
        if neomake#has_async_support()
            if args_is_list
                let argv = [exe] + args
            else
                let argv = exe . (len(args) ? ' ' . args : '')
            endif
            if has('nvim')
                let opts = {
                    \ 'on_stdout': function('neomake#MakeHandler'),
                    \ 'on_stderr': function('neomake#MakeHandler'),
                    \ 'on_exit': function('neomake#MakeHandler')
                    \ }
                try
                    call neomake#utils#LoudMessage(printf(
                                \ 'Starting async job: %s',
                                \ string(argv)), jobinfo)
                    let job = jobstart(argv, opts)
                catch
                    let error = printf('Failed to start Neovim job: %s: %s',
                                \ string(argv), v:exception)
                endtry
                if empty(error)
                    if job == 0
                        let error = 'Job table is full or invalid arguments given'
                    elseif job == -1
                        " Never happens?!
                        " https://github.com/neovim/neovim/issues/5465
                        let error = 'Executable not found'
                    else
                        let jobinfo.id = job
                        let s:jobs[jobinfo.id] = jobinfo
                    endif
                endif
            else
                " vim-async.
                let opts = {
                            \ 'err_cb': 'neomake#MakeHandlerVimStderr',
                            \ 'out_cb': 'neomake#MakeHandlerVimStdout',
                            \ 'close_cb': 'neomake#MakeHandlerVimClose',
                            \ 'mode': 'raw',
                            \ }
                if neomake#utils#IsRunningWindows()
                    let argv = &shell.' '.&shellcmdflag.' '.shellescape(args_is_list ? join(argv) : argv)
                elseif !args_is_list
                    let argv = [&shell, &shellcmdflag, argv]
                endif
                try
                    call neomake#utils#LoudMessage(printf(
                                \ 'Starting async job: %s',
                                \ string(argv)), jobinfo)
                    let job = job_start(argv, opts)
                    " Get this as early as possible!
                    " XXX: the job might be finished already before the setup
                    "      is done completely!
                    let job_status = job_status(job)
                    let jobinfo.id = ch_info(job)['id']
                    let jobinfo.vim_job = job
                    let s:jobs[jobinfo.id] = jobinfo
                catch
                    let error = printf('Failed to start Vim job: %s: %s',
                                \ argv, v:exception)
                endtry
                if job_status !=# 'run'
                    let error = printf('Vim job failed to run: %s', string(job))
                endif
                if empty(error)
                    call neomake#utils#DebugMessage(printf('Vim job: %s',
                                \ string(job_info(job))), jobinfo)
                    call neomake#utils#DebugMessage(printf('Vim channel: %s',
                                \ string(ch_info(job))), jobinfo)
                endif
            endif

            " Bail out on errors.
            if len(error)
                call neomake#utils#LoudMessage(error)
                return -1
            endif

            call s:AddJobinfoForCurrentWin(jobinfo.id)
            let r = jobinfo.id
        else
            call neomake#utils#DebugMessage('Running synchronously')
            let program = exe
            if len(args)
                if args_is_list
                    if neomake#utils#IsRunningWindows()
                        let program .= ' '.join(args)
                    else
                        let program .= ' '.join(map(args, 'shellescape(v:val)'))
                    endif
                else
                    let program .= ' '.args
                endif
            endif

            call neomake#utils#LoudMessage('Starting: ' . program)

            let jobinfo.id = job_id
            let s:jobs[job_id] = jobinfo
            call s:AddJobinfoForCurrentWin(jobinfo.id)
            call neomake#MakeHandler(job_id, split(system(program), '\r\?\n', 1), 'stdout')
            call neomake#MakeHandler(job_id, v:shell_error, 'exit')
            let r = -1
        endif
    finally
        if exists('old_wd')
            exe 'cd' fnameescape(old_wd)
        endif
    endtry
    return r
endfunction

function! neomake#GetMaker(name_or_maker, ...) abort
    if a:0
        let real_ft = a:1
        let fts = neomake#utils#GetSortedFiletypes(real_ft)
    else
        let fts = []
    endif
    if type(a:name_or_maker) == type({})
        let maker = a:name_or_maker
    elseif a:name_or_maker ==# 'makeprg'
        let maker = neomake#utils#MakerFromCommand(&makeprg)
    elseif a:name_or_maker !~# '\v^\w+$'
        call neomake#utils#ErrorMessage('Invalid maker name: '.a:name_or_maker)
        return {}
    else
        if len(fts)
            for ft in fts
                let m = get(g:, 'neomake_'.ft.'_'.a:name_or_maker.'_maker')
                if type(m) == type({})
                    let maker = m
                    break
                endif
                unlet m
            endfor
        elseif exists('g:neomake_'.a:name_or_maker.'_maker')
            let maker = get(g:, 'neomake_'.a:name_or_maker.'_maker')
        endif
        if !exists('maker')
            if len(fts)
                for ft in fts
                    try
                        let maker = eval('neomake#makers#ft#'.ft.'#'.a:name_or_maker.'()')
                        break
                    catch /^Vim\%((\a\+)\)\=:E117/
                    endtry
                endfor
            else
                try
                    let maker = eval('neomake#makers#'.a:name_or_maker.'#'.a:name_or_maker.'()')
                catch /^Vim\%((\a\+)\)\=:E117/
                endtry
            endif
        endif
        if !exists('maker')
            call neomake#utils#ErrorMessage('Maker not found: '.a:name_or_maker)
            return {}
        endif
    endif
    let maker = deepcopy(maker)
    if !has_key(maker, 'name')
        if type(a:name_or_maker) == type('')
            let maker.name = a:name_or_maker
        else
            let maker.name = 'unnamed_maker'
        endif
    endif
    let defaults = copy(s:maker_defaults)
    call extend(defaults, {
        \ 'exe': maker.name,
        \ 'args': [],
        \ 'errorformat': &errorformat,
        \ })
    let bufnr = bufnr('%')
    for [key, default] in items(defaults)
        let maker[key] = neomake#utils#GetSetting(key, maker, default, fts, bufnr)
        unlet! default  " workaround for old Vim (7.3.429)
    endfor
    let s:UNSET = {}
    for key in ['append_file']
        let value = neomake#utils#GetSetting(key, maker, s:UNSET, fts, bufnr)
        if value isnot s:UNSET
            let maker[key] = value
        endif
        unlet! value  " workaround for old Vim (7.3.429)
    endfor
    if exists('real_ft')
        let maker.ft = real_ft
    endif
    return maker
endfunction

function! neomake#GetMakers(ft) abort
    " Get all makers for a given filetype.  This is used from completion.
    " XXX: this should probably use a callback or some other more stable
    " approach to get the list of makers (than looking at the lowercase
    " functions)?!

    let makers = []
    let makers_count = {}
    let fts = neomake#utils#GetSortedFiletypes(a:ft)
    for ft in fts
        let ft = substitute(ft, '\W', '_', 'g')
        " Trigger sourcing of the autoload file.
        try
            exe 'call neomake#makers#ft#'.ft.'#EnabledMakers()'
        catch /^Vim\%((\a\+)\)\=:E117/
            continue
        endtry
        let funcs_output = neomake#utils#redir('fun /neomake#makers#ft#'.ft.'#\l')
        for maker_name in map(split(funcs_output, '\n'),
                    \ "substitute(v:val, '\\v^.*#(.*)\\(.*$', '\\1', '')")
            let c = get(makers_count, maker_name, 0)
            let makers_count[maker_name] = c + 1
            " Add each maker only once, but keep the order.
            if c == 0
                let makers += [maker_name]
            endif
        endfor
    endfor
    let l = len(fts)
    return filter(makers, 'makers_count[v:val] ==# l')
endfunction

function! neomake#GetProjectMakers() abort
    runtime! autoload/neomake/makers/*.vim
    let funcs_output = neomake#utils#redir('fun /neomake#makers#\(ft#\)\@!\l')
    return map(split(funcs_output, '\n'),
                \ "substitute(v:val, '\\v^.*#(.*)\\(.*$', '\\1', '')")
endfunction

function! neomake#GetEnabledMakers(...) abort
    if !a:0 || type(a:1) !=# type('')
        " If we have no filetype, use the global default makers.
        " This variable is also used for project jobs, so it has no
        " buffer local ('b:') counterpart for now.
        return get(g:, 'neomake_enabled_makers', [])
    endif

    " If a filetype was passed, get the makers that are enabled for each of
    " the filetypes represented.
    let makers = []
    let makers_count = {}
    let fts = neomake#utils#GetSortedFiletypes(a:1)
    for ft in fts
        let ft = substitute(ft, '\W', '_', 'g')
        unlet! l:enabled_makers
        for l:varname in [
                    \ 'b:neomake_'.ft.'_enabled_makers',
                    \ 'g:neomake_'.ft.'_enabled_makers']
            if exists(l:varname)
                let l:enabled_makers = eval(l:varname)
                break
            endif
        endfor

        " Use plugin's defaults if not customized.
        if !exists('l:enabled_makers')
            try
                let fnname = 'neomake#makers#ft#'.ft.'#EnabledMakers'
                let default_makers = eval(fnname . '()')
            catch /^Vim\%((\a\+)\)\=:E117/
                let default_makers = []
            endtry
            let l:enabled_makers = neomake#utils#AvailableMakers(ft, default_makers)
        endif

        " @vimlint(EVL104, 1, l:enabled_makers)
        for maker_name in l:enabled_makers
            let c = get(makers_count, maker_name, 0)
            let makers_count[maker_name] = c + 1
            " Add each maker only once, but keep the order.
            if c == 0
                let makers += [maker_name]
            endif
        endfor
    endfor

    let l = len(fts)
    return filter(makers, 'makers_count[v:val] ==# l')
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

function! s:Make(options, ...) abort
    let file_mode = get(a:options, 'file_mode', 0)
    let enabled_makers = get(a:options, 'enabled_makers', [])
    if !len(enabled_makers)
        if file_mode
            call neomake#utils#DebugMessage('Nothing to make: no enabled makers.')
            return []
        endif
        let enabled_makers = ['makeprg']
    endif

    if a:0
        let make_id = a:1
    else
        let s:make_id += 1
        let make_id = s:make_id
    endif

    let buf = bufnr('%')
    let ft = get(a:options, 'ft', '')

    if file_mode
        call neomake#statusline#ResetCountsForBuf(buf)
    else
        call neomake#statusline#ResetCountsForProject()
    endif

    " Empty the quickfix/location list (using a valid 'errorformat' setting).
    let l:efm = &errorformat
    try
        let &errorformat = '%-G'
        if file_mode
            lgetexpr ''
        else
            cgetexpr ''
        endif
    finally
        let &errorformat = l:efm
    endtry
    call s:HandleLoclistQflistDisplay(file_mode)

    if !get(a:options, 'continuation')
        " Only do this if we have one or more enabled makers
        if file_mode
            if g:neomake_place_signs
                call neomake#signs#ResetFile(buf)
            endif
            let s:need_errors_cleaning['file'][buf] = 1
        else
            if g:neomake_place_signs
                call neomake#signs#ResetProject()
            endif
            let s:need_errors_cleaning['project'] = 1
        endif
    endif

    let serialize = get(g:, 'neomake_serialize')
    let job_ids = []

    let enabled_makers = map(copy(enabled_makers), 'neomake#GetMaker(v:val, ft)')
    call neomake#utils#DebugMessage(printf('Running makers: %s (%s)',
                \ join(map(copy(enabled_makers), 'v:val.name'), ', '),
                \ string(enabled_makers)), {'make_id': make_id})
    let maker = {}
    while len(enabled_makers)
        let maker = remove(enabled_makers, 0)
        if empty(maker)
            continue
        endif

        " Check for already running job for the same maker.
        " This used to use this key: maker.name.',ft='.maker.ft.',buf='.maker.bufnr
        if len(s:jobs)
            let running_already = values(filter(copy(s:jobs),
                        \ 'v:val.maker == maker'
                        \ .' && v:val.bufnr == buf'))
            if len(running_already)
                let jobinfo = running_already[0]
                let jobinfo.maker.next = copy(a:options)
                " TODO: required?! (
                let jobinfo.maker.next.enabled_makers = [maker] + enabled_makers
                call neomake#utils#LoudMessage('Found already running job for the same maker, restarting.', jobinfo)
                call neomake#CancelJob(jobinfo.id)
                break
            endif
        endif
        if serialize && len(enabled_makers) > 0
            let next_opts = copy(a:options)
            let next_opts.enabled_makers = enabled_makers
            let next_opts.continuation = 1
            let maker.next = next_opts
        endif
        let options = {
                    \ 'file_mode': file_mode,
                    \ 'maker': maker,
                    \ }
        if has_key(a:options, 'exit_callback')
            let options.exit_callback = a:options.exit_callback
        endif
        let job_id = s:MakeJob(make_id, options)
        if job_id != -1
            call add(job_ids, job_id)
        endif
        " If we are serializing makers, stop after the first one. The
        " remaining makers will be processed in turn when this one is done.
        if serialize
            break
        endif
    endwhile
    return job_ids
endfunction

function! s:AddExprCallback(jobinfo, prev_index) abort
    let maker = a:jobinfo.maker
    let file_mode = a:jobinfo.file_mode
    let highlight_columns = get(g:, 'neomake_highlight_columns', 1)
    let highlight_lines = get(g:, 'neomake_highlight_lines', 0)
    let list = file_mode ? getloclist(0) : getqflist()
    let list_modified = 0
    let counts_changed = 0
    let index = a:prev_index
    let maker_type = file_mode ? 'file' : 'project'
    let cleaned_signs = 0
    let ignored_signs = 0

    while index < len(list)
        let entry = list[index]
        let entry.maker_name = has_key(maker, 'name') ? maker.name : 'makeprg'
        let index += 1

        if has_key(maker, 'postprocess')
            if list_modified
                call maker.postprocess(entry)
            else
                let before = copy(entry)
                call maker.postprocess(entry)
                if entry != before
                    let list_modified = 1
                endif
            endif
        endif

        if !entry.valid
            if maker.remove_invalid_entries
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

        if !cleaned_signs
            if file_mode
                call neomake#CleanOldFileSignsAndErrors(entry.bufnr)
            else
                call neomake#CleanOldProjectSignsAndErrors()
            endif
            let cleaned_signs = 1
        endif

        " Track all errors by buffer and line
        let s:current_errors[maker_type][entry.bufnr] = get(s:current_errors[maker_type], entry.bufnr, {})
        let s:current_errors[maker_type][entry.bufnr][entry.lnum] = get(
            \ s:current_errors[maker_type][entry.bufnr], entry.lnum, [])
        call add(s:current_errors[maker_type][entry.bufnr][entry.lnum], entry)

        if g:neomake_place_signs
            if entry.lnum is 0
                let ignored_signs += 1
            else
                call neomake#signs#RegisterSign(entry, maker_type)
            endif
        endif
        if highlight_columns || highlight_lines
            call neomake#highlights#AddHighlight(entry, maker_type)
        endif
    endwhile

    if list_modified
        if file_mode
            call setloclist(0, list, 'r')
        else
            call setqflist(list, 'r')
        endif
    endif
    if ignored_signs
        call neomake#utils#DebugMessage(printf(
                    \ 'Could not place signs for %d entries without line number.',
                    \ ignored_signs))
    endif
    return counts_changed
endfunction

function! s:CleanJobinfo(jobinfo) abort
    call remove(s:jobs, a:jobinfo.id)

    " Remove job from its window.
    let [t, w] = s:GetTabWinForJob(a:jobinfo.id)
    let jobs = s:gettabwinvar(t, w, 'neomake_jobs', [])
    let idx = index(jobs, a:jobinfo.id)
    if idx != -1
        call remove(jobs, idx)
        call settabwinvar(t, w, 'neomake_jobs', jobs)
    endif

    " If signs were not cleared before this point, then the maker did not return
    " any errors, so all signs must be removed
    if a:jobinfo.file_mode
        call neomake#CleanOldFileSignsAndErrors(a:jobinfo.bufnr)
    else
        call neomake#CleanOldProjectSignsAndErrors()
    endif

    " Show the current line's error
    call neomake#EchoCurrentError()

    call neomake#utils#hook('NeomakeJobFinished', {'jobinfo': a:jobinfo})
    " Trigger autocmd if all jobs for a s:Make instance have finished.
    if !len(filter(copy(s:jobs), 'v:val.make_id == a:jobinfo.make_id'))
        call neomake#utils#hook('NeomakeFinished', {
                    \ 'file_mode': a:jobinfo.file_mode,
                    \ 'make_id': a:jobinfo.make_id})
    endif
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

function! s:ProcessJobOutput(jobinfo, lines, source) abort
    let maker = a:jobinfo.maker
    call neomake#utils#DebugMessage(printf(
                \ '%s: processing %d lines of output.',
                \ maker.name, len(a:lines)), a:jobinfo)

    if has_key(maker, 'mapexpr')
        if a:jobinfo.file_mode
            let l:neomake_bufname = bufname(a:jobinfo.bufnr)
            " @vimlint(EVL102, 1, l:neomake_bufdir)
            let l:neomake_bufdir = fnamemodify(neomake_bufname, ':h')
        endif
        " @vimlint(EVL102, 1, l:neomake_output_source)
        let l:neomake_output_source = a:source
        call map(a:lines, maker.mapexpr)
    endif

    let olderrformat = &errorformat
    let &errorformat = maker.errorformat
    try
        let file_mode = a:jobinfo.file_mode
        if file_mode
            let prev_list = getloclist(0)
            laddexpr a:lines
        else
            let prev_list = getqflist()
            caddexpr a:lines
        endif
        let counts_changed = s:AddExprCallback(a:jobinfo, len(prev_list))
        if !counts_changed
            let counts_changed = (file_mode && getloclist(0) != prev_list)
                        \ || (!file_mode && getqflist() != prev_list)
        endif
        if counts_changed
            call neomake#utils#hook('NeomakeCountsChanged', {
                        \ 'file_mode': file_mode,
                        \ 'bufnr': a:jobinfo.bufnr,
                        \ })
        endif
    finally
        let &errorformat = olderrformat
    endtry

    " TODO: after processed?!
    call s:HandleLoclistQflistDisplay(a:jobinfo.file_mode)
endfunction

function! neomake#ProcessCurrentWindow() abort
    if s:CanProcessJobOutput()
        let outputs = get(w:, 'neomake_jobs_output', {})
        if len(outputs)
            unlet w:neomake_jobs_output
            call s:ProcessPendingOutput(outputs)
        endif
    endif
endfunction

function! s:ProcessPendingOutput(outputs) abort
    for job_id in sort(keys(a:outputs))
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
    if len(s:project_job_output)
        call s:ProcessPendingOutput(s:project_job_output)
        if g:neomake_place_signs
            call neomake#signs#PlaceVisibleSigns()
        endif
    endif
    call neomake#highlights#ShowHighlights()
endfunction

" Get tabnr and winnr for a given job ID.
function! s:GetTabWinForJob(job_id) abort
    for t in [tabpagenr()] + range(1, tabpagenr()-1) + range(tabpagenr()+1, tabpagenr('$'))
        for w in range(1, tabpagewinnr(t, '$'))
            if index(s:gettabwinvar(t, w, 'neomake_jobs', []), a:job_id) != -1
                return [t, w]
            endif
        endfor
    endfor
    return [-1, -1]
endfunction

function! s:RegisterJobOutput(jobinfo, lines, source) abort
    if !a:jobinfo.file_mode
        if s:CanProcessJobOutput()
            call s:ProcessJobOutput(a:jobinfo, a:lines, a:source)
            if g:neomake_place_signs
                call neomake#signs#PlaceVisibleSigns()
            endif
        else
            if !exists('s:project_job_output[a:jobinfo.id]')
                let s:project_job_output[a:jobinfo.id] = {}
            endif
            if !exists('s:project_job_output[a:jobinfo.id][a:source]')
                let s:project_job_output[a:jobinfo.id][a:source] = []
            endif
            let s:project_job_output[a:jobinfo.id][a:source] += a:lines
        endif
        return
    endif

    " Process the window directly if we can.
    if s:CanProcessJobOutput() && index(get(w:, 'neomake_jobs', []), a:jobinfo.id) != -1
        call s:ProcessJobOutput(a:jobinfo, a:lines, a:source)
        call neomake#signs#PlaceVisibleSigns()
        call neomake#highlights#ShowHighlights()
        return
    endif

    " file mode: append lines to jobs's window's output.
    let [t, w] = s:GetTabWinForJob(a:jobinfo.id)
    if w == -1
        call neomake#utils#LoudMessage('No window found for output!', a:jobinfo)
        return
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
endfunction

function! s:vim_output_handler(type, channel, output) abort
    let job_id = ch_info(a:channel)['id']
    let jobinfo = s:jobs[job_id]
    let jobinfo['vim_in_'.a:type] = 1  " vim_in_stdout/vim_in_stderr
    call neomake#utils#DebugMessage('MakeHandlerVim: stdout: '.a:channel.', '.string(a:output), jobinfo)

    call neomake#MakeHandler(job_id, split(a:output, "\n", 1), a:type)

    let jobinfo['vim_in_'.a:type] = 0  " vim_in_stdout/vim_in_stderr
    if exists('jobinfo.vim_exited')
        let job_info = job_info(ch_getjob(a:channel))
        call neomake#utils#DebugMessage('MakeHandlerVim: trigger delayed exit: '
                    \ .string(a:channel).', job_info: '.string(job_info), jobinfo)

        call neomake#MakeHandler(job_id, jobinfo.vim_exited, 'exit')
    endif
endfunction

function! neomake#MakeHandlerVimStdout(channel, output) abort
    return s:vim_output_handler('stdout', a:channel, a:output)
endfunction

function! neomake#MakeHandlerVimStderr(channel, output) abort
    return s:vim_output_handler('stderr', a:channel, a:output)
endfunction

function! neomake#MakeHandlerVimClose(channel) abort
    let job_info = job_info(ch_getjob(a:channel))
    let job_id = ch_info(a:channel)['id']
    if has_key(s:jobs, job_id)
        let jobinfo = s:jobs[job_id]
        if get(jobinfo, 'vim_in_stdout') || get(jobinfo, 'vim_in_stderr')
            call neomake#utils#DebugMessage('MakeHandlerVim: exit (delayed): '
                        \ .string(a:channel).', job_info: '.string(job_info), jobinfo)
            let jobinfo.vim_exited = job_info['exitval']
            return
        endif
    endif
    call neomake#utils#DebugMessage('MakeHandlerVim: exit: '
                \ .string(a:channel).', job_info: '.string(job_info),
                \ get(l:, 'jobinfo', {}))
    call neomake#MakeHandler(job_id, job_info['exitval'], 'exit')
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

function! neomake#MakeHandler(job_id, data, event_type) abort
    if !has_key(s:jobs, a:job_id)
        call neomake#utils#QuietMessage(
                    \ 'neomake#MakeHandler: '.a:event_type.': job not found: '
                    \ . string(a:job_id))
        return
    endif
    let jobinfo = s:jobs[a:job_id]
    if get(jobinfo, 'canceled')
        if a:event_type ==# 'exit'
            call neomake#utils#DebugMessage(
                        \ 'neomake#MakeHandler: '.a:event_type.': job was canceled.',
                        \ jobinfo)
            call s:CleanJobinfo(jobinfo)
        endif
        return
    endif
    let maker = jobinfo.maker
    call neomake#utils#DebugMessage(printf('%s: %s: %s',
                \ a:event_type, maker.name, string(a:data)), jobinfo)
    if index(['stdout', 'stderr'], a:event_type) >= 0
        let last_event_type = get(jobinfo, 'event_type', a:event_type)
        let jobinfo.event_type = a:event_type

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

        if !maker.buffer_output || last_event_type !=# a:event_type
            let lines = jobinfo[a:event_type][:-2]
            if len(lines)
                call s:RegisterJobOutput(jobinfo, lines, a:event_type)
            endif
            let jobinfo[a:event_type] = jobinfo[a:event_type][-1:]
        endif
    elseif a:event_type ==# 'exit'
        " Handle any unfinished lines from stdout/stderr callbacks.
        for event_type in ['stdout', 'stderr']
            if has_key(jobinfo, event_type)
                let lines = jobinfo[event_type]
                if len(lines)
                    if lines[-1] ==# ''
                        call remove(lines, -1)
                    endif
                    if len(lines)
                        call s:RegisterJobOutput(jobinfo, lines, event_type)
                    endif
                endif
            endif
        endfor

        let status = a:data
        if has_key(maker, 'exit_callback')
            let callback_dict = { 'status': status,
                                \ 'name': maker.name,
                                \ 'has_next': has_key(maker, 'next') }
            if type(maker.exit_callback) == type('')
                let l:ExitCallback = function(maker.exit_callback)
            else
                let l:ExitCallback = maker.exit_callback
            endif
            try
                call l:ExitCallback(callback_dict)
            catch /^Vim\%((\a\+)\)\=:E117/
            endtry
        endif

        if neomake#has_async_support()
            call neomake#utils#DebugMessage(printf(
                        \ '%s: completed with exit code %d.',
                        \ maker.name, status), jobinfo)
        endif

        if s:has_pending_output(jobinfo)
            call neomake#utils#DebugMessage(
                        \ 'Output left to be processed, not cleaning job yet.', jobinfo)
            let jobinfo.pending_output = 1
            let jobinfo.finished = 1
        else
            call s:CleanJobinfo(jobinfo)
        endif

        if has_key(maker, 'next')
            let next_makers = '['.join(map(copy(maker.next.enabled_makers), 'v:val.name'), ', ').']'
            if get(g:, 'neomake_serialize_abort_on_error') && status !=# 0
                call neomake#utils#LoudMessage('Aborting next makers '.next_makers)
            else
                call neomake#utils#DebugMessage(printf('next makers: %s',
                            \ next_makers), jobinfo)
                call s:Make(maker.next, a:job_id)
            endif
        endif
    endif
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

function! neomake#EchoCurrentError() abort
    if !get(g:, 'neomake_echo_current_error', 1)
        return
    endif

    if !empty(get(s:, 'neomake_last_echoed_error', {}))
        unlet s:neomake_last_echoed_error
        echon ''
    endif

    let buf = bufnr('%')
    let ln = line('.')
    let ln_errors = []

    for maker_type in ['file', 'project']
        let buf_errors = get(s:current_errors[maker_type], buf, {})
        let ln_errors += get(buf_errors, ln, [])
    endfor

    if empty(ln_errors)
        return
    endif

    let s:neomake_last_echoed_error = ln_errors[0]
    for error in ln_errors
        if error.type ==# 'E'
            let s:neomake_last_echoed_error = error
            break
        endif
    endfor
    let message = s:neomake_last_echoed_error.maker_name.': '.s:neomake_last_echoed_error.text
    call neomake#utils#WideMessage(message)
endfunction

let s:last_cursormoved = [0, 0]
function! neomake#CursorMoved() abort
    let l:line = line('.')
    if s:last_cursormoved[0] != l:line || s:last_cursormoved[1] != bufnr('%')
        let s:last_cursormoved = [l:line, bufnr('%')]
        if g:neomake_place_signs
            call neomake#signs#PlaceVisibleSigns()
        endif
        call neomake#EchoCurrentError()
    endif
endfunction

function! neomake#CompleteMakers(ArgLead, CmdLine, ...) abort
    if a:ArgLead =~# '[^A-Za-z0-9]'
        return []
    endif
    let file_mode = a:CmdLine =~# '\v^(Neomake|NeomakeFile)\s'
    let makers = file_mode ? neomake#GetMakers(&filetype) : neomake#GetProjectMakers()
    return filter(makers, "v:val =~? '^".a:ArgLead."'")
endfunction

function! neomake#CompleteJobs() abort
    return join(map(neomake#GetJobs(), "v:val.id.': '.v:val.maker.name"), "\n")
endfunction

function! neomake#Make(file_mode, enabled_makers, ...) abort
    let options = a:0 ? { 'exit_callback': a:1 } : {}
    let options.file_mode = a:file_mode
    if a:file_mode
        let options.ft = &filetype
    endif
    let options.enabled_makers = len(a:enabled_makers)
                    \ ? a:enabled_makers
                    \ : neomake#GetEnabledMakers(a:file_mode ? &filetype : '')
    return s:Make(options)
endfunction

function! neomake#ShCommand(bang, sh_command, ...) abort
    let maker = neomake#utils#MakerFromCommand(a:sh_command)
    let maker.name = 'sh: '.a:sh_command
    let maker.buffer_output = !a:bang
    let maker.errorformat = '%m'
    let options = {'enabled_makers': [maker]}
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
    if !len(maker_names)
        echon ' None.'
        return
    endif
    for maker_name in maker_names
        let maker = call('neomake#GetMaker', [maker_name] + a:000)
        echo ' - '.maker.name
        for [k, V] in items(maker)
            if k ==# 'name' || k ==# 'ft'
                continue
            endif
            if has_key(s:maker_defaults, k)
                        \ && type(V) == type(s:maker_defaults[k])
                        \ && V ==# s:maker_defaults[k]
                continue
            endif
            echo '   '.k.': '.string(V)
            unlet V
        endfor
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
        echo 'NOTE: you can define g:neomake_'.ft.'_enabled_makers'
                    \ .' to configure it (or b:neomake_'.ft.'_enabled_makers).'
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
    for [k, V] in items(filter(copy(g:), "v:key =~# '^neomake_'"))
        echo 'g:'.k.' = '.string(V)
        unlet! V  " Fix variable type mismatch with Vim 7.3.
    endfor
    echo "\n"
    echo 'shell:' &shell
    echo 'shellcmdflag:' &shellcmdflag
    echo 'Windows: '.neomake#utils#IsRunningWindows()
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
