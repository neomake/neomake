scriptencoding utf8

let s:highlight_types = {
    \ 'E': 'NeomakeVirtualtextError',
    \ 'W': 'NeomakeVirtualtextWarning',
    \ 'I': 'NeomakeVirtualtextInfo',
    \ 'M': 'NeomakeVirtualtextMessage'
    \ }

function! neomake#virtualtext#show(...) abort
    let list = neomake#list#get()
    if empty(list)
        echom 'Neomake: no annotations to show (no list)'
        return
    endif

    let filter = a:0 ? a:1 : ''
    if empty(filter)
        let entries = list.entries
    else
        let entries = map(copy(list.entries), filter)
    endif

    if empty(entries)
        echom 'Neomake: no annotations to show (no errors)'
        return
    endif

    for entry in entries
        call neomake#virtualtext#add_entry(entry)
    endfor
endfunction

function! neomake#virtualtext#add_entry(entry) abort
    let buf_info = getbufvar(a:entry.bufnr, '_neomake_info', {})
    let src_id = get(buf_info, 'virtual_text_src_id', 0)

    let hi = get(s:highlight_types, toupper(a:entry.type), 'NeomakeVirtualtextMessage')

    let prefix = get(g:, 'neomake_annotation_prefix', '❯ ')
    let text = prefix . a:entry.text
    let used_src_id = nvim_buf_set_virtual_text(a:entry.bufnr, src_id, a:entry.lnum-1, [[text, hi]], {})

    if src_id ==# 0
        let buf_info.virtual_text_src_id = used_src_id
        call setbufvar(a:entry.bufnr, '_neomake_info', buf_info)
    endif
    return used_src_id
endfunction

function! neomake#virtualtext#show_errors() abort
    call neomake#virtualtext#show('v:val ==? "e"')
endfunction

function! neomake#virtualtext#hide() abort
    let bufnr = bufnr('%')
    let buf_info = getbufvar(bufnr, '_neomake_info', {})
    let src_id = get(buf_info, 'virtual_text_src_id', 0)
    if src_id !=# 0
        call nvim_buf_clear_highlight(bufnr, src_id, 0, -1)
    endif
endfunction

if exists('*nvim_buf_set_virtual_text')
    let s:cur_virtualtext = []
    function! neomake#virtualtext#handle_current_error() abort
        if get(g:, 'neomake_virtualtext_current_error', 1)
            if !empty(s:cur_virtualtext)
                call nvim_buf_clear_highlight(s:cur_virtualtext[0], s:cur_virtualtext[1], 0, -1)
            endif
            let entry = neomake#get_nearest_error()
            if !empty(entry)
                let s:cur_virtualtext = [bufnr('%'), neomake#virtualtext#add_entry(entry)]
            endif
        endif
    endfunction
else
    function! neomake#virtualtext#handle_current_error() abort
    endfunction
endif

function! neomake#virtualtext#DefineHighlights() abort
    for [group, link] in items({
                \ 'NeomakeVirtualtextError': 'NeomakeError',
                \ 'NeomakeVirtualtextWarning': 'NeomakeWarning',
                \ 'NeomakeVirtualtextInfo': 'NeomakeWarning',
                \ 'NeomakeVirtualtextMessage': 'NeomakeWarning'
                \ })
        if !neomake#utils#highlight_is_defined(group)
            exe 'highlight link '.group.' '.link
        endif
    endfor
endfunction

call neomake#virtualtext#DefineHighlights()

" vim: ts=4 sw=4 et
