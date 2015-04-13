
function! s:setCount(counts, item, buf) abort
    let type = toupper(a:item.type)
    if len(type) && (!a:buf || a:item.bufnr ==# a:buf)
        let a:counts[type] = get(a:counts, type, 0) + 1
    endif
endfunction

function! neomake#statusline#ResetCounts() abort
    let s:qflist_counts = {}
    let s:loclist_counts = {}
endfunction
call neomake#statusline#ResetCounts()

function! neomake#statusline#AddLoclistCount(win, buf, item) abort
    let s:loclist_counts[a:win] = get(s:loclist_counts, a:win, {})
    let s:loclist_counts[a:win][a:buf] = get(s:loclist_counts[a:win], a:buf, {})
    call s:setCount(s:loclist_counts[a:win][a:buf], a:item, a:buf)
endfunction

function! neomake#statusline#AddQflistCount(item) abort
    call s:setCount(s:qflist_counts, a:item, 0)
endfunction

function! neomake#statusline#LoclistCounts() abort
    let win = winnr()
    let buf = bufnr('%')
    let s:loclist_counts[win] = get(s:loclist_counts, win, {})
    return get(s:loclist_counts[win], buf, {})
endfunction

function! neomake#statusline#QflistCounts() abort
    return s:qflist_counts
endfunction

function! s:showErrWarning(counts, prefix)
    let w = get(a:counts, 'W', 0)
    let e = get(a:counts, 'E', 0)
    if w || e
        let result = a:prefix
        if e
            let result .= 'E:'.e
        endif
        if w
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
