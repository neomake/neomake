scriptencoding utf-8

let s:qflist_counts = {}
let s:loclist_counts = {}

function! s:incCount(counts, item, buf) abort
    let type = toupper(a:item.type)
    if !empty(type) && (!a:buf || a:item.bufnr ==# a:buf)
        let a:counts[type] = get(a:counts, type, 0) + 1
        if a:buf
            if has_key(s:cache, a:buf)
                unlet s:cache[a:buf]
            endif
        else
            let s:cache = {}
        endif
        return 1
    endif
    return 0
endfunction

function! neomake#statusline#buffer_finished(bufnr) abort
    if !has_key(s:loclist_counts, a:bufnr)
        let s:loclist_counts[a:bufnr] = {}
        if has_key(s:cache, a:bufnr)
            unlet s:cache[a:bufnr]
        endif
    endif
endfunction

function! neomake#statusline#ResetCountsForBuf(...) abort
    let bufnr = a:0 ? +a:1 : bufnr('%')
    if has_key(s:loclist_counts, bufnr)
      let r = s:loclist_counts[bufnr] != {}
      unlet s:loclist_counts[bufnr]
      if r
          call neomake#utils#hook('NeomakeCountsChanged', {
                \ 'reset': 1, 'file_mode': 1, 'bufnr': bufnr})
      endif
      if has_key(s:cache, bufnr)
          unlet s:cache[bufnr]
      endif
      return r
    endif
    return 0
endfunction

function! neomake#statusline#ResetCountsForProject(...) abort
    let r = s:qflist_counts != {}
    let s:qflist_counts = {}
    if r
        call neomake#utils#hook('NeomakeCountsChanged', {
              \ 'reset': 1, 'file_mode': 0, 'bufnr': bufnr('%')})
    endif
    return r
endfunction

function! neomake#statusline#ResetCounts() abort
    let r = neomake#statusline#ResetCountsForProject()
    for bufnr in keys(s:loclist_counts)
        let r = neomake#statusline#ResetCountsForBuf(bufnr) || r
    endfor
    let s:loclist_counts = {}
    return r
endfunction

function! neomake#statusline#AddLoclistCount(buf, item) abort
    let s:loclist_counts[a:buf] = get(s:loclist_counts, a:buf, {})
    return s:incCount(s:loclist_counts[a:buf], a:item, a:buf)
endfunction

function! neomake#statusline#AddQflistCount(item) abort
    return s:incCount(s:qflist_counts, a:item, 0)
endfunction

function! neomake#statusline#LoclistCounts(...) abort
    let buf = a:0 ? a:1 : bufnr('%')
    if buf is# 'all'
        return s:loclist_counts
    endif
    return get(s:loclist_counts, buf, {})
endfunction

function! neomake#statusline#QflistCounts() abort
    return s:qflist_counts
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

let s:no_loclist_counts = {}
function! neomake#statusline#get_counts(bufnr) abort
    return [get(s:loclist_counts, a:bufnr, s:no_loclist_counts), s:qflist_counts]
endfunction

function! neomake#statusline#get_filtered_counts(bufnr, ...) abort
    let include = a:0 ? a:1 : []
    let exclude = a:0 > 1 ? a:2 : []
    let empty = a:0 > 2 ? a:3 : ''

    let [loclist_counts, qf_errors] = neomake#statusline#get_counts(a:bufnr)

    let errors = []
    for [type, c] in items(loclist_counts)
        if len(include) && index(include, type) == -1 | continue | endif
        if len(exclude) && index(exclude, type) != -1 | continue | endif
        let errors += [type . ':' .c]
    endfor
    if ! empty(qf_errors)
        for [type, c] in items(qf_errors)
            if len(include) && index(include, type) == -1 | continue | endif
            if len(exclude) && index(exclude, type) != -1 | continue | endif
            let errors += [type . ':' .c]
        endfor
    endif
    if len(errors)
        return ' '.join(errors)
    endif
    return empty
endfunction


let s:formatter = {
            \ 'args': {},
            \ }
function! s:formatter.running_job_names() abort
    let jobs = get(self.args, 'running_jobs', s:running_jobs(self.args.bufnr))
    return join(map(jobs, 'v:val.name'), ', ')
endfunction

