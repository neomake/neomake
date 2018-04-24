scriptencoding utf-8

unlockvar s:unknown_counts
let s:unknown_counts = {}
lockvar s:unknown_counts

let s:counts = {}

" Key: bufnr, Value: dict with cache keys.
let s:cache = {}

" For debugging.
let g:neomake#statusline#_s = s:

function! s:clear_cache(bufnr) abort
    if has_key(s:cache, a:bufnr)
        unlet s:cache[a:bufnr]
    endif
endfunction

function! neomake#statusline#clear_cache() abort
    let s:cache = {}
endfunction

function! s:incCount(counts, item, buf) abort
    if !empty(a:item.type) && (!a:buf || a:item.bufnr ==# a:buf)
        let type = toupper(a:item.type)
        let a:counts[type] = get(a:counts, type, 0) + 1
        if a:buf
            call s:clear_cache(a:buf)
        else
            let s:cache = {}
        endif
        return 1
    endif
    return 0
endfunction

function! neomake#statusline#make_finished(make_info) abort
    if a:make_info.options.file_mode
        let bufnr = a:make_info.options.bufnr
        if !empty(a:make_info.finished_jobs) && !has_key(s:counts, bufnr)
            let s:counts[bufnr] = {}
        endif
        call s:clear_cache(bufnr)
    else
        let s:cache = {}
        if !empty(a:make_info.finished_jobs) && !has_key(s:counts, 'project')
            let s:counts['project'] = {}
        endif
    endif

    " Trigger redraw of all statuslines.
    " TODO: only do this if some relevant formats are used?!
    redrawstatus!
endfunction

function! neomake#statusline#ResetCountsForBuf(...) abort
    let bufnr = a:0 ? +a:1 : bufnr('%')
    call s:clear_cache(bufnr)
    if has_key(s:counts, bufnr)
      let r = s:counts[bufnr] != {}
      unlet s:counts[bufnr]
      if r
          call neomake#utils#hook('NeomakeCountsChanged', {
                \ 'reset': 1, 'file_mode': 1, 'bufnr': bufnr})
      endif
      return r
    endif
    return 0
endfunction

function! neomake#statusline#ResetCountsForProject(...) abort
    let s:cache = {}
    if !has_key(s:counts, 'project')
        return 0
    endif
    let r = s:counts['project'] != {}
    let bufnr = bufnr('%')
    unlet s:counts['project']
    if r
        call neomake#utils#hook('NeomakeCountsChanged', {
              \ 'reset': 1, 'file_mode': 0, 'bufnr': bufnr})
    endif
    return r
endfunction

function! neomake#statusline#ResetCounts() abort
    let r = neomake#statusline#ResetCountsForProject()
    for bufnr in keys(s:counts)
        let r = neomake#statusline#ResetCountsForBuf(bufnr) || r
    endfor
    let s:counts = {}
    return r
endfunction

function! neomake#statusline#AddLoclistCount(buf, item) abort
    let s:counts[a:buf] = get(s:counts, a:buf, {})
    return s:incCount(s:counts[a:buf], a:item, a:buf)
endfunction

function! neomake#statusline#AddQflistCount(item) abort
    let s:counts['project'] = get(s:counts, 'project', {})
    return s:incCount(s:counts['project'], a:item, 0)
endfunction

function! neomake#statusline#LoclistCounts(...) abort
    let buf = a:0 ? a:1 : bufnr('%')
    if buf is# 'all'
        return s:counts
    endif
    return get(s:counts, buf, {})
endfunction

function! neomake#statusline#QflistCounts() abort
    return get(s:counts, 'project', s:unknown_counts)
endfunction

function! s:showErrWarning(counts, prefix) abort
    let w = get(a:counts, 'W', 0)
    let e = get(a:counts, 'E', 0)
    if w || e
        let result = a:prefix
        if e
            let result .= 'E:'.e
        endif
        if w
            if e
                let result .= ','
            endif
            let result .= 'W:'.w
        endif
        return result
    else
        return ''
    endif
endfunction

