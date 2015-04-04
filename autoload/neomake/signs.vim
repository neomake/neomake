" vim: ts=4 sw=4 et

function! neomake#signs#Reset() abort
    let s:sign_queue = {}
    if exists('s:last_placed_signs')
        call neomake#signs#CleanOldSigns()
    endif
    let s:last_placed_signs = get(s:, 'placed_signs', {})
    let s:placed_signs = {}
endfunction
call neomake#signs#Reset()

function! neomake#signs#GetSigns(...) abort
    let signs = {
        \ 'by_line': {},
        \ 'max_id': 0,
        \ }
    if a:0
        let opts = a:1
    else
        let opts = {}
    endif
    let place_cmd = 'sign place'
    for attr in keys(opts)
        if attr ==# 'file' || attr ==# 'buffer'
            let place_cmd .= ' '.attr.'='.opts[attr]
        endif
    endfor
    call neomake#utils#DebugMessage('executing: '.place_cmd)
    redir => signs_txt | silent exe place_cmd | redir END
    let fname_pattern = 'Signs for \(.*\):'
    for s in split(signs_txt, '\n')
        if s =~# fname_pattern
            " This should always happen first, so don't define outside loop
            let fname = substitute(s, fname_pattern, '\1', '')
        elseif s =~# 'id='
            let result = {}
            let parts = split(s, '\s\+')
            for part in parts
                let [key, val] = split(part, '=')
                let result[key] = val =~# '\d\+' ? 0 + val : val
            endfor
            let result.file = fname
            if !has_key(opts, 'name') || opts.name ==# result.name
                let signs.by_line[result.line] = get(signs.by_line, result.line, [])
                call add(signs.by_line[result.line], result)
                let signs.max_id = max([signs.max_id, result.id])
            endif
        endif
    endfor
    return signs
endfunction

function! neomake#signs#GetSignsInBuffer(bufnr) abort
    return neomake#signs#GetSigns({'buffer': a:bufnr})
endfunction

function! neomake#signs#RegisterSign(entry) abort
    let s:sign_queue[a:entry.bufnr] = get(s:sign_queue, a:entry.bufnr, {})
    let existing = get(s:sign_queue[a:entry.bufnr], a:entry.lnum, {})
    if empty(existing) || a:entry.type ==# 'E' && existing.type !=# 'E'
        let s:sign_queue[a:entry.bufnr][a:entry.lnum] = a:entry
    endif
endfunction

function! neomake#signs#PlaceSign(existing_signs, entry) abort
    let type = a:entry.type ==# 'E' ? 'neomake_err' : 'neomake_warn'

    let a:existing_signs.by_line[a:entry.lnum] = get(a:existing_signs.by_line,
                                                   \ a:entry.lnum, [])
    let s:placed_signs[a:entry.bufnr] = get(s:placed_signs, a:entry.bufnr, {})
    let new_sign = 0
    if !has_key(s:placed_signs[a:entry.bufnr], a:entry.lnum)
        let sign_id = a:existing_signs.max_id + 1
        let a:existing_signs.max_id = sign_id
        let cmd = 'sign place '.sign_id.' line='.a:entry.lnum.
                                      \ ' name='.type.
                                      \ ' buffer='.a:entry.bufnr
        let s:placed_signs[a:entry.bufnr][a:entry.lnum] = sign_id
        let new_sign = 1
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

    if new_sign
        " Replace all existing signs for this line, so that ours appear on top
        for existing in get(a:existing_signs.by_line, a:entry.lnum, [])
            if existing.name !~# 'neomake_'
                exe 'sign unplace '.existing.id.' buffer='.a:entry.bufnr
                exe 'sign place '.existing.id.' line='.existing.line.
                                            \ ' name='.existing.name.
                                            \ ' buffer='.a:entry.bufnr
            endif
        endfor
    endif
endfunction

function! neomake#signs#CleanOldSigns() abort
    call neomake#utils#DebugObject('Cleaning old signs:', s:last_placed_signs)
    for buf in keys(s:last_placed_signs)
        for ln in keys(s:last_placed_signs[buf])
            let cmd = 'sign unplace '.s:last_placed_signs[buf][ln]
            call neomake#utils#DebugMessage('Unplacing sign: '.cmd)
            exe cmd
        endfor
    endfor
    let s:last_placed_signs = {}
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
            if !exists('l:signs')
                let l:signs = neomake#signs#GetSignsInBuffer(buf)
            endif
            call neomake#signs#PlaceSign(l:signs, s:sign_queue[buf][ln])
            unlet s:sign_queue[buf][ln]
        endif
    endfor
    if empty(s:sign_queue[buf])
        unlet s:sign_queue[buf]
    endif
endfunction

" This command intentionally ends with a space
exe 'sign define neomake_invisible text=\ '

function! neomake#signs#RedefineSign(name, opts)
    let signs = neomake#signs#GetSigns({'name': a:name})
    for lnum in keys(signs.by_line)
        for sign in signs.by_line[lnum]
            exe 'sign place '.sign.id.' name=neomake_invisible file='.sign.file
        endfor
    endfor

    let sign_define = 'sign define '.a:name
    for attr in keys(a:opts)
        let sign_define .= ' '.attr.'='.a:opts[attr]
    endfor
    exe sign_define

    for lnum in keys(signs.by_line)
        for sign in signs.by_line[lnum]
            exe 'sign place '.sign.id.' name='.a:name.' file='.sign.file
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
