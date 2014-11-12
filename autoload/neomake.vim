sign define neomake_err text=✖
sign define neomake_warn text=⚠

let s:make_id = 1
let s:jobs = {}
let s:window_jobs = {}

function! s:MakeJobFromMaker(jobname, maker)
    if has_key(a:maker, 'args')
        let args = copy(a:maker.args)
    else
        let args = []
    endif
    let fidx = index(args, '%:p')
    let fpath = expand('%:p')
    if fidx < 0
        call add(args, fpath)
    else
        args[fidx] = fpath
    endif
    return jobstart(a:jobname, a:maker.exe, args)
endfunction

function! neomake#MakeJob(...)
    let jobname = 'neomake_' . s:make_id
    let s:make_id += 1
    let jobinfo = {}
    if a:0
        let jobinfo['maker'] = a:1
        let jobname .= '_' . a:1.exe
        let job = s:MakeJobFromMaker(jobname, a:1)
    else
        let job = jobstart(jobname, &shell, ['-c', &makeprg])
    endif

    if job == 0
        throw 'Job table is full or invalid arguments given'
    elseif job == -1
        throw 'Non executable given'
    endif
    let jobinfo['name'] = jobname
    let jobinfo['winnr'] = winnr()
    let jobinfo['bufnr'] = bufnr('%')
    let jobinfo['id'] = job

    let s:jobs[job] = jobinfo
    call add(s:window_jobs[jobinfo.winnr], jobinfo)
endfunction

function! neomake#GetMaker(ft, name)
    let maker = get(g:, 'neomake_'.a:ft.'_'.a:name.'_maker')
    if type(maker) == type(0)
        unlet maker
        try
            let maker = eval('neomake#makers#'.a:ft.'#'.a:name.'()')
        catch /^Vim\%((\a\+)\)\=:E117/
            let maker = {}
        endtry
    endif
    if !has_key(maker, 'exe')
        let maker['exe'] = a:name
    endif
    let maker['name'] = a:name
    let maker['ft'] = a:ft
    return maker
endfunction

function! neomake#GetEnabledMakers(ft)
    let enabled_makers = get(g:, 'neomake_'.a:ft.'_enabled_makers')
    if type(enabled_makers) == type(0)
        unlet enabled_makers
        try
            let enabled_makers = eval('neomake#makers#'.a:ft.'#EnabledMakers()')
        catch /^Vim\%((\a\+)\)\=:E117/
            let enabled_makers = []
        endtry
    endif
    return enabled_makers
endfunction

function! neomake#Make(...)
    lgetexpr ''

    if !bufnr('%')
        throw 'Invalid buffer, cannot Neomake'
    endif

    " Remove any signs we placed before
    let b:neomake_signs = get(b:, 'neomake_signs', [])
    for s in b:neomake_signs
        exe 'sign unplace '.s
    endfor
    let b:neomake_signs = []

    " Stop jobs so we don't create too many copies of the same job
    let my_winnr = winnr()
    if has_key(s:window_jobs, my_winnr)
        echom 'Stopping '.len(s:window_jobs[my_winnr]).' job early'
        for jobinfo in s:window_jobs[my_winnr]
            call jobstop(jobinfo.id)
        endfor
    else
        let s:window_jobs[my_winnr] = []
    endif

    " Get enabled makers for this filetype
    if a:0
        let enabled_makers = [a:1]
    else
        let enabled_makers = neomake#GetEnabledMakers(&ft)
    endif

    if len(enabled_makers)
        for name in enabled_makers
            call neomake#MakeJob(neomake#GetMaker(&ft, name))
        endfor
    else
        call neomake#MakeJob()
    endif
endfunction

function! s:WinBufDo(winnr, bufnr, action)
    let result = ''
    let old_winnr = winnr()
    let old_bufnr = bufnr('%')
    if old_winnr != a:winnr
        let result .= a:winnr . 'wincmd w | '
    endif
    if old_bufnr != a:bufnr
        let result .= a:bufnr . 'b | '
    endif
    let result .= a:action
    if old_bufnr != a:bufnr
        let result .= old_bufnr . 'b | '
    endif
    if old_winnr != a:winnr
        " Switch back to whatever buffer you were using
        let result .= ' | ' . old_winnr . 'wincmd w'
    endif
    return result
