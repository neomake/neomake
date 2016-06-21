" vim: ts=4 sw=4 et
scriptencoding utf-8

let s:make_id = 1
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

function! neomake#GetJobs() abort
    return s:jobs
endfunction

function! neomake#ListJobs() abort
    call neomake#utils#DebugMessage('call neomake#ListJobs()')
    for jobinfo in values(s:jobs)
        echom jobinfo.id.' '.jobinfo.name
    endfor
endfunction

function! neomake#CancelJob(job_id) abort
    if !has_key(s:jobs, a:job_id)
        return
    endif
    call jobstop(s:jobs[a:job_id])
endfunction

function! s:GetMakerKey(maker) abort
    return has_key(a:maker, 'name') ? a:maker.name.' ft='.a:maker.ft : 'makeprg'
endfunction

function! s:gettabwinvar(t, w, v, d)
    " Wrapper around gettabwinvar that has no default (Vim in Travis).
    let r = gettabwinvar(a:t, a:w, a:v)
    if r is ''
        unlet r
        let r = a:d
    endif
    return r
endfunction

function! s:getwinvar(w, v, d)
    " Wrapper around getwinvar that has no default (Vim in Travis).
    let r = getwinvar(a:w, a:v)
    if r is ''
        unlet r
        let r = a:d
    endif
    return r
endfunction

function! s:AddJobinfoForCurrentWin(job_id)
    " Add jobinfo to current window.
    let win_jobs = s:gettabwinvar(tabpagenr(), winnr(), 'neomake_jobs', [])
    if index(win_jobs, a:job_id) == -1
        let win_jobs += [a:job_id]
        call settabwinvar(tabpagenr(), winnr(), 'neomake_jobs', win_jobs)
    endif
endfunction

function! neomake#MakeJob(maker) abort
    let make_id = s:make_id
    let s:make_id += 1
    let jobinfo = {
        \ 'name': 'neomake_'.make_id,
        \ 'winnr': winnr(),
        \ 'bufnr': bufnr('%'),
        \ }
    let jobinfo.maker = a:maker

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

    if neomake#utils#IsRunningWindows()
        " Don't expand &shellcmdflag argument of cmd.exe
        call map(args, 'v:val !=? &shellcmdflag ? expand(v:val) : v:val')
    else
        call map(args, 'expand(v:val)')
    endif

    if has_key(a:maker, 'cwd')
        let old_wd = getcwd()
        let cwd = expand(a:maker.cwd, 1)
        exe 'cd' fnameescape(cwd)
    endif

    try
        let has_args = type(args) == type([])
        if has('nvim')
            let argv = [exe]
            if has_args
                let argv = argv + args
            endif
            call neomake#utils#LoudMessage('Starting: '.join(argv, ' '))
            let opts = {
                \ 'on_stdout': function('neomake#MakeHandler'),
                \ 'on_stderr': function('neomake#MakeHandler'),
                \ 'on_exit': function('neomake#MakeHandler')
                \ }
            let job = jobstart(argv, opts)
            let jobinfo.start = localtime()
            let jobinfo.last_register = 0

            if job == 0
                throw 'Job table is full or invalid arguments given'
            elseif job == -1
                throw 'Non executable given'
            endif

            let jobinfo.id = job
            let s:jobs[job] = jobinfo
            let maker_key = s:GetMakerKey(a:maker)
            let s:jobs_by_maker[maker_key] = jobinfo
            call s:AddJobinfoForCurrentWin(jobinfo.id)
            let r = jobinfo.id
        else
            " Vim, synchronously.
            if has_args
                if neomake#utils#IsRunningWindows()
                    let program = exe.' '.join(map(args, 'v:val'))
                else
                    let program = exe.' '.join(map(args, 'shellescape(v:val)'))
                endif
            else
                let program = exe
            endif
            let jobinfo.id = make_id
            let s:jobs[make_id] = jobinfo
            call s:AddJobinfoForCurrentWin(jobinfo.id)
            call neomake#MakeHandler(make_id, split(system(program), '\r\?\n', 1), 'stdout')
            call neomake#MakeHandler(make_id, v:shell_error, 'exit')
            let r = 0
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
    else
        if a:name_or_maker ==# 'makeprg'
            let maker = neomake#utils#MakerFromCommand(&shell, &makeprg)
        elseif len(fts)
            for ft in fts
                let m = get(g:, 'neomake_'.ft.'_'.a:name_or_maker.'_maker')
                if type(m) == type({})
                    let maker = m
                    break
                endif
                unlet m
            endfor
        else
            let maker = get(g:, 'neomake_'.a:name_or_maker.'_maker')
        endif
        if !exists('maker') || type(maker) == type(0)
            unlet! maker
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
                    let maker = {}
                endtry
            endif
        endif
    endif
    let maker = deepcopy(maker)
    if !has_key(maker, 'name')
        let maker.name = a:name_or_maker
    endif
    let defaults = {
        \ 'exe': maker.name,
        \ 'args': [],
        \ 'errorformat': &errorformat,
        \ 'buffer_output': 0,
        \ 'remove_invalid_entries': 1
        \ }
    for key in keys(defaults)
        if len(fts)
            for ft in fts
                let config_var = 'neomake_'.ft.'_'.maker.name.'_'.key
                if has_key(g:, config_var) || has_key(b:, config_var)
                    break
                endif
            endfor
        else
            let config_var = 'neomake_'.maker.name.'_'.key
        endif
        if has_key(b:, config_var)
            let maker[key] = copy(get(b:, config_var))
        elseif has_key(g:, config_var)
            let maker[key] = copy(get(g:, config_var))
        elseif !has_key(maker, key)
            let maker[key] = defaults[key]
        endif
    endfor
    if exists('real_ft')
        let maker.ft = real_ft
    endif
    return maker
