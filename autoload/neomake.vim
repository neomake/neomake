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

function! neomake#has_async_support() abort
    return has('nvim') ||
                \ has('channel') && has('job') && has('patch-8.0.0027')
endfunction

function! neomake#GetJobs() abort
    return s:jobs
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

function! neomake#CancelJob(job_id) abort
    if has_key(s:jobs, a:job_id)
        call neomake#utils#DebugMessage('Stopping job: ' . a:job_id)
        if has('nvim')
            try
                call jobstop(a:job_id)
            catch /^Vim\%((\a\+)\)\=:\(E474\|E900\):/
                return 0
            endtry
        else
            if v:version < 800 || v:version == 800 && !has('patch45')
                " Vim before 8.0.0045 might fail to stop a job right away.
                sleep 50m
            endif
            let vim_job = s:jobs[a:job_id].vim_job
            " NOTE: Vim does not trigger the exit callback with job_stop?!
            unlet s:jobs[a:job_id]
            if job_status(vim_job) !=# 'run'
                return 0
            endif
            call job_stop(vim_job)
        endif
        return 1
    endif
    return 0
endfunction

function! s:GetMakerKey(maker) abort
    return a:maker.name.',ft='.a:maker.ft.',buf='.a:maker.bufnr
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

function! s:getwinvar(w, v, d) abort
    " Wrapper around getwinvar that has no default (Vim in Travis).
    let r = getwinvar(a:w, a:v)
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

function! s:MakeJob(make_id, maker) abort
    let job_id = s:job_id
    let s:job_id += 1
    let jobinfo = {
        \ 'name': 'neomake_'.job_id,
        \ 'winnr': winnr(),
        \ 'bufnr': bufnr('%'),
        \ 'maker': a:maker,
        \ 'make_id': a:make_id,
        \ }

    " Resolve exe/args, which might be a function or dictionary.
    if type(a:maker.exe) == type(function('tr'))
        let exe = call(a:maker.exe, [])
    elseif type(a:maker.exe) == type({})
        let exe = call(a:maker.exe.fn, [], a:maker.exe)
    else
        let exe = a:maker.exe
    endif
    if type(a:maker.args) == type(function('tr'))
        let args = call(a:maker.args, [])
    elseif type(a:maker.args) == type({})
        let args = call(a:maker.args.fn, [], a:maker.args)
    else
        let args = a:maker.args
    endif
    let append_file = a:maker.file_mode && index(args, '%:p') == -1 && get(a:maker, 'append_file', 1)
    if append_file
        call add(args, '%:p')
    endif

    call neomake#utils#ExpandArgs(args)

    if has_key(a:maker, 'cwd')
        let old_wd = getcwd()
        let cwd = expand(a:maker.cwd, 1)
        exe 'cd' fnameescape(cwd)
    endif

    try
        let has_args = type(args) == type([])
        let error = ''
        if neomake#has_async_support()
            let argv = [exe]
            if has_args
                let argv += args
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
                    let argv = &shell.' '.&shellcmdflag.' '.shellescape(join(argv))
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

            let maker_key = s:GetMakerKey(a:maker)
            let s:jobs_by_maker[maker_key] = jobinfo
            call s:AddJobinfoForCurrentWin(jobinfo.id)
            let r = jobinfo.id
        else
            call neomake#utils#DebugMessage('Running synchronously')
            if has_args
                if neomake#utils#IsRunningWindows()
                    let program = exe.' '.join(map(args, 'v:val'))
                else
                    let program = exe.' '.join(map(args, 'shellescape(v:val)'))
                endif
            else
                let program = exe
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
    let defaults = {
        \ 'exe': maker.name,
        \ 'args': [],
        \ 'errorformat': &errorformat,
        \ 'buffer_output': 1,
        \ 'remove_invalid_entries': 1,
        \ }
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
    let file_mode = get(a:options, 'file_mode')
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
    call neomake#signs#DefineSigns()

    call neomake#highlights#DefineHighlights()

    call neomake#utils#DebugMessage(printf('Running makers: %s',
                \ string(enabled_makers)), {'make_id': make_id})

    let buf = bufnr('%')
    let win = winnr()
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
            call neomake#signs#ResetFile(buf)
            let s:need_errors_cleaning['file'][buf] = 1
        else
            call neomake#signs#ResetProject()
            let s:need_errors_cleaning['project'] = 1
        endif
    endif

    let serialize = get(g:, 'neomake_serialize')
    let job_ids = []
    for name in enabled_makers
        let maker = neomake#GetMaker(name, ft)
        if empty(maker)
            continue
        endif
        call extend(maker, {
                    \ 'file_mode': file_mode,
                    \ 'bufnr': buf,
                    \ 'winnr': win,
                    \ }, 'error')
        let maker_key = s:GetMakerKey(maker)
        if has_key(s:jobs_by_maker, maker_key)
            let jobinfo = s:jobs_by_maker[maker_key]
            let jobinfo.maker.next = copy(a:options)
            call neomake#CancelJob(jobinfo.id)
            break
        endif
        if serialize && len(enabled_makers) > 1
            let next_opts = copy(a:options)
            let next_opts.enabled_makers = enabled_makers[1:]
            let next_opts.continuation = 1
            let maker.next = next_opts
        endif
        if has_key(a:options, 'exit_callback')
            let maker.exit_callback = a:options.exit_callback
        endif
        let job_id = s:MakeJob(make_id, maker)
        if job_id != -1
            call add(job_ids, job_id)
        endif
        " If we are serializing makers, stop after the first one. The
        " remaining makers will be processed in turn when this one is done.
        if serialize
            break
        endif
    endfor
    if !len(job_ids)
        call neomake#utils#hook('NeomakeFinished', {
                    \ 'file_mode': file_mode})
    endif
    return job_ids
