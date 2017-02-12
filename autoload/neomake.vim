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

function! neomake#has_async_support() abort
    return has('nvim') ||
                \ has('channel') && has('job') && has('patch-8.0.0027')
endfunction

function! s:sort_jobs(a, b) abort
    return a:a.id - a:b.id
endfunction

function! neomake#GetJobs(...) abort
    if !len(s:jobs)
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
                \ }
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
    let jobinfo = s:jobs[job_id]
    if get(jobinfo, 'finished')
        call neomake#utils#DebugMessage('Removing already finished job: '.job_id)
        call s:CleanJobinfo(jobinfo)
    else
        if remove_always
            unlet s:jobs[job_id]
        endif
        " Mark it as canceled for the exit handler.
        let jobinfo.canceled = 1
        call neomake#utils#DebugMessage('Stopping job', jobinfo)
        if has('nvim')
            try
                call jobstop(job_id)
            catch /^Vim\%((\a\+)\)\=:\(E474\|E900\):/
                call neomake#utils#LoudMessage(printf(
                            \ 'jobstop failed: %s', v:exception), jobinfo)
                return 0
            endtry
        else
            let vim_job = jobinfo.vim_job
            if job_status(vim_job) !=# 'run'
                call neomake#utils#LoudMessage(
                            \ 'job_stop: job was not running anymore', jobinfo)
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
    let maker = a:options.maker
    let jobinfo = {
        \ 'name': 'neomake_'.job_id,
        \ 'bufnr': a:options.bufnr,
        \ 'file_mode': a:options.file_mode,
        \ 'maker': maker,
        \ 'make_id': a:make_id,
        \ 'next': get(a:options, 'next', {}),
        \ }

    " Call .fn function in maker object, if any.
    if has_key(maker, 'fn')
        " TODO: Allow to throw and/or return 0 to abort/skip?!
        let maker = call(maker.fn, [jobinfo], maker)
    endif

    let cwd = get(maker, 'cwd', s:make_info[a:make_id].cwd)
    if len(cwd)
        let old_wd = getcwd()
        let cwd = expand(cwd, 1)
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
        let argv = maker.get_argv(jobinfo.file_mode ? jobinfo.bufnr : 0)
        if neomake#has_async_support()
            if has('nvim')
                let opts = {
                    \ 'on_stdout': function('s:nvim_output_handler'),
                    \ 'on_stderr': function('s:nvim_output_handler'),
                    \ 'on_exit': function('s:exit_handler')
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
                try
                    call neomake#utils#LoudMessage(printf(
                                \ 'Starting async job: %s',
                                \ string(argv)), jobinfo)
                    let job = job_start(argv, opts)
                    " Get this as early as possible!
                    let jobinfo.id = ch_info(job)['id']
                    let jobinfo.vim_job = job
                    let s:jobs[jobinfo.id] = jobinfo
                catch
                    let error = printf('Failed to start Vim job: %s: %s',
                                \ argv, v:exception)
                endtry
                if empty(error)
                    call neomake#utils#DebugMessage(printf('Vim job: %s',
                                \ string(job_info(job))), jobinfo)
                    call neomake#utils#DebugMessage(printf('Vim channel: %s',
                                \ string(ch_info(job))), jobinfo)
                endif
            endif

            " Bail out on errors.
            if len(error)
                call neomake#utils#ErrorMessage(error, jobinfo)
                call s:handle_next_makers(jobinfo, 122)
                return -1
            endif

            let r = jobinfo.id
        else
            call neomake#utils#DebugMessage('Running synchronously')
            call neomake#utils#LoudMessage('Starting: '.argv, jobinfo)

            let jobinfo.id = job_id
            let s:jobs[job_id] = jobinfo
            call s:output_handler(job_id, split(system(argv), '\r\?\n', 1), 'stdout')
            call s:exit_handler(job_id, v:shell_error, 'exit')
            let r = -1
        endif
    finally
        if exists('old_wd')
            exe 'cd' fnameescape(old_wd)
        endif
    endtry
    return r
endfunction