endfunction

function! s:GetSignsInBuffer(bufnr)
    let signs = {}
    redir => signs_txt | exe 'sign place buffer='.a:bufnr | redir END
    for s in split(signs_txt, '\n')
        if s =~# 'name='
            let ln = 0 + substitute(s, '.*line=\(\d\+\).*', '\1', '')
            let id = 0 + substitute(s, '.*id=\(\d\+\).*', '\1', '')
            let signs[ln] = id
        endif
    endfor
    return signs
endfunction

function! s:LaddrCallback(maker)
    let b:neomake_loclist_nr = get(b:, 'neomake_loclist_nr', 0)
    let loclist = deepcopy(getloclist(0))

    let sign_id = 1
    let redraw = 0
    while b:neomake_loclist_nr < len(loclist)
        let entry = loclist[b:neomake_loclist_nr]
        let b:neomake_loclist_nr += 1
        if !entry.valid
            continue
        endif
        if !exists('l:signs')
            let l:signs = s:GetSignsInBuffer(entry.bufnr)
            let sign_id = max([sign_id - 1] + values(l:signs)) + 1
        endif
        let s = sign_id
        let sign_id += 1
        if has_key(l:signs, entry.lnum)
            exe 'sign unplace '.l:signs[entry.lnum]
        endif
        let type = entry.type ==# 'E' ? 'neomake_err' : 'neomake_warn'
        exe 'sign place '.s.' line='.entry['lnum'].' name='.type.' buffer='.entry['bufnr']
        call add(b:neomake_signs, s)
        let redraw = 1
    endwhile
    if redraw
        redraw!
    endif

    if len(a:maker) && exists('g:Neomake_'.&ft.'_'.a:maker['name'].'_laddexprCallback')
        exe 'call g:Neomake_'.&ft.'_'.a:maker['name'].'_laddexprCallback()'
    endif
    if exists('g:Neomake_'.&ft.'_laddexprCallback')
        exe 'call g:Neomake_'.&ft.'_laddexprCallback()'
    endif
    if exists('g:Neomake_laddexprCallback')
        call g:Neomake_laddexprCallback()
    endif
endfunction

function! s:MakerCompleteCallback(maker)
    if len(a:maker) && exists("g:Neomake_".&ft."_".a:maker["name"]."_completeCallback")
        exe "call g:Neomake_".&ft."_".a:maker["name"]."_completeCallback()"
    endif
endfunction

function! s:CompleteCallback()
    unlet b:neomake_loclist_nr
    if exists("g:Neomake_".&ft."_completeCallback")
        exe "call g:Neomake_".&ft."_completeCallback()"
    endif
    if exists("g:Neomake_completeCallback")
        call g:Neomake_completeCallback()
    endif
endfunction

function! neomake#MakeHandler()
    let jobinfo = s:jobs[v:job_data[0]]
    if has_key(jobinfo, 'maker')
        let maker = jobinfo.maker
    else
        let maker = {}
    endif
    if index(['stdout', 'stderr'], v:job_data[1]) >= 0
        if has_key(maker, 'errorformat')
            let olderrformat = &errorformat
            let &errorformat = maker.errorformat
        else
            let olderrformat = ''
        endif

        exe s:WinBufDo(jobinfo.winnr, jobinfo.bufnr, 'laddexpr v:job_data[2] | call s:LaddrCallback(maker)')

        if len(olderrformat)
            let &errorformat = olderrformat
        endif
    else
        call remove(s:jobs, v:job_data[0])
        exe s:WinBufDo(jobinfo.winnr, jobinfo.bufnr, 'call s:MakerCompleteCallback(maker)')
        call remove(s:window_jobs[jobinfo.winnr], index(s:window_jobs[jobinfo.winnr], jobinfo))
        if !len(s:window_jobs[jobinfo.winnr])
            call remove(s:window_jobs, jobinfo.winnr)
            exe s:WinBufDo(jobinfo.winnr, jobinfo.bufnr, 'call s:CompleteCallback()')
        endif
    endif
endfunction
