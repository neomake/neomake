" vim: ts=4 sw=4 et

let s:make_id = 1
let s:jobs = {}
let s:jobs_by_maker = {}

function! neomake#ListJobs() abort
    call neomake#utils#DebugMessage('call neomake#ListJobs()')
    for jobinfo in values(s:jobs)
        echom jobinfo.id.' '.jobinfo.name
    endfor
endfunction

function! s:JobStart(make_id, name, exe, ...) abort
    let has_args = a:0 && type(a:1) == type([])
    if has('nvim')
        if has_args
            let exe = a:exe
            let args = a:1
        else
            let exe = &shell
            let args = ['-c', a:exe]
        endif
        call neomake#utils#LoudMessage('Starting: '.exe.' '.join(args, ' '))
        return jobstart(a:name, exe, args)
    else
        if has_args
            let program = a:exe.' '.join(map(a:1, 'shellescape(v:val)'))
        else
            let program = a:exe
        endif
        call neomake#MakeHandler([a:make_id, 'stdout', split(system(program), '\r\?\n', 1)])
        call neomake#MakeHandler([a:make_id, 'exit', v:shell_error])
        return 0
    endif
endfunction

function! s:MakeJobFromMaker(make_id, jobname, maker) abort
    if has_key(a:maker, 'args')
        let args = copy(a:maker.args)
    else
        let args = []
    endif

    " Add makepath to args
    let makepathIdx = index(args, '{{makepath}}')
    if makepathIdx < 0
        let makepathIdx = index(args, '!!makepath!!')
    endif
    if makepathIdx >= 0
        let args[makepathIdx] = a:maker.makepath
    elseif len(a:maker.makepath)
        call add(args, a:maker.makepath)
    endif

    return s:JobStart(a:make_id, a:jobname, a:maker.exe, args)
endfunction

function! s:GetMakerKey(maker) abort
    return has_key(a:maker, 'name') ? a:maker.name.' ft='.a:maker.ft : 'makeprg'
endfunction

function! neomake#MakeJob(...) abort
    let make_id = s:make_id
    let s:make_id += 1
    let jobinfo = {
        \ 'name': 'neomake_'.make_id,
        \ 'winnr': winnr(),
        \ 'bufnr': bufnr('%'),
        \ }
    if !has('nvim')
        let jobinfo.id = make_id
        let s:jobs[make_id] = jobinfo
    endif
    if a:0 && len(a:1)
        let maker = a:1
        let jobinfo.name .= '_'.maker.name
        let jobinfo.maker = maker
        let job = s:MakeJobFromMaker(make_id, jobinfo.name, maker)
    else
        let maker = {}
        let jobinfo.maker = maker
        let job = s:JobStart(make_id, jobinfo.name, &makeprg)
    endif

    " Async setup that only affects neovim
    if has('nvim')
        if job == 0
            throw 'Job table is full or invalid arguments given'
        elseif job == -1
            throw 'Non executable given'
        endif

        let jobinfo.id = job
        let s:jobs[job] = jobinfo

        let maker_key = s:GetMakerKey(maker)
        if has_key(s:jobs_by_maker, maker_key)
            call jobstop(s:jobs_by_maker[maker_key].id)
            call s:CleanJobinfo(s:jobs_by_maker[maker_key])
        endif
        let s:jobs_by_maker[maker_key] = jobinfo
    endif
endfunction

function! neomake#GetMaker(name, makepath, ...) abort
    if a:0
        let ft = a:1
    else
        let ft = ''
    endif
    if len(ft)
        let maker = get(g:, 'neomake_'.ft.'_'.a:name.'_maker')
    else
        let maker = get(g:, 'neomake_'.a:name.'_maker')
    endif
    if type(maker) == type(0)
        unlet maker
        try
            if len(ft)
                let maker = eval('neomake#makers#'.ft.'#'.a:name.'()')
            else
                let maker = {}
            endif
        catch /^Vim\%((\a\+)\)\=:E117/
            let maker = {}
        endtry
    endif
    let maker = copy(maker)
    let maker['makepath'] = a:makepath
    if !has_key(maker, 'exe')
        let maker['exe'] = a:name
    endif
    let maker['name'] = a:name
    let maker['ft'] = ft
    return maker
endfunction

function! neomake#GetEnabledMakers(...) abort
    let default = ['makeprg']
    if a:0 && type(a:1) == type('')
        let ft = a:1
    else
        let ft = ''
    endif
    if len(ft)
        let enabled_makers = get(g:, 'neomake_'.ft.'_enabled_makers')
    else
        let enabled_makers = get(g:, 'neomake_enabled_makers', default)
    endif
    if type(enabled_makers) == type(0)
        unlet enabled_makers
        try
            let default_makers = eval('neomake#makers#'.ft.'#EnabledMakers()')
        catch /^Vim\%((\a\+)\)\=:E117/
            return default
        endtry

        let enabled_makers = neomake#utils#AvailableMakers(ft, default_makers)
        if !len(enabled_makers)
            call neomake#utils#ErrorMessage('None of the default '.ft.' makers ('
                        \ .join(default_makers, ', ').',) are available on '.
                        \ 'your system. Install one of them or configure your '.
                        \ 'own makers.')
            return default
        endif
    endif
    return enabled_makers
