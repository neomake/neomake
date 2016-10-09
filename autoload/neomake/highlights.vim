" vim: ts=4 sw=4 et

let s:highlights = {'file': {}, 'project': {}}
let s:highlight_types = {
    \ 'E': 'NeomakeError',
    \ 'W': 'NeomakeWarning',
    \ 'I': 'NeomakeInformational',
    \ 'M': 'NeomakeMessage'
    \ }

function! s:InitBufHighlights(type, buf) abort
    let s:highlights[a:type][a:buf] = {
        \ 'NeomakeError': [],
        \ 'NeomakeWarning': [],
        \ 'NeomakeInformational': [],
        \ 'NeomakeMessage': []
        \ }
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
            let l:loc = a:entry.lnum
        else
            let l:loc = [a:entry.lnum, a:entry.col, get(a:entry, 'length', 1)]
        endif
        call add(s:highlights[a:type][a:entry.bufnr][l:hi], l:loc)
    endif
endfunction

function! neomake#highlights#ShowHighlights() abort
    call s:ResetHighlights()
    let l:buf = bufnr('%')
    for l:type in ['file', 'project']
        for l:hi in keys(get(s:highlights[l:type], l:buf, {}))
            call add(w:current_highlights, matchaddpos(l:hi, s:highlights[l:type][l:buf][l:hi]))
        endfor
    endfor
endfunction

let s:highlights_defined = 0
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
    if exists("w:current_highlights")
        for l:highlight in w:current_highlights
            call matchdelete(l:highlight)
        endfor
    endif
    let w:current_highlights = []
endfunction