function! neomake#statusline#LoclistStatus(...) abort
    return s:showErrWarning(neomake#statusline#LoclistCounts(), a:0 ? a:1 : '')
endfunction

function! neomake#statusline#QflistStatus(...) abort
    return s:showErrWarning(neomake#statusline#QflistCounts(), a:0 ? a:1 : '')
endfunction

" Get counts for a bufnr or 'project'.
" Returns all counts when used without arguments.
function! neomake#statusline#get_counts(...) abort
    if a:0
        return get(s:counts, a:1, s:unknown_counts)
    endif
    return s:counts
endfunction


let s:formatter = {
            \ 'args': {},
            \ }
function! s:formatter.running_job_names() abort
    let jobs = get(self.args, 'running_jobs', s:running_jobs(self.args.bufnr))
    let sep = get(self.args, 'running_jobs_separator', ', ')
    let format_running_job_file = get(self.args, 'format_running_job_file', '%s')
    let format_running_job_project = get(self.args, 'format_running_job_project', '%s!')
    let formatted = []
    for job in jobs
        if job.file_mode
            call add(formatted, printf(format_running_job_file, job.name))
        else
            call add(formatted, printf(format_running_job_project, job.name))
        endif
    endfor
    return join(formatted, sep)
endfunction

function! s:formatter._substitute(m) abort
    if has_key(self.args, a:m)
        return self.args[a:m]
    endif
    if !has_key(self, a:m)
        let self.errors += [printf('Unknown statusline format: {{%s}}.', a:m)]
        return '{{'.a:m.'}}'
    endif
    try
        return call(self[a:m], [], self)
    catch
        call neomake#log#error(printf(
                    \ 'Error while formatting statusline: %s.', v:exception))
    endtry
endfunction

function! s:formatter.format(f, args) abort
    if empty(a:f)
        return a:f
    endif
    let self.args = a:args
    let self.errors = []
    let r = substitute(a:f, '{{\(.\{-}\)}}', '\=self._substitute(submatch(1))', 'g')
    if !empty(self.errors)
        call neomake#log#error(printf(
                    \ 'Error%s when formatting %s: %s',
                    \ len(self.errors) > 1 ? 's' : '',
                    \ string(a:f), join(self.errors, ', ')))
    endif
    return r
endfunction