endfunction

function! neomake#Make(options) abort
    if get(g:, 'neomake_place_signs', 1)
        try
            silent sign list neomake_err
        catch /^Vim\%((\a\+)\)\=:E155/
            call neomake#utils#RedefineErrorSign()
        endtry
        try
            silent sign list neomake_warn
        catch /^Vim\%((\a\+)\)\=:E155/
            call neomake#utils#RedefineWarningSign()
        endtry
    endif

    let ft = get(a:options, 'ft', '')
    let enabled_makers = get(a:options, 'enabled_makers', ['makeprg'])
    let file_mode = get(a:options, 'file_mode')
    if file_mode
        lgetexpr ''
    else
        cgetexpr ''
    endif

    if file_mode
        let b:neomake_loclist_nr = 0
        let b:neomake_errors = {}
        " Remove any signs we placed before
        let b:neomake_signs = get(b:, 'neomake_signs', {})
        for ln in keys(b:neomake_signs)
            exe 'sign unplace '.b:neomake_signs[ln]
        endfor
        let b:neomake_signs = {}
    endif

    let serialize = get(g:, 'neomake_serialize')
    for name in enabled_makers
        if name ==# 'makeprg'
            call neomake#MakeJob()
        else
            let tempfile = 0
            let tempsuffix = ''
            let makepath = ''
            if file_mode
                let makepath = expand('%')
                if get(g:, 'neomake_make_modified', 0) && &mod
                    let tempfile = 1
                    let tempsuffix = '.'.neomake#utils#Random().'.neomake.tmp'
                    let makepath .= tempsuffix
                    " TODO Make this cross platform
                    silent exe 'w !cat > '.shellescape(makepath)
                    neomake#utils#LoudMessage('Neomake: wrote temp file '.makepath)
                endif
            endif
            let maker = neomake#GetMaker(name, makepath, ft)
            let maker['file_mode'] = file_mode
            if tempfile
                let maker['tempfile'] = makepath
                let maker['tempsuffix'] = tempsuffix
            endif
            if serialize && len(enabled_makers) > 1
                let next_opts = copy(a:options)
                let next_opts['enabled_makers'] = enabled_makers[1:]
                let maker['next'] = next_opts
            endif
            call neomake#MakeJob(maker)
        endif
        if serialize
            break
        endif
    endfor
endfunction

function! s:WinBufDo(winnr, bufnr, action) abort
    let old_winnr = winnr()
    let old_bufnr = bufnr('%')
    return 'if winnr() !=# '.a:winnr.' | '.a:winnr.'wincmd w | endif | '.
         \ 'if bufnr("%") !=# '.a:bufnr.' | '.a:bufnr.'b | endif | '.
         \ a:action.' | '.
         \ 'if bufnr("%") !=# '.old_bufnr.' | '.old_bufnr.'b | endif | '.
         \ 'if winnr() !=# '.old_winnr.' | '.old_winnr.'wincmd w | endif'
endfunction

function! neomake#GetSigns(...) abort
    let signs = {
        \ 'by_line': {},
        \ 'max_id': 0,
        \ }
    if a:0
        let opts = a:1
    else
        let opts = {}
    endif
    let place_cmd = 'sign place'
    for attr in keys(opts)
        if attr ==# 'file' || attr ==# 'buffer'
            let place_cmd .= ' '.attr.'='.opts[attr]
        endif
    endfor
    call neomake#utils#DebugMessage('executing: '.place_cmd)
    redir => signs_txt | silent exe place_cmd | redir END
    let fname_pattern = 'Signs for \(.*\):'
    for s in split(signs_txt, '\n')
        if s =~# fname_pattern
            " This should always happen first, so don't define outside loop
            let fname = substitute(s, fname_pattern, '\1', '')
        elseif s =~# 'id='
            let result = {}
            let parts = split(s, '\s\+')
            for part in parts
                let [key, val] = split(part, '=')
                let result[key] = val =~# '\d\+' ? 0 + val : val
            endfor
            let result.file = fname
            if !has_key(opts, 'name') || opts.name ==# result.name
                let signs.by_line[result.line] = get(signs.by_line, result.line, [])
                call add(signs.by_line[result.line], result)
                let signs.max_id = max([signs.max_id, result.id])
            endif
        endif
    endfor
    return signs
endfunction

function! neomake#GetSignsInBuffer(bufnr) abort
    return neomake#GetSigns({'buffer': a:bufnr})
endfunction