function! s:formatter._substitute(m) abort
    if has_key(self.args, a:m)
        return self.args[a:m]
    endif
    if !has_key(self, a:m)
        call neomake#utils#ErrorMessage(printf(
                    \ 'Unknown statusline format: {{%s}}.', a:m))
        return '{{'.a:m.'}}'
    endif
    try
        return call(self[a:m], [], self)
    catch
        call neomake#utils#ErrorMessage(printf(
                    \ 'Error while formatting statusline: %s.', v:exception))
    endtry
endfunction

function! s:formatter.format(f, args) abort
    let self.args = a:args
    return substitute(a:f, '{{\(.\{-}\)}}', '\=self._substitute(submatch(1))', 'g')
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
            return s:formatter.format(format_running, {
                        \ 'bufnr': a:bufnr,
                        \ 'running_jobs': running_jobs})
        endif
    endif

    let [loclist_counts, qflist_counts] = neomake#statusline#get_counts(a:bufnr)
    if empty(loclist_counts)
        if loclist_counts is s:no_loclist_counts
            let format_unknown = get(a:options, 'format_unknown', '?')
            let r .= s:formatter.format(format_unknown, {'bufnr': a:bufnr})
        else
            let format_ok = get(a:options, 'format_ok', '%#NeomakeStatusGood#✓')
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

function! neomake#statusline#clear_cache(bufnr) abort
    call s:clear_cache(a:bufnr)
endfunction

" Key: bufnr, Value: dict with cache keys.
let s:cache = {}
" For debugging.
function! neomake#statusline#get_s() abort
    return s:
endfunction

function! s:clear_cache(bufnr) abort
    if has_key(s:cache, a:bufnr)
        unlet s:cache[a:bufnr]
    endif
endfunction

function! neomake#statusline#get(bufnr, options) abort
    let cache_key = string(a:options)
    if !has_key(s:cache, a:bufnr)
        let s:cache[a:bufnr] = {}
    endif
    if has_key(s:cache[a:bufnr], cache_key)
        return s:cache[a:bufnr][cache_key]
    endif
    let bufnr = +a:bufnr

    " TODO: needs to go into cache key then!
    if getbufvar(bufnr, '&filetype') ==# 'qf'
        let s:cache[a:bufnr][cache_key] = ''
        return ''
    endif

    let r = ''
    let [disabled, source] = neomake#config#get_with_source('disabled', -1, {'bufnr': bufnr})
    if disabled != -1
        if disabled
            let r .= source[0].'-'
        else
            let r .= source[0].'+'
        endif
    else
        let status = neomake#statusline#get_status(bufnr, a:options)
        if has_key(a:options, 'format_status')
            let status = printf(a:options.format_status, status)
        endif
        let r .= status
    endif

    let s:cache[a:bufnr][cache_key] = r
    return r
endfunction

" XXX: TODO
function! neomake#statusline#DefineHighlights() abort
    if exists('g:neomake_statusline_bg')
        let stlbg = g:neomake_statusline_bg
    else
        let stlbg = neomake#utils#GetHighlight('StatusLine', 'bg')
    endif

    " Highlights.
    exe 'hi default NeomakeStatusGood ctermfg=green ctermbg=' . stlbg

    " Base highlight for type counts.
    exe 'hi NeomakeStatColorTypes cterm=NONE ctermfg=white ctermbg=blue'

    " Specific highlights for types.  Only used if defined.
    exe 'hi NeomakeStatColorTypeE cterm=NONE ctermfg=white ctermbg=red'
    hi link NeomakeStatColorQuickfixTypeE NeomakeStatColorTypeE

    exe 'hi NeomakeStatColorTypeW cterm=NONE ctermfg=white ctermbg=yellow'

    hi link NeomakeStatColorTypeI NeomakeStatColorTypes
endfunction

augroup neomake_statusline
    autocmd!
    autocmd User NeomakeJobStarted,NeomakeJobFinished call s:clear_cache(g:neomake_hook_context.jobinfo.bufnr)
    " Trigger redraw of all statuslines.
    " TODO: only do this if some relevant formats are used?!
    autocmd User NeomakeJobFinished let &stl = &stl
    autocmd BufWipeout * call s:clear_cache(expand('<abuf>'))
    autocmd ColorScheme * call neomake#statusline#DefineHighlights()
augroup END
call neomake#statusline#DefineHighlights()
