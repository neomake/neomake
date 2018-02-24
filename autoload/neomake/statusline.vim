scriptencoding utf-8

let s:qflist_counts = {}
let s:loclist_counts = {}

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
    let bufnr = a:make_info.options.bufnr
    if !has_key(s:loclist_counts, bufnr)
        let s:loclist_counts[bufnr] = {}
    endif
    call s:clear_cache(bufnr)

    " Trigger redraw of all statuslines.
    " TODO: only do this if some relevant formats are used?!
    redrawstatus!
endfunction

function! neomake#statusline#ResetCountsForBuf(...) abort
    let bufnr = a:0 ? +a:1 : bufnr('%')
    call s:clear_cache(bufnr)
    if has_key(s:loclist_counts, bufnr)
      let r = s:loclist_counts[bufnr] != {}
      unlet s:loclist_counts[bufnr]
      if r
          call neomake#utils#hook('NeomakeCountsChanged', {
                \ 'reset': 1, 'file_mode': 1, 'bufnr': bufnr})
      endif
      return r
    endif
    return 0
endfunction

function! neomake#statusline#ResetCountsForProject(...) abort
    let r = s:qflist_counts != {}
    let s:qflist_counts = {}
    let bufnr = bufnr('%')
    if r
        call neomake#utils#hook('NeomakeCountsChanged', {
              \ 'reset': 1, 'file_mode': 0, 'bufnr': bufnr})
    endif
    call s:clear_cache(bufnr)
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


let s:formatter = {
            \ 'args': {},
            \ }
function! s:formatter.running_job_names() abort
    let jobs = get(self.args, 'running_jobs', s:running_jobs(self.args.bufnr))
    return join(map(jobs, "v:val.name . (v:val.file_mode ? '' : '!')"), ', ')
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
        call neomake#utils#ErrorMessage(printf(
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
        call neomake#utils#ErrorMessage(printf(
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
            return s:formatter.format(format_running, {
                        \ 'bufnr': a:bufnr,
                        \ 'running_jobs': running_jobs})
        endif
    endif

    let [loclist_counts, qflist_counts] = neomake#statusline#get_counts(a:bufnr)
    if empty(loclist_counts)
        if loclist_counts is s:no_loclist_counts
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
    if has_key(s:cache[a:bufnr], cache_key)
        return s:cache[a:bufnr][cache_key]
    endif
    let bufnr = +a:bufnr
    call s:setup_statusline_augroup_for_use()

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