let s:maker_base = {}
function! s:maker_base.get_argv(...) abort dict
    let bufnr = a:0 ? a:1 : 0

    " Resolve exe/args, which might be a function or dictionary.
    if type(self.exe) == type(function('tr'))
        let exe = call(self.exe, [])
    elseif type(self.exe) == type({})
        let exe = call(self.exe.fn, [], self.exe)
    else
        let exe = self.exe
    endif
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
    if bufnr && neomake#utils#GetSetting('append_file', self, 1, [self.ft], bufnr)
        let bufname = bufname(bufnr)
        if !len(bufname)
            throw 'Neomake: no file name'
        endif
        let bufname = fnamemodify(bufname, ':p')
        if !filereadable(bufname)
            throw 'Neomake: file is not readable ('.bufname.')'
        endif
        if args_is_list
            call add(args, bufname)
        else
            let args .= ' '.fnameescape(bufname)
        endif
    endif

    if neomake#has_async_support()
        if args_is_list
            let argv = [exe] + args
        else
            let argv = exe . (len(args) ? ' ' . args : '')
        endif
        if !has('nvim')
            if !args_is_list
                " Have to use a shell to handle argv properly (Vim splits it
                " at spaces).
                let argv = [&shell, &shellcmdflag, argv]
            endif
        endif
    else
        let argv = exe
        if len(args)
            if args_is_list
                if neomake#utils#IsRunningWindows()
                    let argv .= ' '.join(args)
                else
                    let argv .= ' '.join(map(args, 'shellescape(v:val)'))
                endif
            else
                let argv .= ' '.args
            endif
        endif
    endif
    return argv
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

    " Create the maker object.
    let maker = deepcopy(maker)
    if !has_key(maker, 'name')
        if type(a:name_or_maker) == type('')
            let maker.name = a:name_or_maker
        else
            let maker.name = 'unnamed_maker'
        endif
    endif
    let maker.get_argv = s:maker_base.get_argv
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
        for v in extend(keys(g:), keys(b:))
            let maker_name = matchstr(v, '\v^neomake_'.ft.'_\zs\l+\ze_maker')
            if len(maker_name)
                let c = get(makers_count, maker_name, 0)
                let makers_count[maker_name] = c + 1
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