endfunction

function! s:AddExprCallback(jobinfo, prev_index) abort
    let maker = a:jobinfo.maker
    let file_mode = get(maker, 'file_mode')
    let place_signs = get(g:, 'neomake_place_signs', 1)
    let highlight_columns = get(g:, 'neomake_highlight_columns', 1)
    let highlight_lines = get(g:, 'neomake_highlight_lines', 1)
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

        if place_signs
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
    let maker = a:jobinfo.maker
    let maker_key = s:GetMakerKey(maker)
    if has_key(s:jobs_by_maker, maker_key)
        unlet s:jobs_by_maker[maker_key]
    endif
    call remove(s:jobs, a:jobinfo.id)

    " Remove job from its window.
    let [t, w] = s:GetTabWinForJob(a:jobinfo.id)
    let jobs = s:gettabwinvar(t, w, 'neomake_jobs', [])
    let idx = index(jobs, a:jobinfo.id)
    if idx != -1
        call remove(jobs, idx)
        call settabwinvar(t, w, 'neomake_jobs', jobs)
    endif
endfunction

function! s:ProcessJobOutput(jobinfo, lines, source) abort
    let maker = a:jobinfo.maker
    call neomake#utils#DebugMessage(printf(
                \ '%s: processing %d lines of output.',
                \ maker.name, len(a:lines)), a:jobinfo)

    if has_key(maker, 'mapexpr')
        if maker.file_mode
            let l:neomake_bufname = bufname(maker.bufnr)
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
        let file_mode = get(maker, 'file_mode')
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
                        \ 'file_mode': maker.file_mode,
                        \ 'bufnr': get(maker, 'bufnr', -1),
                        \ })
        endif
    finally
        let &errorformat = olderrformat
    endtry

    call s:HandleLoclistQflistDisplay(maker.file_mode)
endfunction

function! neomake#ProcessCurrentWindow() abort
    let outputs = get(w:, 'neomake_jobs_output', [])
    if len(outputs)
        unlet w:neomake_jobs_output
        for output in outputs
            call s:ProcessJobOutput(output.jobinfo, output.lines, output.source)
        endfor
        call neomake#signs#PlaceVisibleSigns()
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
    let lines = copy(a:lines)
    let maker = a:jobinfo.maker

    if !get(maker, 'file_mode')
        call s:ProcessJobOutput(a:jobinfo, lines, a:source)
        call neomake#signs#PlaceVisibleSigns()
        return
    endif

    " file mode: append lines to jobs's window's output.
    let [t, w] = s:GetTabWinForJob(a:jobinfo.id)
    if w == -1
        call neomake#utils#LoudMessage('No window found for output!', a:jobinfo)
        return
    endif
    let w_output = s:gettabwinvar(t, w, 'neomake_jobs_output', []) + [{
                \ 'source': a:source,
                \ 'jobinfo': a:jobinfo,
                \ 'lines': lines }]
    call settabwinvar(t, w, 'neomake_jobs_output', w_output)

    " Process the window on demand if we can.
    let idx_win_job = index(s:getwinvar(winnr(), 'neomake_jobs', []), a:jobinfo.id)
    if idx_win_job != -1
        call neomake#ProcessCurrentWindow()
    elseif &filetype ==# 'qf'
        " Process the previous window if we are in a qf window.
        " XXX: noautocmd, restore alt window.
        wincmd p
        call neomake#ProcessCurrentWindow()
        wincmd p
    endif
