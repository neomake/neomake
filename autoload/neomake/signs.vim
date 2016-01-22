" vim: ts=4 sw=4 et

function! s:InitSigns() abort
    let s:sign_queue = {
        \ 'project': {},
        \ 'file': {}
        \ }
    let s:last_placed_signs = {
        \ 'project': {},
        \ 'file': {}
        \ }
    let s:placed_signs = {
        \ 'project': {},
        \ 'file': {}
        \ }
    let s:sign_queue = {
        \ 'project': {},
        \ 'file': {}
        \ }
    let s:neomake_sign_id = {
        \ 'project': {},
        \ 'file': {}
        \ }
endfunction
call s:InitSigns()

" Reset signs placed by a :Neomake! call
" (resettting signs means the current signs will be deleted on the next call to ResetProject)
function! neomake#signs#ResetProject() abort
    let s:sign_queue.project = {}
    for buf in keys(s:placed_signs.project)
        call neomake#signs#CleanOldSigns(buf, 'project')
        call neomake#signs#Reset(buf, 'project')
    endfor
    let s:neomake_sign_id.project = {}
endfunction

" Reset signs placed by a :Neomake call in a buffer
function! neomake#signs#ResetFile(bufnr) abort
    let s:sign_queue.file[a:bufnr] = {}
    call neomake#signs#CleanOldSigns(a:bufnr, 'file')
    call neomake#signs#Reset(a:bufnr, 'file')
    if has_key(s:neomake_sign_id.file, a:bufnr)
        unlet s:neomake_sign_id.file[a:bufnr]
    endif
endfunction

function! neomake#signs#Reset(bufnr, type) abort
    if has_key(s:placed_signs[a:type], a:bufnr)
        let s:last_placed_signs[a:type][a:bufnr] = s:placed_signs[a:type][a:bufnr]
        unlet s:placed_signs[a:type][a:bufnr]
    endif
endfunction

" type may be either 'file' or 'project'
function! neomake#signs#RegisterSign(entry, type) abort
    let s:sign_queue[a:type][a:entry.bufnr] = get(s:sign_queue[a:type], a:entry.bufnr, {})
    let existing = get(s:sign_queue[a:type][a:entry.bufnr], a:entry.lnum, {})
    if empty(existing) || a:entry.type ==# 'E' && existing.type !=# 'E'
        let s:sign_queue[a:type][a:entry.bufnr][a:entry.lnum] = a:entry
    endif
endfunction

" type may be either 'file' or 'project'
function! neomake#signs#PlaceSign(entry, type) abort
    if a:entry.type ==? 'W'
        let sign_type = 'neomake_warn'
    elseif a:entry.type ==? 'I'
        let sign_type = 'neomake_info'
    elseif a:entry.type ==? 'M'
        let sign_type = 'neomake_msg'
    else
        let sign_type = 'neomake_err'
    endif

    let s:placed_signs[a:type][a:entry.bufnr] = get(s:placed_signs[a:type], a:entry.bufnr, {})
    if !has_key(s:placed_signs[a:type][a:entry.bufnr], a:entry.lnum)
        let default = a:type ==# 'file' ? 5000 : 7000
        let sign_id = get(s:neomake_sign_id[a:type], a:entry.bufnr, default)
        let s:neomake_sign_id[a:type][a:entry.bufnr] = sign_id + 1
        let cmd = 'sign place '.sign_id.' line='.a:entry.lnum.
                                      \ ' name='.sign_type.
                                      \ ' buffer='.a:entry.bufnr
        let s:placed_signs[a:type][a:entry.bufnr][a:entry.lnum] = sign_id
    elseif sign_type ==# 'neomake_err'
        " Upgrade this sign to an error
        let sign_id = s:placed_signs[a:type][a:entry.bufnr][a:entry.lnum]
        let cmd =  'sign place '.sign_id.' name='.sign_type.' buffer='.a:entry.bufnr
    else
        let cmd = ''
    endif

    if len(cmd)
        call neomake#utils#DebugMessage('Placing sign: '.cmd)
        exe cmd
    endif
endfunction

