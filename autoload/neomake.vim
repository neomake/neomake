" vim: ts=4 sw=4 et
scriptencoding utf-8

let s:make_id = 1
let s:jobs = {}
let s:jobs_by_maker = {}
let s:job_output_by_buffer = {}
let s:current_errors = {
    \ 'project': {},
    \ 'file': {}
    \ }
let s:need_errors_cleaning = {
    \ 'project': 1,
    \ 'file': {}
    \ }

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
    call jobstop(a:job_id)
endfunction

function! s:JobStart(make_id, exe, ...) abort
    let argv = [a:exe]
    let has_args = a:0 && type(a:1) == type([])
    if has('nvim')
        if has_args
            let argv = argv + a:1
        endif
        call neomake#utils#LoudMessage('Starting: '.join(argv, ' '))
        let opts = {
            \ 'on_stdout': function('neomake#MakeHandler'),
            \ 'on_stderr': function('neomake#MakeHandler'),
            \ 'on_exit': function('neomake#MakeHandler')
            \ }
        return jobstart(argv, opts)
    else
        if has_args
            let program = a:exe.' '.join(map(a:1, 'shellescape(v:val)'))
        else
            let program = a:exe
        endif
        call neomake#MakeHandler(a:make_id, split(system(program), '\r\?\n', 1), 'stdout')
        call neomake#MakeHandler(a:make_id, v:shell_error, 'exit')
        return 0
    endif
endfunction

function! s:GetMakerKey(maker) abort
    return has_key(a:maker, 'name') ? a:maker.name.' ft='.a:maker.ft : 'makeprg'
endfunction

function! neomake#MakeJob(maker) abort
    let make_id = s:make_id
    let s:make_id += 1
    let jobinfo = {
        \ 'name': 'neomake_'.make_id,
        \ 'winnr': winnr(),
        \ 'bufnr': bufnr('%'),
        \ }
    if !has('nvim')
        let jobinfo.id = make_id
        " Assign this before neomake#MakeHandler gets run synchronously
        let s:jobs[make_id] = jobinfo
    endif
    let jobinfo.maker = a:maker

    let args = a:maker.args
    let append_file = a:maker.file_mode && index(args, '%:p') <= 0 && get(a:maker, 'append_file', 1)
    if append_file
        call add(args, '%:p')
    endif
    call map(args, 'expand(v:val)')

    if has_key(a:maker, 'cwd')
        let old_wd = getcwd()
        let cwd = expand(a:maker.cwd, 1)
        exe 'cd' fnameescape(cwd)
    endif

    let job = s:JobStart(make_id, a:maker.exe, args)
    let jobinfo.start = localtime()
    let jobinfo.last_register = 0

    " Async setup that only affects neovim
    if has('nvim')
        if job == 0
            throw 'Job table is full or invalid arguments given'
        elseif job == -1
            throw 'Non executable given'
        endif

        let jobinfo.id = job
        let s:jobs[job] = jobinfo
        let maker_key = s:GetMakerKey(a:maker)
        let s:jobs_by_maker[maker_key] = jobinfo
    endif

    if has_key(a:maker, 'cwd')
        exe 'cd' fnameescape(old_wd)
    endif

    return jobinfo.id
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
                let maker = get(g:, 'neomake_'.ft.'_'.a:name_or_maker.'_maker')
                if type(maker) == type({})
                    break
                endif
            endfor
        else
            let maker = get(g:, 'neomake_'.a:name_or_maker.'_maker')
        endif
        if type(maker) == type(0)
            unlet maker
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
    let maker.ft = real_ft
    " Only relevant if file_mode is used
    let maker.winnr = winnr()
    return maker
endfunction

function! neomake#GetEnabledMakers(...) abort
    if !a:0 || type(a:1) !=# type('')
        " If we have no filetype, our job isn't complicated.
        return get(g:, 'neomake_enabled_makers', [])
    endif

    " If a filetype was passed, get the makers that are enabled for each of
    " the filetypes represented.
    let union = {}
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
            let union[maker_name] = get(union, maker_name, 0) + 1
        endfor
    endfor

    let l = len(fts)
    return filter(keys(union), 'union[v:val] ==# l')
endfunction