function! s:AddExprCallback(maker) abort
    let file_mode = get(a:maker, 'file_mode')
    let place_signs = get(g:, 'neomake_place_signs', 1)
    if file_mode
        let loclist = getloclist(0)

        let sign_id = 1
        let placed_sign = 0
        while b:neomake_loclist_nr < len(loclist)
            let entry = loclist[b:neomake_loclist_nr]
            let b:neomake_loclist_nr += 1

            if !entry.bufnr
                continue
            endif
            if !entry.valid
                continue
            endif

            " Track all errors by line
            let b:neomake_errors[entry.lnum] = get(b:neomake_errors, entry.lnum, [])
            call add(b:neomake_errors[entry.lnum], entry)

            if place_signs
                if !exists('l:signs')
                    let l:signs = neomake#GetSignsInBuffer(entry.bufnr)
                    let sign_id = l:signs.max_id + 1
                endif
                let s = sign_id
                let sign_id += 1
                let type = entry.type ==# 'E' ? 'neomake_err' : 'neomake_warn'

                let l:signs.by_line[entry.lnum] = get(l:signs.by_line, entry.lnum, [])
                if !has_key(b:neomake_signs, entry.lnum)
                    exe 'sign place '.s.' line='.entry.lnum.' name='.type.' buffer='.entry.bufnr
                    let b:neomake_signs[entry.lnum] = s
                elseif type ==# 'neomake_err'
                    " Upgrade this sign to an error
                    exe 'sign place '.b:neomake_signs[entry.lnum].' name='.type.' buffer='.entry.bufnr
                endif
                let placed_sign = 1

                " Replace all existing signs for this line, so that ours appears
                " on top
                for existing in get(l:signs.by_line, entry.lnum, [])
                    if existing.name !~# 'neomake_'
                        exe 'sign unplace '.existing.id.' buffer='.entry.bufnr
                        exe 'sign place '.existing.id.' line='.existing.line.' name='.existing.name.' buffer='.entry.bufnr
                    endif
                endfor
            endif
        endwhile
        if placed_sign
            redraw!
        endif
    endif

    if get(g:, 'neomake_open_list')
        let old_w = winnr()
        if file_mode
            lwindow
        else
            cwindow
        endif
        " s:WinBufDo doesn't work right if we change windows on it.
        exe old_w.'wincmd w'
    endif
endfunction

function! s:CleanJobinfo(jobinfo) abort
    let maker = a:jobinfo.maker
    if has_key(maker, 'tempfile')
        let rmResult = neomake#utils#RemoveFile(maker.tempfile)
        if !rmResult
            call neomake#utils#ErrorMessage('Failed to remove temporary file '.maker.tempfile)
        endif
    endif
    let maker_key = s:GetMakerKey(maker)
    if has_key(s:jobs_by_maker, maker_key)
        unlet s:jobs_by_maker[maker_key]
    endif
    call remove(s:jobs, a:jobinfo.id)
endfunction

function! neomake#MakeHandler(...) abort
    if a:0
        let job_data = a:1
    else
        let job_data = v:job_data
    endif
    if !has_key(s:jobs, job_data[0])
        return
    endif
    let jobinfo = s:jobs[job_data[0]]
    let maker = jobinfo.maker
    if index(['stdout', 'stderr'], job_data[1]) >= 0
        if has_key(maker, 'tempsuffix')
            let pattern = substitute(maker.tempsuffix, '\.', '\.', 'g')
            let lines = map(copy(job_data[2]), 'substitute(v:val, pattern, "", "g")')
        else
            let lines = job_data[2]
        endif

        if has_key(maker, 'mapexpr')
            let lines = map(copy(lines), maker.mapexpr)
        endif

        for line in lines
            call neomake#utils#DebugMessage(
                \ get(maker, 'name', 'make').' '.job_data[1].': '.line)
        endfor

        if len(lines) > 0
            if has_key(maker, 'errorformat')
                let olderrformat = &errorformat
                let &errorformat = maker.errorformat
            endif

            let addexpr_suffix = 'lines | call s:AddExprCallback(maker)'
            if get(maker, 'file_mode')
                exe s:WinBufDo(jobinfo.winnr, jobinfo.bufnr, 'laddexpr '.addexpr_suffix)
            else
                exe 'caddexpr '.addexpr_suffix
            endif

            if exists('olderrformat')
                let &errorformat = olderrformat
            endif
        endif
    else
        let status = get(job_data, 2, 0)
        call s:CleanJobinfo(jobinfo)
        if has_key(maker, 'name')
            let msg = maker.name.' complete'
        else
            let msg = 'make complete'
        endif
        if status !=# 0
            call neomake#utils#ErrorMessage(msg.' with error status '.status)
        else
            call neomake#utils#QuietMessage(msg)
        endif
        " Show the current line's error
        call neomake#CursorMoved()

        " TODO when neovim implements getting the exit status of a job, add
        " option to only run next checkers if this one succeeded.
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

function! neomake#CursorMoved() abort
    if !get(g:, 'neomake_echo_current_error', 1)
        return
    endif

    if !empty(get(b:, 'neomake_last_echoed_error', {}))
        unlet b:neomake_last_echoed_error
        echon ''
    endif

    let errors = get(b:, 'neomake_errors', {})
    if empty(errors)
        return
    endif

    let ln = line('.')
    let ln_errors = get(errors, ln, [])
    if empty(ln_errors)
        return
    endif

    let b:neomake_last_echoed_error = ln_errors[0]
    for error in ln_errors
        if error.type ==# 'E'
            let b:neomake_last_echoed_error = error
            break
        endif
    endfor
    call neomake#utils#WideMessage(b:neomake_last_echoed_error.text)
endfunction