endfunction

function! neomake#GetEnabledMakers(...) abort
    if !a:0 || type(a:1) !=# type('')
        " If we have no filetype, our job isn't complicated.
        return get(g:, 'neomake_enabled_makers', [])
    endif

    " If a filetype was passed, get the makers that are enabled for each of
    " the filetypes represented.
    let makers = []
    let makers_count = {}
    let fts = neomake#utils#GetSortedFiletypes(a:1)
    for ft in fts
        let ft = substitute(ft, '\W', '_', 'g')
        let varname = 'g:neomake_'.ft.'_enabled_makers'
        let fnname = 'neomake#makers#ft#'.ft.'#EnabledMakers'
        if exists(varname)
            let enabled_makers = eval(varname)
        else
            try
                let default_makers = eval(fnname . '()')
            catch /^Vim\%((\a\+)\)\=:E117/
                let default_makers = []
            endtry
            let enabled_makers = neomake#utils#AvailableMakers(ft, default_makers)
        endif
        for maker_name in enabled_makers
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
    call neomake#signs#DefineSigns()

    let buf = bufnr('%')
    let win = winnr()
    let ft = get(a:options, 'ft', '')
    let file_mode = get(a:options, 'file_mode')

    if file_mode
        call neomake#statusline#ResetCountsForBuf(buf)
    else
        call neomake#statusline#ResetCounts()
    endif

    let enabled_makers = get(a:options, 'enabled_makers', [])
    if !len(enabled_makers)
        if file_mode
            call neomake#utils#DebugMessage('Nothing to make: no enabled makers')
            return
        else
            let enabled_makers = ['makeprg']
        endif
    endif

    if file_mode
        lgetexpr ''
    else
        cgetexpr ''
    endif
    call s:HandleLoclistQflistDisplay(file_mode)

    if !get(a:options, 'continuation')
        " Only do this if we have one or more enabled makers
        if file_mode
            call neomake#signs#ResetFile(buf)
            let s:need_errors_cleaning['file'][buf] = 1
            let s:loclist_nr = get(s:, 'loclist_nr', {})
            let s:loclist_nr[win] = 0
        else
            call neomake#signs#ResetProject()
            let s:need_errors_cleaning['project'] = 1
            let s:qflist_nr = 0
        endif
    endif

    let serialize = get(g:, 'neomake_serialize')
    let job_ids = []
    for name in enabled_makers
        let maker = neomake#GetMaker(name, ft)
        let maker.file_mode = file_mode
        let maker_key = s:GetMakerKey(maker)
        if has_key(s:jobs_by_maker, maker_key)
            let jobinfo = s:jobs_by_maker[maker_key]
            let jobinfo.maker.next = copy(a:options)
            try
                call jobstop(jobinfo.id)
            catch /^Vim\%((\a\+)\)\=:E900/
                " Ignore invalid job id errors. Happens when the job is done,
                " but on_exit hasn't been called yet.
            endtry
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
        let job_id = neomake#MakeJob(maker)
        call add(job_ids, job_id)
        " If we are serializing makers, stop after the first one. The
        " remaining makers will be processed in turn when this one is done.
        if serialize
            break
        endif
    endfor
    return job_ids