function! s:Make(options) abort
    let options = copy(a:options)
    call extend(options, {
                \ 'file_mode': 0,
                \ 'enabled_makers': [],
                \ 'bufnr': bufnr('%'),
                \ 'ft': '',
                \ }, 'keep')
    let bufnr = options.bufnr
    let file_mode = options.file_mode
    let enabled_makers = options.enabled_makers
    let ft = options.ft

    " Reset/clear on first run, but not when using 'serialize'.
    if !get(options, 'continuation', 0)
        if !len(enabled_makers)
            if file_mode
                call neomake#utils#DebugMessage('Nothing to make: no enabled makers.')
                return []
            endif
            let enabled_makers = ['makeprg']
        endif

        let s:make_id += 1
        let s:make_info[s:make_id] = {
                    \ 'cwd': getcwd(),
                    \ }

        if file_mode
            " XXX: this clears counts for job's buffer only, but we
            "      add counts for the entry's buffers, which might be
            "      different!
            call neomake#statusline#ResetCountsForBuf(bufnr)
        else
            call neomake#statusline#ResetCountsForProject()
        endif

        call s:AddMakeInfoForCurrentWin(s:make_id)
    endif

    let job_ids = []

    let enabled_makers = filter(map(copy(enabled_makers), 'neomake#GetMaker(v:val, ft)'), '!empty(v:val)')
    if !len(enabled_makers)
        return []
    endif
    call neomake#utils#DebugMessage(printf('Running makers: %s',
                \ join(map(copy(enabled_makers), 'v:val.name'), ', ')))
    let maker = {}
    while len(enabled_makers)
        let maker = remove(enabled_makers, 0)
        if empty(maker)
            continue
        endif
        if has_key(a:options, 'exit_callback')
            let maker.exit_callback = a:options.exit_callback
        endif
        " call neomake#utils#DebugMessage('Maker: '.string(enabled_makers), {'make_id': s:make_id})

        " Check for already running job for the same maker (from other runs).
        " This used to use this key: maker.name.',ft='.maker.ft.',buf='.maker.bufnr
        if len(s:jobs)
            let running_already = values(filter(copy(s:jobs),
                        \ 'v:val.make_id != s:make_id && v:val.maker == maker'
                        \ ." && v:val.bufnr == bufnr && !get(v:val, 'restarting')"))
            if len(running_already)
                let jobinfo = running_already[0]
                " let jobinfo.next = copy(options)
                " TODO: required?! (
                " let jobinfo.next.enabled_makers = [maker]
                call neomake#utils#LoudMessage(printf(
                            \ 'Restarting already running job (%d.%d) for the same maker.',
                            \ jobinfo.make_id, jobinfo.id), {'make_id': s:make_id})
                let jobinfo.restarting = 1
                call neomake#CancelJob(jobinfo.id)
                continue
            endif
        endif

        if neomake#has_async_support()
            let serialize = neomake#utils#GetSetting('serialize', maker, 0, [ft], bufnr)
        else
            let serialize = 1
        endif
        if serialize && len(enabled_makers) > 0
            let next_opts = copy(options)
            let next_opts.enabled_makers = enabled_makers
            let next_opts.continuation = 1
            call extend(next_opts, {
                    \ 'file_mode': file_mode,
                    \ 'bufnr': bufnr,
                    \ 'serialize_abort_on_error':
                    \    neomake#utils#GetSetting('serialize_abort_on_error', maker, 0, [ft], bufnr),
                    \ })
            let options.next = next_opts
        endif
        let options.maker = maker
        try
            let job_id = s:MakeJob(s:make_id, options)
        catch /^Neomake: /
            let error = substitute(v:exception, '^Neomake: ', '', '')
            call neomake#utils#ErrorMessage(error, {'make_id': s:make_id})
            continue
        endtry
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
    let s:postprocess = get(maker, 'postprocess', function('neomake#utils#CompressWhitespace'))
    let debug = get(g:, 'neomake_verbose', 0) >= 3

    while index < len(list)
        let entry = list[index]
        let entry.maker_name = has_key(maker, 'name') ? maker.name : 'makeprg'
        let index += 1

        let before = copy(entry)
        call call(s:postprocess, [entry], maker)
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
    call neomake#utils#DebugMessage('Cleaning jobinfo', a:jobinfo)

    if has_key(a:jobinfo, 'id')
        call remove(s:jobs, a:jobinfo.id)

        let [t, w] = s:GetTabWinForMakeId(a:jobinfo.make_id)
        let jobs_output = s:gettabwinvar(t, w, 'neomake_jobs_output', {})
        if has_key(jobs_output, a:jobinfo.id)
            unlet jobs_output[a:jobinfo.id]
        endif
        if has_key(s:project_job_output, a:jobinfo.id)
            unlet s:project_job_output[a:jobinfo.id]
        endif
    endif

    call neomake#utils#hook('NeomakeJobFinished', {'jobinfo': a:jobinfo})

    " Trigger autocmd if all jobs for a s:Make instance have finished.
    if !len(filter(copy(s:jobs), 'v:val.make_id == a:jobinfo.make_id'))
        call s:init_job_output(a:jobinfo)

        " If signs were not cleared before this point, then the maker did not return
        " any errors, so all signs must be removed
        if a:jobinfo.file_mode
            call neomake#CleanOldFileSignsAndErrors(a:jobinfo.bufnr)
        else
            call neomake#CleanOldProjectSignsAndErrors()
        endif

        " Remove make_id from its window.
        if !exists('l:t')
            let [t, w] = s:GetTabWinForMakeId(a:jobinfo.make_id)
        endif
        " @vimlint(EVL104, 1, l:t)
        " @vimlint(EVL104, 1, l:w)
        let make_ids = s:gettabwinvar(t, w, 'neomake_make_ids', [])
        let idx = index(make_ids, a:jobinfo.make_id)
        if idx != -1
            call remove(make_ids, idx)
            call settabwinvar(t, w, 'neomake_make_ids', make_ids)
        endif
        call neomake#utils#hook('NeomakeFinished', {
                    \ 'file_mode': a:jobinfo.file_mode,
                    \ 'make_id': a:jobinfo.make_id}, a:jobinfo)
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