endfunction

function! neomake#MakeHandlerVimStdout(channel, output) abort
    call neomake#utils#DebugMessage('MakeHandlerVim: stdout: ' . a:channel)
    call neomake#MakeHandler(ch_info(a:channel)['id'], split(a:output, "\n", 1), 'stdout')
endfunction

function! neomake#MakeHandlerVimStderr(channel, output) abort
    call neomake#utils#DebugMessage('MakeHandlerVim: stderr: ' . a:channel)
    call neomake#MakeHandler(ch_info(a:channel)['id'], split(a:output, "\n", 1), 'stderr')
endfunction

function! neomake#MakeHandlerVimClose(channel) abort
    let job_info = job_info(ch_getjob(a:channel))
    call neomake#utils#DebugMessage('MakeHandlerVim: exit: '
                \ .string(a:channel).', job_info: '.string(job_info))
    call neomake#MakeHandler(ch_info(a:channel)['id'], job_info['exitval'], 'exit')
endfunction

function! neomake#MakeHandler(job_id, data, event_type) abort
    if !has_key(s:jobs, a:job_id)
        call neomake#utils#QuietMessage(
                    \ 'neomake#MakeHandler: '.a:event_type.': job not found: '
                    \ . string(a:job_id))
        return
    endif
    let jobinfo = s:jobs[a:job_id]
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
        call s:CleanJobinfo(jobinfo)
        if neomake#has_async_support()
            call neomake#utils#DebugMessage(printf(
                        \ '%s: completed with exit code %d.',
                        \ maker.name, status), jobinfo)
        endif

        " If signs were not cleared before this point, then the maker did not return
        " any errors, so all signs must be removed
        if maker.file_mode
            call neomake#CleanOldFileSignsAndErrors(jobinfo.bufnr)
        else
            call neomake#CleanOldProjectSignsAndErrors()
        endif

        " Show the current line's error
        call neomake#EchoCurrentError()

        if has_key(maker, 'next')
            let next_makers = '['.join(maker.next.enabled_makers, ', ').']'
            if get(g:, 'neomake_serialize_abort_on_error') && status !=# 0
                call neomake#utils#LoudMessage('Aborting next makers '.next_makers)
            else
                call neomake#utils#DebugMessage(printf('next makers: %s',
                            \ next_makers), jobinfo)
                call s:Make(maker.next, a:job_id)
            endif
        endif

        " Trigger autocmd if all jobs for a s:Make instance have finished.
        if neomake#has_async_support()
            if !len(filter(copy(s:jobs), 'v:val.make_id == jobinfo.make_id'))
                call neomake#utils#hook('NeomakeFinished', {
                            \ 'file_mode': maker.file_mode})
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
    call neomake#signs#CleanAllOldSigns('project')
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
    call neomake#signs#CleanOldSigns(bufnr, 'file')
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
        call neomake#signs#PlaceVisibleSigns()
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

function! neomake#DisplayInfo() abort
    let ft = &filetype
    echo '#### Neomake debug information'
    echo 'Async support: '.neomake#has_async_support()
    echo 'Current filetype: '.ft
    echo "\n"
    echo '##### Enabled makers'
    echo 'For the current filetype (with :Neomake): '
                \ .string(neomake#GetEnabledMakers(ft))
    if empty(ft)
        echo 'NOTE: the current buffer does not have a filetype.'
    else
        echo 'NOTE: you can define g:neomake_'.ft.'_enabled_makers'
                    \ .' to configure it (or b:neomake_'.ft.'_enabled_makers).'
    endif
    echo 'For the project (with :Neomake!): '
                \ .string(neomake#GetEnabledMakers())
    echo 'NOTE: you can define g:neomake_enabled_makers to configure it.'
    echo "\n"
    echo '##### Settings'
    echo '```'
    for [k, v] in items(filter(copy(g:), "v:key =~# '^neomake_'"))
        echo 'g:'.k.' = '.string(v)
        unlet! v  " Fix variable type mismatch with Vim 7.3.
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