function! s:Make(options) abort
    call neomake#signs#DefineSigns()
    call neomake#statusline#ResetCounts()

    let ft = get(a:options, 'ft', '')
    let file_mode = get(a:options, 'file_mode')

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

    if !get(a:options, 'continuation')
        " Only do this if we have one or more enabled makers
        if file_mode
            let buf = bufnr('%')
            let win = winnr()
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
            let Func = a:maker.postprocess
            call Func(entry)
        end

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
            call neomake#statusline#AddLoclistCount(
                \ a:maker.winnr, entry.bufnr, entry)
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
endfunction

function! s:ProcessJobOutput(maker, lines) abort
    call neomake#utils#DebugMessage(get(a:maker, 'name', 'makeprg').' processing '.
                                    \ len(a:lines).' lines of output')
    if len(a:lines) > 0
        let olderrformat = &errorformat
        let &errorformat = a:maker.errorformat

        if get(a:maker, 'file_mode')
            laddexpr a:lines
        else
            caddexpr a:lines
        endif
        call s:AddExprCallback(a:maker)

        let &errorformat = olderrformat
    endif
endfunction

function! neomake#ProcessCurrentBuffer() abort
    let buf = bufnr('%')
    if has_key(s:job_output_by_buffer, buf)
        for output in s:job_output_by_buffer[buf]
            call s:ProcessJobOutput(output.maker, output.lines)
        endfor
        unlet s:job_output_by_buffer[buf]
    endif
    call neomake#signs#PlaceVisibleSigns()
endfunction

function! s:RegisterJobOutput(jobinfo, maker, lines) abort
    if get(a:maker, 'file_mode')
        let output = {
            \ 'maker': a:maker,
            \ 'lines': a:lines
            \ }
        if has_key(s:job_output_by_buffer, a:jobinfo.bufnr)
            call add(s:job_output_by_buffer[a:jobinfo.bufnr], output)
        else
            let s:job_output_by_buffer[a:jobinfo.bufnr] = [output]
        endif

        " Process the buffer on demand if we can
        if bufnr('%') ==# a:jobinfo.bufnr
            call neomake#ProcessCurrentBuffer()
        endif
        if &ft ==# 'qf'
            " Process the previous window if we are in a qf window.
            wincmd p
            call neomake#ProcessCurrentBuffer()
            wincmd p
        endif
    else
        call s:ProcessJobOutput(a:maker, a:lines)
    endif
endfunction