endfunction

function! s:AddExprCallback(maker) abort
    let file_mode = get(a:maker, 'file_mode')
    let place_signs = get(g:, 'neomake_place_signs', 1)
    let list = file_mode ? getloclist(a:maker.winnr) : getqflist()
    let list_modified = 0
    let index = file_mode ? s:loclist_nr[a:maker.winnr] : s:qflist_nr
    let maker_type = file_mode ? 'file' : 'project'

    while index < len(list)
        let entry = list[index]
        let entry.maker_name = has_key(a:maker, 'name') ? a:maker.name : 'makeprg'
        let index += 1

        if has_key(a:maker, 'postprocess')
            call a:maker.postprocess(entry)
        endif

        if !entry.valid
            if a:maker.remove_invalid_entries
                let index -= 1
                call remove(list, index)
                let list_modified = 1
            endif
            continue
        endif

        if !file_mode
            call neomake#statusline#AddQflistCount(entry)
        endif

        if !entry.bufnr
            continue
        endif

        if file_mode
            call neomake#statusline#AddLoclistCount(entry.bufnr, entry)
        endif

        " On the first valid error identified by a maker,
        " clear the existing signs
        if file_mode
            call neomake#CleanOldFileSignsAndErrors(entry.bufnr)
        else
            call neomake#CleanOldProjectSignsAndErrors()
        endif

        " Track all errors by buffer and line
        let s:current_errors[maker_type][entry.bufnr] = get(s:current_errors[maker_type], entry.bufnr, {})
        let s:current_errors[maker_type][entry.bufnr][entry.lnum] = get(
            \ s:current_errors[maker_type][entry.bufnr], entry.lnum, [])
        call add(s:current_errors[maker_type][entry.bufnr][entry.lnum], entry)

        if place_signs
            call neomake#signs#RegisterSign(entry, maker_type)
        endif
    endwhile

    if list_modified
        if file_mode
            call setloclist(a:maker.winnr, list, 'r')
        else
            call setqflist(list, 'r')
        endif
    endif

    if file_mode
        let s:loclist_nr[a:maker.winnr] = index
    else
        let s:qflist_nr = index
    endif
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

function! s:ProcessJobOutput(maker, lines) abort
    call neomake#utils#DebugMessage(get(a:maker, 'name', 'makeprg').' processing '.
                                    \ len(a:lines).' lines of output')
    if len(a:lines)
        let olderrformat = &errorformat
        let &errorformat = a:maker.errorformat
        if get(a:maker, 'file_mode')
            let a:maker.winnr = winnr()
            laddexpr a:lines
        else
            caddexpr a:lines
        endif
        call s:AddExprCallback(a:maker)
        let &errorformat = olderrformat
    endif

    call s:HandleLoclistQflistDisplay(a:maker.file_mode)
endfunction

function! neomake#ProcessCurrentWindow() abort
    let outputs = get(w:, 'neomake_jobs_output', [])
    if len(outputs)
        unlet w:neomake_jobs_output
        for output in outputs
            call s:ProcessJobOutput(output.maker, output.lines)
        endfor
        call neomake#signs#PlaceVisibleSigns()
    endif
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

function! s:RegisterJobOutput(jobinfo, maker, lines) abort
    if has_key(a:maker, 'mapexpr')
        let lines = map(copy(a:lines), a:maker.mapexpr)
    else
        let lines = copy(a:lines)
    endif

    if get(a:maker, 'file_mode')
        let output = {
            \ 'maker': a:maker,
            \ 'lines': lines
            \ }

        let [t, w] = s:GetTabWinForJob(a:jobinfo.id)
        if w != -1
            let w_output = s:gettabwinvar(t, w, 'neomake_jobs_output', [])
                        \ + [output]
            call settabwinvar(t, w, 'neomake_jobs_output', w_output)
        endif

        " Process the window on demand if we can.
        let idx_win_job = index(s:getwinvar(winnr(), 'neomake_jobs', []), a:jobinfo.id)
        if idx_win_job != -1
            call neomake#ProcessCurrentWindow()
        elseif &filetype ==# 'qf'
            " Process the previous window if we are in a qf window.
            wincmd p
            call neomake#ProcessCurrentWindow()
            wincmd p
        endif
    else
        call s:ProcessJobOutput(a:maker, lines)
    endif
endfunction

