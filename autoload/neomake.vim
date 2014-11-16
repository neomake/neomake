scriptencoding utf-8

sign define neomake_err text=✖
sign define neomake_warn text=⚠

let s:make_id = 1
let s:jobs = {}
let s:jobs_by_maker = {}
let s:sign_id = 7500

function! neomake#ListJobs() abort
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
        return jobstart(a:name, exe, args)
    else
        if has_args
            let program = a:exe.' '.join(map(a:1, 'shellescape(v:val)'))
        else
            let program = a:exe
        endif
        call neomake#MakeHandler([a:make_id, 'stdout', system(program)])
        call neomake#MakeHandler([a:make_id, 'exit', ''])
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
            let enabled_makers = eval('neomake#makers#'.ft.'#EnabledMakers()')
        catch /^Vim\%((\a\+)\)\=:E117/
            return default
            let enabled_makers = default
        endtry
    endif
    return enabled_makers
endfunction

function! neomake#Make(options) abort
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
        " Remove any signs we placed before
        let b:neomake_signs = get(b:, 'neomake_signs', [])
        for s in b:neomake_signs
            exe 'sign unplace '.s
        endfor
        let b:neomake_signs = []
    endif

    for name in enabled_makers
        if name ==# 'makeprg'
            call neomake#MakeJob()
        else
            if !get(a:options, 'no_makepath')
                if file_mode
                    let makepath = expand('%')
                else
                    let makepath = getcwd()
                endif
            else
                let makepath = ''
            endif
            let maker = neomake#GetMaker(name, makepath, ft)
            let maker['file_mode'] = file_mode
            call neomake#MakeJob(maker)
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

function! neomake#GetSignsInBuffer(bufnr) abort
    let signs = {
        \ 'by_line': {},
        \ 'max_id': 0,
        \ }
    redir => signs_txt | silent exe 'sign place buffer='.a:bufnr | redir END
    for s in split(signs_txt, '\n')
        if s =~# 'id='
            let result = {}
            let parts = split(s, '\s\+')
            for part in parts
                let [key, val] = split(part, '=')
                let result[key] = val =~# '\d\+' ? 0 + val : val
            endfor
            let signs.by_line[result.line] = get(signs.by_line, result.line, [])
            call add(signs.by_line[result.line], result)
            let signs.max_id = max([signs.max_id, result.id])
        endif
    endfor
    return signs
endfunction

function! s:AddExprCallback(maker) abort
    let file_mode = get(a:maker, 'file_mode')
    if file_mode
        let b:neomake_loclist_nr = get(b:, 'neomake_loclist_nr', 0)
        let loclist = getloclist(0)

        let sign_id = 1
        let placed_sign = 0
        while b:neomake_loclist_nr < len(loclist)
            let entry = loclist[b:neomake_loclist_nr]
            let b:neomake_loclist_nr += 1
            if !entry.valid
                continue
            endif
            if !exists('l:signs')
                let l:signs = neomake#GetSignsInBuffer(entry.bufnr)
                let sign_id = l:signs.max_id + 1
            endif
            let s = sign_id
            let sign_id += 1
            let type = entry.type ==# 'E' ? 'neomake_err' : 'neomake_warn'

            let l:signs.by_line[entry.lnum] = get(l:signs.by_line, entry.lnum, [])
            call add(l:signs.by_line[entry.lnum], {'id': s, 'line': entry.lnum, 'name': type})
            exe 'sign place '.s.' line='.entry.lnum.' name='.type.' buffer='.entry.bufnr
            call add(b:neomake_signs, s)
            let placed_sign = 1

            " Replace all existing signs for this line, so that ours appears
            " on top
            for existing in get(l:signs.by_line, entry.lnum, [])
                if existing.name !=# 'neomake_err'
                    exe 'sign unplace '.existing.id.' buffer='.entry.bufnr
                    exe 'sign place '.existing.id.' line='.existing.line.' name='.existing.name.' buffer='.entry.bufnr
                endif
            endfor
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
    let maker_key = s:GetMakerKey(a:jobinfo.maker)
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
    let jobinfo['leftovers'] = get(jobinfo, 'leftovers', '')
    if index(['stdout', 'stderr'], job_data[1]) >= 0
        let jobinfo['last_stream'] = job_data[1]
        let data = jobinfo.leftovers . job_data[2]
        let lines = split(data, '\r\n\|\r\|\n', 1)
        let jobinfo['leftovers'] = lines[-1]

        if len(lines) > 1
            if has_key(maker, 'errorformat')
                let olderrformat = &errorformat
                let &errorformat = maker.errorformat
            endif

            let addexpr_suffix = 'lines[:-2] | call s:AddExprCallback(maker)'
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
        if len(jobinfo.leftovers)
            call neomake#MakeHandler([job_data[0], jobinfo.last_stream, "\n"])
        endif
        call s:CleanJobinfo(jobinfo)
    endif
endfunction