function! neomake#MakeHandler(job_id, data, event_type) abort
    if !has_key(s:jobs, a:job_id)
        return
    endif
    let jobinfo = s:jobs[a:job_id]
    let maker = jobinfo.maker
    if index(['stdout', 'stderr'], a:event_type) >= 0
        let lines = a:data
        if has_key(maker, 'mapexpr')
            let lines = map(copy(lines), maker.mapexpr)
        endif

        for line in lines
            call neomake#utils#DebugMessage(
                \ get(maker, 'name', 'makeprg').' '.a:event_type.': '.line)
        endfor
        call neomake#utils#DebugMessage(
            \ get(maker, 'name', 'makeprg').' '.a:event_type.' done.')

        " Register job output. Buffer registering of output for long running
        " jobs.
        let last_event_type = get(jobinfo, 'event_type', a:event_type)
        let jobinfo.event_type = a:event_type
        if has_key(jobinfo, 'lines')
            " As per https://github.com/neovim/neovim/issues/3555
            let jobinfo.lines = jobinfo.lines[:-2]
                        \ + [jobinfo.lines[-1] . get(lines, 0, '')]
                        \ + lines[1:]
        else
            let jobinfo.lines = lines
        endif
        let now = localtime()
        if (!maker.buffer_output || last_event_type !=# a:event_type) ||
                \ (last_event_type !=# a:event_type ||
                \  now - jobinfo.start < 1 ||
                \  now - jobinfo.last_register > 3)
            call s:RegisterJobOutput(jobinfo, maker, jobinfo.lines)
            unlet jobinfo.lines
            let jobinfo.last_register = now
        endif
    elseif a:event_type ==# 'exit'
        if has_key(jobinfo, 'lines')
            call s:RegisterJobOutput(jobinfo, maker, jobinfo.lines)
        endif
        " TODO This used to open up as the list was populated, but it caused
        " some issues with s:AddExprCallback.
        if get(g:, 'neomake_open_list')
            let height = get(g:, 'neomake_list_height', 10)
            let open_val = g:neomake_open_list
            let win_val = winnr()
            if get(maker, 'file_mode')
                exe "lwindow ".height
            else
                exe "cwindow ".height
            endif
            if open_val == 2 && win_val != winnr()
                wincmd p
            endif
        endif
        let status = a:data
        if has_key(maker, 'exit_callback')
            let callback_dict = { 'status': status,
                                \ 'name': maker.name,
                                \ 'has_next': has_key(maker, 'next') }
            if type(maker.exit_callback) == type('')
                let ExitCallback = function(maker.exit_callback)
            else
                let ExitCallback = maker.exit_callback
            endif
            try
                call ExitCallback(callback_dict)
            catch /^Vim\%((\a\+)\)\=:E117/
            endtry
        endif
        call s:CleanJobinfo(jobinfo)
        if has('nvim')
            " Only report completion for neovim, since it is asynchronous
            call neomake#utils#QuietMessage(get(maker, 'name', 'make').
                                          \ ' complete with exit code '.status)
        endif

        " If signs were not cleared before this point, then the maker did not return
        " any errors, so all signs must be removed
        if maker.file_mode
            call neomake#CleanOldFileSignsAndErrors(jobinfo.bufnr)
        else
            call neomake#CleanOldProjectSignsAndErrors()
        endif

        " Show the current line's error
        call neomake#CursorMoved()

        if has_key(maker, 'next')
            let next_makers = '['.join(maker.next.enabled_makers, ', ').']'
            if get(g:, 'neomake_serialize_abort_on_error') && status !=# 0
                call neomake#utils#LoudMessage('Aborting next makers '.next_makers)
            else
                call neomake#utils#DebugMessage('next makers '.next_makers)
                call neomake#Make(maker.next)
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
        call neomake#utils#DebugMessage("All project-level errors cleaned.")
    endif
    call neomake#signs#CleanAllOldSigns('project')
endfunction

function! neomake#CleanOldFileSignsAndErrors(bufnr) abort
    if get(s:need_errors_cleaning['file'], a:bufnr, 0)
        if has_key(s:current_errors['file'], a:bufnr)
            unlet s:current_errors['file'][a:bufnr]
        endif
        unlet s:need_errors_cleaning['file'][a:bufnr]
        call neomake#utils#DebugMessage("File-level errors cleaned in buffer ".a:bufnr)
    endif
    call neomake#signs#CleanOldSigns(a:bufnr, 'file')
endfunction

function! neomake#CleanOldErrors(bufnr, type) abort
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

function! neomake#CursorMoved() abort
    call neomake#signs#PlaceVisibleSigns()
    call neomake#EchoCurrentError()
endfunction

function! neomake#CompleteMakers(ArgLead, CmdLine, CursorPos)
    if a:ArgLead =~ '[^A-Za-z0-9]'
        return []
    else
        return filter(neomake#GetEnabledMakers(&ft),
                    \ "v:val =~? '^".a:ArgLead."'")
    endif
endfunction

function! neomake#Make(file_mode, enabled_makers, ...)
    let options = a:0 ? { 'exit_callback': a:1 } : {}
    if a:file_mode
        let options.enabled_makers = len(a:enabled_makers) ?
                    \ a:enabled_makers :
                    \ neomake#GetEnabledMakers(&ft)
        let options.ft = &ft
        let options.file_mode = 1
    else
        let options.enabled_makers = len(a:enabled_makers) ?
                    \ a:enabled_makers :
                    \ neomake#GetEnabledMakers()
    endif
    return s:Make(options)
endfunction

function! neomake#Sh(sh_command, ...)
    let options = a:0 ? { 'exit_callback': a:1 } : {}
    let custom_maker = neomake#utils#MakerFromCommand(&shell, a:sh_command)
    let custom_maker.name = 'sh: '.a:sh_command
    let custom_maker.remove_invalid_entries = 0
    let options.enabled_makers =  [custom_maker]
    return s:Make(options)[0]
endfunction
