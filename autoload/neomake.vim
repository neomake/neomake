" vim: ts=4 sw=4 et
scriptencoding utf-8

let s:make_id = 1
let s:jobs = {}
let s:jobs_by_maker = {}
let s:job_output_by_buffer = {}

function! neomake#ListJobs() abort
    call neomake#utils#DebugMessage('call neomake#ListJobs()')
    for jobinfo in values(s:jobs)
        echom jobinfo.id.' '.jobinfo.name
    endfor
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
    let append_file = a:maker.file_mode && index(args, '%:p') <= 0
    if append_file
        call add(args, '%:p')
    endif
    call map(args, 'expand(v:val)')

    let job = s:JobStart(make_id, a:maker.exe, args)

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
endfunction

function! neomake#GetMaker(name, ...) abort
    if a:0
        let ft = a:1
    else
        let ft = ''
    endif
    if type(a:name) == type({})
        let maker = a:name
    else
        if a:name ==# 'makeprg'
            let maker = neomake#utils#MakerFromCommand(&shell, &makeprg)
        elseif len(ft)
            let maker = get(g:, 'neomake_'.ft.'_'.a:name.'_maker')
        else
            let maker = get(g:, 'neomake_'.a:name.'_maker')
        endif
        if type(maker) == type(0)
            unlet maker
            try
                if len(ft)
                    let maker = eval('neomake#makers#ft#'.ft.'#'.a:name.'()')
                else
                    let maker = eval('neomake#makers#'.a:name.'#'.a:name.'()')
                endif
            catch /^Vim\%((\a\+)\)\=:E117/
                let maker = {}
            endtry
        endif
    endif
    let maker = copy(maker)
    let defaults = {
        \ 'exe': a:name,
        \ 'args': [],
        \ 'errorformat': '',
        \ 'buffer_output': 0,
        \ }
    for key in keys(defaults)
        if len(ft)
            let config_var = 'neomake_'.ft.'_'.a:name.'_'.key
        else
            let config_var = 'neomake_'.a:name.'_'.key
        endif
        if has_key(g:, config_var)
            let maker[key] = copy(get(g:, config_var))
        elseif !has_key(maker, key)
            let maker[key] = defaults[key]
        endif
    endfor
    let maker.name = a:name
    let maker.ft = ft
    " Only relevant if file_mode is used
    let maker.winnr = winnr()
    return maker
endfunction

function! neomake#GetEnabledMakers(...) abort
    if a:0 && type(a:1) == type('')
        let ft = a:1
    else
        let ft = ''
    endif
    if len(ft)
        let enabled_makers = get(g:, 'neomake_'.ft.'_enabled_makers')
    else
        let enabled_makers = get(g:, 'neomake_enabled_makers')
    endif
    if type(enabled_makers) == type(0)
        unlet enabled_makers
        try
            let default_makers = eval('neomake#makers#ft#'.ft.'#EnabledMakers()')
        catch /^Vim\%((\a\+)\)\=:E117/
            return []
        endtry

        let enabled_makers = neomake#utils#AvailableMakers(ft, default_makers)
        if !len(enabled_makers)
            call neomake#utils#DebugMessage('None of the default '.ft.' makers ('
                        \ .join(default_makers, ', ').',) are available on '.
                        \ 'your system. Install one of them or configure your '.
                        \ 'own makers.')
            return []
        endif
    endif
    return enabled_makers
endfunction

function! neomake#Make(options) abort
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
        call neomake#signs#Reset()
        let s:neomake_list_nr = 0
        let s:cleared_current_errors = 0
    endif

    let serialize = get(g:, 'neomake_serialize')
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
        call neomake#MakeJob(maker)
        " If we are serializing makers, stop after the first one. The
        " remaining makers will be processed in turn when this one is done.
        if serialize
            break
        endif
    endfor
endfunction

function! s:AddExprCallback(maker) abort
    let file_mode = get(a:maker, 'file_mode')
    let place_signs = get(g:, 'neomake_place_signs', 1)
    let list = file_mode ? getloclist(a:maker.winnr) : getqflist()

    while s:neomake_list_nr < len(list)
        let entry = list[s:neomake_list_nr]
        let s:neomake_list_nr += 1

        if !entry.bufnr || !entry.valid
            continue
        endif

        " On the first valid error identified by a maker,
        " clear the existing signs in the buffer
        call s:CleanSignsAndErrors()

        " Track all errors by buffer and line
        let s:current_errors[entry.bufnr] = get(s:current_errors, entry.bufnr, {})
        let s:current_errors[entry.bufnr][entry.lnum] = get(
            \ s:current_errors[entry.bufnr], entry.lnum, [])
        call add(s:current_errors[entry.bufnr][entry.lnum], entry)

        if place_signs
            call neomake#signs#RegisterSign(entry)
        endif
    endwhile
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
        if has_key(a:maker, 'errorformat')
            let olderrformat = &errorformat
            let &errorformat = a:maker.errorformat
        endif

        if get(a:maker, 'file_mode')
            laddexpr a:lines
        else
            caddexpr a:lines
        endif
        call s:AddExprCallback(a:maker)

        if exists('olderrformat')
            let &errorformat = olderrformat
        endif
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

        if maker.buffer_output
            let last_event_type = get(jobinfo, 'event_type', a:event_type)
            let jobinfo.event_type = a:event_type
            if last_event_type ==# a:event_type
                if has_key(jobinfo, 'lines')
                    call extend(jobinfo.lines, lines)
                else
                    let jobinfo.lines = lines
                endif
            else
                call s:RegisterJobOutput(jobinfo, maker, jobinfo.lines)
                let jobinfo.lines = lines
            endif
        else
            call s:RegisterJobOutput(jobinfo, maker, lines)
        endif
    elseif a:event_type ==# 'exit'
        if has_key(jobinfo, 'lines')
            call s:RegisterJobOutput(jobinfo, maker, jobinfo.lines)
        endif
        " TODO This used to open up as the list was populated, but it caused
        " some issues with s:AddExprCallback.
        if get(g:, 'neomake_open_list')
            let height = get(g:, 'neomake_list_height', 10)
            if get(maker, 'file_mode')
                exe "lwindow ".height
            else
                exe "cwindow ".height
            endif
        endif
        let status = a:data
        call s:CleanJobinfo(jobinfo)
        if has('nvim')
            " Only report completion for neovim, since it is asynchronous
            call neomake#utils#QuietMessage(get(maker, 'name', 'make').
                                          \ ' complete with exit code '.status)
        endif

        " If signs were not cleared before this point, then the maker did not return
        " any errors, so all signs must be removed
        call s:CleanSignsAndErrors()

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

function! s:CleanSignsAndErrors()
    call neomake#signs#CleanOldSigns()
    if !s:cleared_current_errors
        let s:current_errors = {}
        let s:cleared_current_errors = 1
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

    let errors = get(s:, 'current_errors', {})
    if empty(errors)
        return
    endif

    let buf = bufnr('%')
    let buf_errors = get(errors, buf, {})
    let ln = line('.')
    let ln_errors = get(buf_errors, ln, [])
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
    call neomake#utils#WideMessage(s:neomake_last_echoed_error.text)
endfunction

function! neomake#CursorMoved() abort
    call neomake#signs#PlaceVisibleSigns()
    call neomake#EchoCurrentError()
endfunction