function! s:ProcessJobOutput(jobinfo, lines, source) abort
    let maker = a:jobinfo.maker
    let file_mode = a:jobinfo.file_mode

    call neomake#utils#DebugMessage(printf(
                \ '%s: processing %d lines of output.',
                \ maker.name, len(a:lines)), a:jobinfo)

    if has_key(maker, 'mapexpr')
        let l:neomake_bufname = bufname(a:jobinfo.bufnr)
        " @vimlint(EVL102, 1, l:neomake_bufdir)
        let l:neomake_bufdir = fnamemodify(neomake_bufname, ':h')
        " @vimlint(EVL102, 1, l:neomake_output_source)
        let l:neomake_output_source = a:source
        call map(a:lines, maker.mapexpr)
    endif

    call s:init_job_output(a:jobinfo)

    let olderrformat = &errorformat
    let &errorformat = maker.errorformat
    try
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
                        \ }, a:jobinfo)
        endif
    finally
        let &errorformat = olderrformat
    endtry

    call s:HandleLoclistQflistDisplay(a:jobinfo.file_mode)
    call neomake#EchoCurrentError()
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
            if g:neomake_place_signs
                call neomake#signs#PlaceVisibleSigns()
            endif
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
        call neomake#signs#PlaceVisibleSigns()
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

    let data = split(a:output, "\n", 1)

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
        while has_key(jobinfo, '_vim_in_handler') && len(jobinfo._vim_in_handler)
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
    endif

    call s:exit_handler(job_id, status, 'exit')
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
    " @vimlint(EVL108, 1)
    if has('nvim-0.2.0')
        call s:output_handler(a:job_id, a:data, a:event_type)
        return
    endif
    " @vimlint(EVL108, 0)
    let jobinfo = s:jobs[a:job_id]
    let args = [a:job_id, a:data, a:event_type]
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
    while len(s:nvim_output_handler_queue)
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
    if get(jobinfo, 'restarting')
        call neomake#utils#DebugMessage('exit: job is restarting.', jobinfo)
        call s:MakeJob(jobinfo.make_id, jobinfo)
        call remove(s:jobs, jobinfo.id)
        return
    endif
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
            if len(lines)
                if lines[-1] ==# ''
                    call remove(lines, -1)
                endif
                if len(lines)
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
    if has_key(maker, 'exit_callback') && !get(jobinfo, 'failed_to_start')
        let callback_dict = { 'status': status,
                            \ 'name': maker.name,
                            \ 'has_next': has_key(maker, 'next') }
        if type(maker.exit_callback) == type('')
            let l:ExitCallback = function(maker.exit_callback)
        else
            let l:ExitCallback = maker.exit_callback
        endif
        try
            call call(l:ExitCallback, [callback_dict], jobinfo)
        catch /^Vim\%((\a\+)\)\=:E117/
        endtry
    endif

    if neomake#has_async_support() && (has('nvim') || status != 122)
        call neomake#utils#DebugMessage(printf(
                    \ '%s: completed with exit code %d.',
                    \ maker.name, status), jobinfo)
    endif

    if has_pending_output || s:has_pending_output(jobinfo)
        call neomake#utils#DebugMessage(
                    \ 'Output left to be processed, not cleaning job yet.', jobinfo)
        let jobinfo.pending_output = 1
        let jobinfo.finished = 1
    endif

    call s:handle_next_makers(jobinfo, status)
endfunction

function! s:output_handler(job_id, data, event_type) abort
    let jobinfo = s:jobs[a:job_id]

    call neomake#utils#DebugMessage(printf('%s: %s: %s',
                \ a:event_type, jobinfo.maker.name, string(a:data)), jobinfo)
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

        if len(lines)
            call s:RegisterJobOutput(jobinfo, lines, a:event_type)
        endif
    endif
endfunction

function! s:handle_next_makers(jobinfo, status) abort
    if len(a:jobinfo.next)
        let next = a:jobinfo.next
        let next_makers = '['.join(map(copy(next.enabled_makers), 'v:val.name'), ', ').']'
        if (a:status != 0 && index([122, 127], a:status) == -1 && next.serialize_abort_on_error)
            call neomake#utils#LoudMessage('Aborting next makers '.next_makers.' (status '.a:status.')')
        else
            call neomake#utils#DebugMessage(printf('next makers: %s',
                        \ next_makers), a:jobinfo)
            call s:Make(next)
        endif
    endif
    if !get(a:jobinfo, 'pending_output', 0)
        call s:CleanJobinfo(a:jobinfo)
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

let s:last_cursormoved = [0, 0]
function! neomake#CursorMoved() abort
    let l:line = line('.')
    if s:last_cursormoved[0] != l:line || s:last_cursormoved[1] != bufnr('%')
        let s:last_cursormoved = [l:line, bufnr('%')]
        if g:neomake_place_signs
            call neomake#signs#PlaceVisibleSigns()
        endif
    endif
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
    let file_mode = a:CmdLine =~# '\v^(Neomake|NeomakeFile)\s'
    let makers = file_mode ? neomake#GetMakers(&filetype) : neomake#GetProjectMakers()
    return filter(makers, "v:val =~? '^".a:ArgLead."'")
endfunction

function! neomake#CompleteJobs(...) abort
    return join(map(neomake#GetJobs(), "v:val.id.': '.v:val.maker.name"), "\n")
endfunction

function! neomake#Make(file_mode, enabled_makers, ...) abort
    let options = {'file_mode': a:file_mode}
    if a:0
        let options.exit_callback = a:1
    endif
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
