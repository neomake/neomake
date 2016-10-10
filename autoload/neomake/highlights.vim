" vim: ts=4 sw=4 et

let s:nvim_api = 0
let s:highlights_defined = 0

let s:highlights = {'file': {}, 'project': {}}
let s:highlight_types = {
    \ 'E': 'NeomakeError',
    \ 'W': 'NeomakeWarning',
    \ 'I': 'NeomakeInformational',
    \ 'M': 'NeomakeMessage'
    \ }

if exists('*nvim_buf_add_highlight')
    let s:nvim_api = 1
    function! s:NewHighlightSource(buf) abort
        return nvim_buf_add_highlight(a:buf, 0, '', 0, 0, -1)
    endfunction
endif

function! s:InitBufHighlights(type, buf) abort
    if s:nvim_api
        if has_key(s:highlights[a:type], a:buf)
            call nvim_buf_clear_highlight(a:buf, s:highlights[a:type][a:buf], 0, -1)
        endif
        let s:highlights[a:type][a:buf] = s:NewHighlightSource(a:buf)
    else
        let s:highlights[a:type][a:buf] = {
            \ 'NeomakeError': [],
            \ 'NeomakeWarning': [],
            \ 'NeomakeInformational': [],
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
    if a:entry.col
        let l:hi = get(s:highlight_types, toupper(a:entry.type), 'NeomakeError')
        if get(g:, 'neomake_highlight_line', 0)
            if s:nvim_api
                call nvim_buf_add_highlight(a:entry.bufnr, s:highlights[a:type][a:entry.bufnr], l:hi, a:entry.lnum - 1, 0, -1)
            else
                call add(s:highlights[a:type][a:entry.bufnr][l:hi], a:entry.lnum)
            endif
        else
            let l:length = get(a:entry, 'length', 1)
            if s:nvim_api
                call nvim_buf_add_highlight(a:entry.bufnr, s:highlights[a:type][a:entry.bufnr], l:hi, a:entry.lnum - 1, a:entry.col - 1, a:entry.col + l:length - 1)
            else
                call add(s:highlights[a:type][a:entry.bufnr][l:hi], [a:entry.lnum, a:entry.col, l:length])
            endif
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
    if !s:highlights_defined
        let s:highlights_defined = 1
        for l:type in ['Error', 'Warning', 'Informational', 'Message']
            exe 'hi link Neomake' . l:type . ' ' .
                \ get(g:, 'neomake_' . tolower(l:type) . '_highlight', l:type)
        endfor
    endif
endfunction

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
