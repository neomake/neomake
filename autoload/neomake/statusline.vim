let s:qflist_counts = {}
let s:loclist_counts = {}

function! s:incCount(counts, item, buf) abort
    let type = toupper(a:item.type)
    if len(type) && (!a:buf || a:item.bufnr ==# a:buf)
        let a:counts[type] = get(a:counts, type, 0) + 1
        return 1
    endif
    return 0
endfunction

function! neomake#statusline#ResetCountsForBuf(...) abort
    let bufnr = a:0 ? a:1 : bufnr('%')
    let r = (get(s:loclist_counts, bufnr, {}) != {})
    let s:loclist_counts[bufnr] = {}
    if r
        call neomake#utils#hook('NeomakeCountsChanged', {
                    \ 'file_mode': 1,
                    \ 'bufnr': bufnr})
    endif
    return r
endfunction

function! neomake#statusline#ResetCountsForProject(...) abort
    let r = s:qflist_counts != {}
    let s:qflist_counts = {}
    if r
        call neomake#utils#hook('NeomakeCountsChanged', {
                    \ 'file_mode': 0,
                    \ 'bufnr': bufnr('%')})
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
