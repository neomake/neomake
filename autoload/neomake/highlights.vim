" vim: ts=4 sw=4 et

let s:highlights = {'file': {}, 'project': {}}
let s:highlight_types = {
    \ 'E': 'NeomakeError',
    \ 'W': 'NeomakeWarning',
    \ 'I': 'NeomakeInfo',
    \ 'M': 'NeomakeMessage'
    \ }

let s:nvim_api = exists('*nvim_buf_add_highlight')

" Used in tests.
function! neomake#highlights#_get() abort
    return s:highlights
endfunction

if s:nvim_api
    function! s:InitBufHighlights(type, buf) abort
        if !bufexists(a:buf)
            " The buffer might be wiped by now: prevent 'Invalid buffer id'.
            return
        endif
        if has_key(s:highlights[a:type], a:buf)
            call nvim_buf_clear_highlight(a:buf, s:highlights[a:type][a:buf], 0, -1)
        else
            let s:highlights[a:type][a:buf] = nvim_buf_add_highlight(a:buf, 0, '', 0, 0, -1)
        endif
    endfunction

    function! neomake#highlights#ResetFile(buf) abort
        call s:InitBufHighlights('file', a:buf)
    endfunction

    function! neomake#highlights#ResetProject(buf) abort
        call s:InitBufHighlights('project', a:buf)
    endfunction
else
    function! s:InitBufHighlights(type, buf) abort
        let s:highlights[a:type][a:buf] = {
            \ 'NeomakeError': [],
            \ 'NeomakeWarning': [],
            \ 'NeomakeInfo': [],
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
endif

function! neomake#highlights#AddHighlight(entry, type) abort
    " Some makers use line 0 for file warnings (which cannot be highlighted,
    " e.g. cpplint with "no copyright" warnings).
    if a:entry.lnum == 0
        return
    endif

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

if s:nvim_api
    function! neomake#highlights#ShowHighlights() abort
    endfunction
else
    function! neomake#highlights#ShowHighlights() abort
        if exists('w:neomake_highlights')
            for l:highlight in w:neomake_highlights
                try
                    call matchdelete(l:highlight)
                catch /^Vim\%((\a\+)\)\=:E803/
                endtry
            endfor
        endif
        let w:neomake_highlights = []

        let l:buf = bufnr('%')
        for l:type in ['file', 'project']
            for [l:hi, l:locs] in items(filter(copy(get(s:highlights[l:type], l:buf, {})), '!empty(v:val)'))
                if exists('*matchaddpos')
                    call add(w:neomake_highlights, matchaddpos(l:hi, l:locs))
                else
                    for l:loc in l:locs
                        if len(l:loc) == 1
                            call add(w:neomake_highlights, matchadd(l:hi, '\%' . l:loc[0] . 'l'))
                        else
                            call add(w:neomake_highlights, matchadd(l:hi, '\%' . l:loc[0] . 'l\%' . l:loc[1] . 'c.\{' . l:loc[2] . '}'))
                        endif
                    endfor
                endif
            endfor
        endfor
    endfunction
endif

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
        if neomake#utils#highlight_is_defined(group)
            continue
        endif
        exe 'hi link '.group.' '.group.'Default'
    endfor
endfunction

function! s:wipe_highlights(bufnr) abort
    for type in ['file', 'project']
        if has_key(s:highlights[type], a:bufnr)
            unlet s:highlights[type][a:bufnr]
        endif
    endfor
endfunction
augroup neomake_highlights
    au!
    autocmd BufWipeout * call s:wipe_highlights(expand('<abuf>'))
augroup END

call neomake#highlights#DefineHighlights()
