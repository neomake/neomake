" vim: ts=4 sw=4 et

let s:nvim_api = 0

let s:highlights = {'file': {}, 'project': {}}
let s:highlight_types = {
    \ 'E': 'NeomakeError',
    \ 'W': 'NeomakeWarning',
    \ 'I': 'NeomakeInfo',
    \ 'M': 'NeomakeMessage'
    \ }

if exists('*nvim_buf_add_highlight')
    let s:nvim_api = 1
endif

" Used in tests.
function! neomake#highlights#_get() abort
    return s:highlights
endfunction

function! s:InitBufHighlights(type, buf) abort
    if s:nvim_api
        if !bufexists(a:buf)
            " The buffer might be wiped by now: prevent 'Invalid buffer id'.
            return
        endif
        if has_key(s:highlights[a:type], a:buf)
            call nvim_buf_clear_highlight(a:buf, s:highlights[a:type][a:buf], 0, -1)
        else
            let s:highlights[a:type][a:buf] = nvim_buf_add_highlight(a:buf, 0, '', 0, 0, -1)
        endif
    else
        let s:highlights[a:type][a:buf] = {
            \ 'NeomakeError': [],
            \ 'NeomakeWarning': [],
            \ 'NeomakeInfo': [],
            \ 'NeomakeMessage': []
            \ }
    endif
endfunction

function! neomake#highlights#ResetFile(buf) abort
    call s:InitBufHighlights('file', a:buf)
    call neomake#highlights#ShowHighlights()
endfunction

function! neomake#highlights#ResetProject(buf) abort
    call s:InitBufHighlights('project', a:buf)
    call neomake#highlights#ShowHighlights()
endfunction

function! neomake#highlights#AddHighlight(entry, type) abort
    if !has_key(s:highlights[a:type], a:entry.bufnr)
        call s:InitBufHighlights(a:type, a:entry.bufnr)
    endif
    let l:hi = get(s:highlight_types, toupper(a:entry.type), 'NeomakeError')
    if get(g:, 'neomake_highlight_lines', 0)
        if s:nvim_api
            call nvim_buf_add_highlight(a:entry.bufnr, s:highlights[a:type][a:entry.bufnr], l:hi, a:entry.lnum - 1, 0, -1)
        else
            call add(s:highlights[a:type][a:entry.bufnr][l:hi], a:entry.lnum)
        endif
    elseif a:entry.col > 0
        let l:length = get(a:entry, 'length', 1)
        if s:nvim_api
            call nvim_buf_add_highlight(a:entry.bufnr, s:highlights[a:type][a:entry.bufnr], l:hi, a:entry.lnum - 1, a:entry.col - 1, a:entry.col + l:length - 1)
        else
            call add(s:highlights[a:type][a:entry.bufnr][l:hi], [a:entry.lnum, a:entry.col, l:length])
        endif
    endif
endfunction

function! neomake#highlights#ShowHighlights() abort
    if s:nvim_api
        return
    endif
    call s:ResetHighlights()
    let l:buf = bufnr('%')
    for l:type in ['file', 'project']
        for l:hi in keys(get(s:highlights[l:type], l:buf, {}))
            if exists('*matchaddpos')
                call add(w:current_highlights, matchaddpos(l:hi, s:highlights[l:type][l:buf][l:hi]))
            else
                for l:loc in s:highlights[l:type][l:buf][l:hi]
                    if len(l:loc) == 1
                        call add(w:current_highlights, matchadd(l:hi, '\%' . l:loc[0] . 'l'))
                    else
                        call add(w:current_highlights, matchadd(l:hi, '\%' . l:loc[0] . 'l\%' . l:loc[1] . 'c.\{' . l:loc[2] . '}'))
                    endif
                endfor
            endif
        endfor
    endfor
endfunction

function! neomake#highlights#DefineHighlights() abort
    for [group, fg_from] in items({
                \ 'NeomakeError': ['Error', 'bg'],
                \ 'NeomakeWarning': ['Todo', 'fg'],
                \ 'NeomakeInfo': ['Question', 'fg'],
                \ 'NeomakeMessage': ['ModeMsg', 'fg']
                \ })
        let [fg_group, fg_attr] = fg_from
        let ctermfg = neomake#utils#GetHighlight(fg_group, fg_attr)
        let guisp = neomake#utils#GetHighlight(fg_group, fg_attr.'#')
        exe 'hi '.group.'Default ctermfg='.ctermfg.' guisp='.guisp.' cterm=underline gui=undercurl'
        if neomake#signs#HlexistsAndIsNotCleared(group)
            continue
        endif
        exe 'hi link '.group.' '.group.'Default'
    endfor
endfunction
call neomake#highlights#DefineHighlights()

function! s:ResetHighlights() abort
    if s:nvim_api
        return
    endif
    if exists('w:current_highlights')
        for l:highlight in w:current_highlights
            call matchdelete(l:highlight)
        endfor
    endif
    let w:current_highlights = []
endfunction