function! neomake#signs#CleanAllOldSigns(type) abort
    call neomake#utils#DebugObject("Removing signs", s:last_placed_signs)
    for buf in keys(s:last_placed_signs[a:type])
        call neomake#signs#CleanOldSigns(buf, a:type)
    endfor
endfunction

" type may be either 'file' or 'project'
function! neomake#signs#CleanOldSigns(bufnr, type) abort
    if !has_key(s:last_placed_signs[a:type], a:bufnr)
        return
    endif
    call neomake#utils#DebugObject('Cleaning old signs in buffer '.a:bufnr.': ', s:last_placed_signs[a:type])
    for ln in keys(s:last_placed_signs[a:type][a:bufnr])
        let cmd = 'sign unplace '.s:last_placed_signs[a:type][a:bufnr][ln].' buffer='.a:bufnr
        call neomake#utils#DebugMessage('Unplacing sign: '.cmd)
        exe cmd
    endfor
    unlet s:last_placed_signs[a:type][a:bufnr]
endfunction

function! neomake#signs#PlaceVisibleSigns() abort
    for type in ['file', 'project']
        let buf = bufnr('%')
        if !has_key(s:sign_queue[type], buf)
            continue
        endif
        let topline = line('w0')
        let botline = line('w$')
        for ln in range(topline, botline)
            if has_key(s:sign_queue[type][buf], ln)
                call neomake#signs#PlaceSign(s:sign_queue[type][buf][ln], type)
                unlet s:sign_queue[type][buf][ln]
            endif
        endfor
        if empty(s:sign_queue[type][buf])
            unlet s:sign_queue[type][buf]
        endif
    endfor
endfunction

exe 'sign define neomake_invisible'

function! neomake#signs#RedefineSign(name, opts)
    let sign_define = 'sign define '.a:name
    for attr in keys(a:opts)
        let sign_define .= ' '.attr.'='.a:opts[attr]
    endfor
    exe sign_define

    for buf in keys(s:placed_signs)
        for ln in keys(s:placed_signs[buf])
            let sign_id = s:placed_signs[buf][ln]
            exe 'sign place '.sign_id.' name=neomake_invisible buffer='.buf
            exe 'sign place '.sign_id.' name='.a:name.' buffer='.buf
        endfor
    endfor
endfunction

function! neomake#signs#RedefineErrorSign(...)
    let default_opts = {'text': '✖'}
    let opts = {}
    if a:0
        call extend(opts, a:1)
    elseif exists('g:neomake_error_sign')
        call extend(opts, g:neomake_error_sign)
    endif
    call extend(opts, default_opts, 'keep')
    call neomake#signs#RedefineSign('neomake_err', opts)
endfunction

function! neomake#signs#RedefineWarningSign(...)
    let default_opts = {'text': '⚠'}
    let opts = {}
    if a:0
        call extend(opts, a:1)
    elseif exists('g:neomake_warning_sign')
        call extend(opts, g:neomake_warning_sign)
    endif
    call extend(opts, default_opts, 'keep')
    call neomake#signs#RedefineSign('neomake_warn', opts)
endfunction

function! neomake#signs#RedefineMessageSign(...)
    let default_opts = {'text': '➤'}
    let opts = {}
    if a:0
        call extend(opts, a:1)
    elseif exists('g:neomake_message_sign')
        call extend(opts, g:neomake_message_sign)
    endif
    call extend(opts, default_opts, 'keep')
    call neomake#signs#RedefineSign('neomake_msg', opts)
endfunction

function! neomake#signs#RedefineInformationalSign(...)
    let default_opts = {'text': 'ℹ'}
    let opts = {}
    if a:0
        call extend(opts, a:1)
    elseif exists('g:neomake_informational_sign')
        call extend(opts, g:neomake_informational_sign)
    endif
    call extend(opts, default_opts, 'keep')
    call neomake#signs#RedefineSign('neomake_info', opts)
endfunction


let s:signs_defined = 0
function! neomake#signs#DefineSigns()
    if !s:signs_defined
        let s:signs_defined = 1
        call neomake#signs#RedefineErrorSign()
        call neomake#signs#RedefineWarningSign()
        call neomake#signs#RedefineInformationalSign()
        call neomake#signs#RedefineMessageSign()
    endif
endfunction
