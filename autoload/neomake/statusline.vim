
function! s:getListCounts(list, buf) abort
    let counts = {}
    for err in a:list
        if len(err.type) && (!a:buf || err.bufnr ==# a:buf)
            let counts[err.type] = get(counts, err.type, 0) + 1
        endif
    endfor
    return counts
endfunction

function! neomake#statusline#LoclistCounts() abort
    return s:getListCounts(getloclist(winnr()), bufnr('%'))
endfunction

function! neomake#statusline#QflistCounts() abort
    return s:getListCounts(getqflist(), 0)
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