function! s:running_jobs(bufnr) abort
    return filter(copy(neomake#GetJobs()),
                \ "v:val.bufnr == a:bufnr && !get(v:val, 'canceled', 0)")
endfunction

function! neomake#statusline#get_status(bufnr, options) abort
    let r = ''

    let running_jobs = s:running_jobs(a:bufnr)
    if !empty(running_jobs)
        let format_running = get(a:options, 'format_running', '… ({{running_job_names}})')
        if format_running isnot 0
            let args = {'bufnr': a:bufnr, 'running_jobs': running_jobs}
            for opt in ['running_jobs_separator', 'format_running_job_project', 'format_running_job_file']
                if has_key(a:options, opt)
                    let args[opt] = a:options[opt]
                endif
            endfor
            return s:formatter.format(format_running, args)
        endif
    endif

    let loclist_counts = get(s:counts, a:bufnr, s:unknown_counts)
    if empty(loclist_counts)
        if loclist_counts is s:unknown_counts
            let format_unknown = get(a:options, 'format_loclist_unknown', '?')
            let r .= s:formatter.format(format_unknown, {'bufnr': a:bufnr})
        else
            let format_ok = get(a:options, 'format_loclist_ok', '%#NeomakeStatusGood#✓')
            let r .= s:formatter.format(format_ok, {'bufnr': a:bufnr})
        endif
    else
        let format_loclist = get(a:options, 'format_loclist_issues', '%s')
        if !empty(format_loclist)
            let loclist = ''
            for [type, c] in items(loclist_counts)
                if has_key(a:options, 'format_loclist_type_'.type)
                    let format = a:options['format_loclist_type_'.type]
                elseif hlexists('NeomakeStatColorType'.type)
                    let format = '%#NeomakeStatColorType{{type}}# {{type}}:{{count}} '
                else
                    let format = ' {{type}}:{{count}} '
                endif
                " let format = get(a:options, 'format_type_'.type, '%#NeomakeStatColorType{{type}}# {{type}}:{{count}} ')
                let loclist .= s:formatter.format(format, {
                            \ 'bufnr': a:bufnr,
                            \ 'count': c,
                            \ 'type': type})
            endfor
            let r = printf(format_loclist, loclist)
        endif
    endif

    " Quickfix counts.
    let qflist_counts = get(s:counts, 'project', s:unknown_counts)
    if empty(qflist_counts)
        let format_ok = get(a:options, 'format_quickfix_ok', '')
        if !empty(format_ok)
            let r .= s:formatter.format(format_ok, {'bufnr': a:bufnr})
        endif
    else
        let format_quickfix = get(a:options, 'format_quickfix_issues', '%s')
        if !empty(format_quickfix)
            let quickfix = ''
            for [type, c] in items(qflist_counts)
                if has_key(a:options, 'format_quickfix_type_'.type)
                    let format = a:options['format_quickfix_type_'.type]
                elseif hlexists('NeomakeStatColorQuickfixType'.type)
                    let format = '%#NeomakeStatColorQuickfixType{{type}}# Q{{type}}:{{count}} '
                else
                    let format = ' Q{{type}}:{{count}} '
                endif
                if !empty(format)
                    let quickfix .= s:formatter.format(format, {
                                \ 'bufnr': a:bufnr,
                                \ 'count': c,
                                \ 'type': type})
                endif
            endfor
            let r = printf(format_quickfix, quickfix)
        endif
    endif
    return r
endfunction

function! neomake#statusline#get(bufnr, options) abort
    let cache_key = string(a:options)
    if !has_key(s:cache, a:bufnr)
        let s:cache[a:bufnr] = {}
    endif
    if !has_key(s:cache[a:bufnr], cache_key)
        let bufnr = +a:bufnr
        call s:setup_statusline_augroup_for_use()

        " TODO: needs to go into cache key then!
        if getbufvar(bufnr, '&filetype') ==# 'qf'
            let s:cache[a:bufnr][cache_key] = ''
        else
            let [disabled, src] = neomake#config#get_with_source('disabled', -1, {'bufnr': bufnr, 'log_source': 'statusline#get'})
            if src ==# 'default'
                let disabled_scope = ''
            else
                let disabled_scope = src[0]
            endif
            if disabled != -1 && disabled
                " Automake Disabled
                let format_disabled_info = get(a:options, 'format_disabled_info', '{{disabled_scope}}-')
                let disabled_info = s:formatter.format(format_disabled_info,
                      \ {'disabled_scope': disabled_scope})
                " Defaults to showing the disabled information (i.e. scope)
                let format_disabled = get(a:options, 'format_status_disabled', '{{disabled_info}} %s')
                let outer_format = s:formatter.format(format_disabled, {'disabled_info': disabled_info})
            else
                " Automake Enabled
                " Defaults to showing only the status
                let format_enabled = get(a:options, 'format_status_enabled', '%s')
                let outer_format = s:formatter.format(format_enabled, {})
            endif
            let format_status = get(a:options, 'format_status', '%s')
            let status = neomake#statusline#get_status(bufnr, a:options)

            let r = printf(outer_format, printf(format_status, status))

            let s:cache[a:bufnr][cache_key] = r
        endif
    endif
    return s:cache[a:bufnr][cache_key]
endfunction

" XXX: TODO: cleanup/doc?!
function! neomake#statusline#DefineHighlights() abort
    for suffix in ['', 'NC']
      let hl = 'StatusLine'.suffix
      " Uses "green" for NeomakeStatusGood, but the default with
      " NeomakeStatusGoodNC (since it might be underlined there, and should
      " not stand out in general there).
      exe 'hi default NeomakeStatusGood'.suffix
            \ . ' ctermfg=' . (suffix ? neomake#utils#GetHighlight(hl, 'fg') : 'green')
            \ . ' guifg=' . (suffix ? neomake#utils#GetHighlight(hl, 'fg#') : 'green')
            \ . ' ctermbg='.neomake#utils#GetHighlight(hl, 'bg')
            \ . ' guifg='.neomake#utils#GetHighlight(hl, 'bg#')
            \ . (neomake#utils#GetHighlight(hl, 'underline') ? ' cterm=underline' : '')
            \ . (neomake#utils#GetHighlight(hl, 'underline#') ? ' gui=underline' : '')
            \ . (neomake#utils#GetHighlight(hl, 'reverse') ? ' cterm=reverse' : '')
            \ . (neomake#utils#GetHighlight(hl, 'reverse#') ? ' gui=reverse' : '')
    endfor

    " Base highlight for type counts.
    exe 'hi NeomakeStatColorTypes cterm=NONE ctermfg=white ctermbg=blue'

    " Specific highlights for types.  Only used if defined.
    exe 'hi NeomakeStatColorTypeE cterm=NONE ctermfg=white ctermbg=red'
    hi link NeomakeStatColorQuickfixTypeE NeomakeStatColorTypeE

    exe 'hi NeomakeStatColorTypeW cterm=NONE ctermfg=white ctermbg=yellow'

    hi link NeomakeStatColorTypeI NeomakeStatColorTypes
endfunction

let s:did_setup_statusline_augroup_for_use = 0
function! s:setup_statusline_augroup_for_use() abort
    if s:did_setup_statusline_augroup_for_use
        return
    endif
    augroup neomake_statusline
        autocmd ColorScheme * call neomake#statusline#DefineHighlights()
    augroup END
    let s:did_setup_statusline_augroup_for_use = 1
endfunction

" Global augroup, gets configured always currently when autoloaded.
augroup neomake_statusline
    autocmd!
    autocmd BufWipeout * call s:clear_cache(expand('<abuf>'))
augroup END
call neomake#statusline#DefineHighlights()
