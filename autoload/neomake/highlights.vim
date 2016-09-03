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
    call neomake#highlights#ShowHighlights(a:buf)
endfunction

function! neomake#highlights#ResetProject(buf) abort
    call s:InitBufHighlights('project', a:buf)
    call neomake#highlights#ShowHighlights(a:buf)
endfunction

function! neomake#highlights#AddHighlight(entry, type) abort
    if !has_key(s:highlights[a:type], a:entry.bufnr)
        call s:InitBufHighlights(a:type, a:entry.bufnr)
    endif
    if a:entry.col
        let l:hi = get(s:highlight_types, toupper(a:entry.type), 'NeomakeError')
        call add(s:highlights[a:type][a:entry.bufnr][l:hi], [a:entry.lnum, a:entry.col, 1])
    endif
endfunction

function! neomake#highlights#ShowHighlights(buf) abort
    call s:ResetHighlights()
    for l:type in ['file', 'project']
        for l:hi in keys(get(s:highlights[l:type], a:buf, {}))
            call matchaddpos(l:hi, s:highlights[l:type][a:buf][l:hi])
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
    for l:match in getmatches()
        if stridx(l:match['group'], 'Neomake') == 0
            call matchdelete(l:match['id'])
        endif
    endfor
endfunction
