" vim: ts=4 sw=4 et

function! neomake#signs#ResetAllBuffers() abort
    let s:sign_queue = {}
    let s:placed_signs = get(s:, 'placed_signs', {})
    if exists('s:last_placed_signs')
        for bufnr in keys(s:last_placed_signs)
            call neomake#signs#Reset(bufnr)
        endfor
    endif
    let s:last_placed_signs = {}
    let s:neomake_sign_id = {}
endfunction
call neomake#signs#ResetAllBuffers()

function! neomake#signs#Reset(bufnr) abort
    let s:sign_queue[a:bufnr] = {}
    if exists('s:last_placed_signs')
        call neomake#signs#CleanOldSigns(a:bufnr)
    endif
    let s:placed_signs = get(s:, 'placed_signs', {})
    let s:last_placed_signs[a:bufnr] = get(s:placed_signs, a:bufnr, {})
    let s:placed_signs[a:bufnr] = {}
    if has_key(s:neomake_sign_id, a:bufnr)
        unlet s:neomake_sign_id[a:bufnr]
    endif
endfunction

function! neomake#signs#RegisterSign(entry) abort
    let s:sign_queue[a:entry.bufnr] = get(s:sign_queue, a:entry.bufnr, {})
    let existing = get(s:sign_queue[a:entry.bufnr], a:entry.lnum, {})
    if empty(existing) || a:entry.type ==# 'E' && existing.type !=# 'E'
        let s:sign_queue[a:entry.bufnr][a:entry.lnum] = a:entry
    endif
endfunction

function! neomake#signs#PlaceSign(entry) abort
    let type = a:entry.type ==# 'E' ? 'neomake_err' : 'neomake_warn'

    let s:placed_signs[a:entry.bufnr] = get(s:placed_signs, a:entry.bufnr, {})
    if !has_key(s:placed_signs[a:entry.bufnr], a:entry.lnum)
        let sign_id = get(s:neomake_sign_id, a:entry.bufnr, 5000)
        let s:neomake_sign_id[a:entry.bufnr] = sign_id + 1
        let cmd = 'sign place '.sign_id.' line='.a:entry.lnum.
                                      \ ' name='.type.
                                      \ ' buffer='.a:entry.bufnr
        let s:placed_signs[a:entry.bufnr][a:entry.lnum] = sign_id
    elseif type ==# 'neomake_err'
        " Upgrade this sign to an error
        let sign_id = s:placed_signs[a:entry.bufnr][a:entry.lnum]
        let cmd =  'sign place '.sign_id.' name='.type.' buffer='.a:entry.bufnr
    else
        let cmd = ''
    endif

    if len(cmd)
        call neomake#utils#DebugMessage('Placing sign: '.cmd)
        exe cmd
    endif
endfunction

function! neomake#signs#CleanOldSigns(bufnr) abort
    if !has_key(s:last_placed_signs, a:bufnr) || empty(s:last_placed_signs[a:bufnr])
        return
    endif
    call neomake#utils#DebugObject('Cleaning old signs in buffer '.a:bufnr.': ', s:last_placed_signs)
    for ln in keys(s:last_placed_signs[a:bufnr])
        let cmd = 'sign unplace '.s:last_placed_signs[a:bufnr][ln].' buffer='.a:bufnr
        call neomake#utils#DebugMessage('Unplacing sign: '.cmd)
        exe cmd
    endfor
    unlet s:last_placed_signs[a:bufnr]
endfunction

function! neomake#signs#PlaceVisibleSigns() abort
    let buf = bufnr('%')
    if !has_key(s:sign_queue, buf)
        return
    endif
    let topline = line('w0')
    let botline = line('w$')
    for ln in range(topline, botline)
        if has_key(s:sign_queue[buf], ln)
            call neomake#signs#PlaceSign(s:sign_queue[buf][ln])
            unlet s:sign_queue[buf][ln]
        endif
    endfor
    if empty(s:sign_queue[buf])
        unlet s:sign_queue[buf]
    endif
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

let s:signs_defined = 0
function! neomake#signs#DefineSigns()
    if !s:signs_defined
        let s:signs_defined = 1
        call neomake#signs#RedefineErrorSign()
        call neomake#signs#RedefineWarningSign()
    endif
endfunction