function! neomake#MakeHandler(job_id, data, event_type) abort
    if !has_key(s:jobs, a:job_id)
        return
    endif
    let jobinfo = s:jobs[a:job_id]
    let maker = jobinfo.maker
    if index(['stdout', 'stderr'], a:event_type) >= 0
        call neomake#utils#DebugMessage(
            \ get(maker, 'name', 'makeprg').' '.a:event_type.': ["'.join(a:data, '", "').'"]')
        call neomake#utils#DebugMessage(
            \ get(maker, 'name', 'makeprg').' '.a:event_type.' done.')

        " Register job output. Buffer registering of output for long running
        " jobs.
        let last_event_type = get(jobinfo, 'event_type', a:event_type)
        let jobinfo.event_type = a:event_type

        " a:data is a List of 'lines' read. Each element *after* the first
        " element represents a newline
        if has_key(jobinfo, 'lines')
            " As per https://github.com/neovim/neovim/issues/3555
            let jobinfo.lines = jobinfo.lines[:-2]
                        \ + [jobinfo.lines[-1] . get(a:data, 0, '')]
                        \ + a:data[1:]
        else
            let jobinfo.lines = a:data
        endif

        let now = localtime()
        if (!maker.buffer_output || last_event_type !=# a:event_type) ||
                \ (last_event_type !=# a:event_type ||
                \  now - jobinfo.start < 1 ||
                \  now - jobinfo.last_register > 3)
            call s:RegisterJobOutput(jobinfo, maker, jobinfo.lines[:-2])
            let jobinfo.lines = jobinfo.lines[-1:]
            let jobinfo.last_register = now
        endif
    elseif a:event_type ==# 'exit'
        if has_key(jobinfo, 'lines')
            if jobinfo.lines[-1] == ''
                call remove(jobinfo.lines, -1)
            endif
            call s:RegisterJobOutput(jobinfo, maker, jobinfo.lines)
        endif

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
        if has('nvim')
            " Only report completion for neovim, since it is asynchronous
            call neomake#utils#QuietMessage(get(maker, 'name', 'make').
                                          \ ' completed with exit code '.status)
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
                call neomake#utils#DebugMessage('next makers '.next_makers)
                call s:Make(maker.next)
            endif
        endif
    endif
endfunction

function! neomake#CleanOldProjectSignsAndErrors() abort
    if s:need_errors_cleaning['project']
        for buf in keys(s:current_errors.project)
            unlet s:current_errors['project'][buf]
        endfor
        let s:need_errors_cleaning['project'] = 0
        call neomake#utils#DebugMessage('All project-level errors cleaned.')
    endif
    call neomake#signs#CleanAllOldSigns('project')
endfunction

function! neomake#CleanOldFileSignsAndErrors(bufnr) abort
    if get(s:need_errors_cleaning['file'], a:bufnr, 0)
        if has_key(s:current_errors['file'], a:bufnr)
            unlet s:current_errors['file'][a:bufnr]
        endif
        unlet s:need_errors_cleaning['file'][a:bufnr]
        call neomake#utils#DebugMessage('File-level errors cleaned in buffer '.a:bufnr)
    endif
    call neomake#signs#CleanOldSigns(a:bufnr, 'file')
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

function! neomake#CompleteMakers(ArgLead, ...) abort
    if a:ArgLead =~# '[^A-Za-z0-9]'
        return []
    else
        return filter(neomake#GetEnabledMakers(&filetype),
                    \ "v:val =~? '^".a:ArgLead."'")
    endif
endfunction

function! neomake#Make(file_mode, enabled_makers, ...) abort
    let options = a:0 ? { 'exit_callback': a:1 } : {}
    if a:file_mode
        let options.enabled_makers = len(a:enabled_makers) ?
                    \ a:enabled_makers :
                    \ neomake#GetEnabledMakers(&filetype)
        let options.ft = &filetype
        let options.file_mode = 1
    else
        let options.enabled_makers = len(a:enabled_makers) ?
                    \ a:enabled_makers :
                    \ neomake#GetEnabledMakers()
    endif
    return s:Make(options)
endfunction

function! neomake#Sh(sh_command, ...) abort
    let options = a:0 ? { 'exit_callback': a:1 } : {}
    let custom_maker = neomake#utils#MakerFromCommand(&shell, a:sh_command)
    let custom_maker.name = 'sh: '.a:sh_command
    let custom_maker.remove_invalid_entries = 0
    let options.enabled_makers =  [custom_maker]
    return s:Make(options)[0]
endfunction
