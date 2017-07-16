" vim: ts=4 sw=4 et

scriptencoding utf-8

if !has('signs')
    call neomake#utils#ErrorMessage('Trying to load signs.vim, without +signs.')
    finish
endif

let s:last_placed_signs = {
    \ 'project': {},
    \ 'file': {}
    \ }
let s:placed_signs = {
    \ 'project': {},
    \ 'file': {}
    \ }
let s:neomake_sign_id = {
    \ 'project': {},
    \ 'file': {}
    \ }

let s:base_sign_id = 5000

let s:signs_for_entries = {}

exe 'sign define neomake_invisible'

" Reset signs placed by a :Neomake! call
" (resetting signs means the current signs will be deleted on the next call to ResetProject)
function! neomake#signs#ResetProject() abort
    for buf in keys(s:placed_signs.project)
        call neomake#signs#CleanOldSigns(buf, 'project')
        call neomake#signs#Reset(buf, 'project')
    endfor
    let s:neomake_sign_id.project = {}
endfunction

" Reset signs placed by a :Neomake call in a buffer
function! neomake#signs#ResetFile(bufnr) abort
    call neomake#signs#CleanOldSigns(a:bufnr, 'file')
    call neomake#signs#Reset(a:bufnr, 'file')
endfunction

function! neomake#signs#Reset(bufnr, type) abort
    if has_key(s:placed_signs[a:type], a:bufnr)
        let s:last_placed_signs[a:type][a:bufnr] = s:placed_signs[a:type][a:bufnr]
        unlet s:placed_signs[a:type][a:bufnr]
    endif
endfunction

let s:sign_order = {'neomake_file_err': 0, 'neomake_file_warn': 1,
                 \  'neomake_file_info': 2, 'neomake_file_msg': 3,
                 \  'neomake_project_err': 4, 'neomake_project_warn': 5,
                 \  'neomake_project_info': 6, 'neomake_project_msg': 7}

" Get the defined signs for a:bufnr.
" It returns a dictionary with line numbers as keys.
" If there are multiple entries for a line only the first (visible) entry is
" returned.
function! neomake#signs#by_lnum(bufnr) abort
    if !bufexists(a:bufnr + 0)
        return {}
    endif
    let signs_output = split(neomake#utils#redir('sign place buffer='.a:bufnr), '\n')

    " Via ALE.
    " Matches output like :
    " line=4  id=1  name=neomake_err
    " строка=1  id=1000001  имя=neomake_err
    " 行=1  識別子=1000001  名前=neomake_err
    " línea=12 id=1000001 nombre=neomake_err
    " riga=1 id=1000001, nome=neomake_err
    let pattern = '^.*=\(\d\+\)\s\+.*=\(\d\+\)\,\?\s\+.*=\(neomake_\w\+\)'

    let d = {}
    for line in signs_output
        let m = matchlist(line, pattern)
        if !empty(m) && !has_key(d, m[1])
            " let l[m[2]] = l[m[1]] + 0
            let d[m[1]] = [m[2] + 0, m[3]]
        endif
    endfor
    return d
endfunction

function! neomake#signs#PlaceSigns(bufnr, entries, type) abort
    let entries_by_bufnr = {}
    let bufnr = a:bufnr

    let entries_by_bufnr[bufnr] = a:entries
    " let entries_by_bufnr = {}
    " for entry in a:entries
    "     let entries_by_bufnr[entry.bufnr] = entry
    " endfor

    for [bufnr, entries] in items(entries_by_bufnr)
        " Query the list of currently placed signs.
        " This allows to cope with movements, e.g. when lines where added.
        let placed_signs = neomake#signs#by_lnum(bufnr)

        let entries_by_linenr = {}
        for entry in entries
            if entry.lnum == 0
                continue
            endif
            if entry.type ==? 'W'
                let sign_type = 'warn'
            elseif entry.type ==? 'I'
                let sign_type = 'info'
            elseif entry.type ==? 'M'
                let sign_type = 'msg'
            else
                let sign_type = 'err'
            endif
            let sign_type = 'neomake_'.a:type.'_'.sign_type

            if ! exists('entries_by_linenr[entry.lnum]')
                        \ || s:sign_order[entries_by_linenr[entry.lnum][1]]
                        \    > s:sign_order[sign_type]
                let entries_by_linenr[entry.lnum] = [entry, sign_type]
            endif
        endfor

        let place_new = []
        let kept_signs = []
        for [lnum, entry_info] in items(entries_by_linenr)
            let [entry, sign_type] = entry_info

            " Keep this sign from being cleaned.
            if exists('s:last_placed_signs[a:type][bufnr][lnum]')
                unlet s:last_placed_signs[a:type][bufnr][lnum]
            endif

            let existing_sign = get(placed_signs, entry.lnum, [])
            if empty(existing_sign) || existing_sign[1] !~# '^neomake_'.a:type.'_'
                call add(place_new, [lnum, sign_type])
                continue
            endif
            if existing_sign[1] == sign_type
                call neomake#utils#DebugMessage(printf(
                            \ 'Reusing sign: id=%d, type=%s, lnum=%d.',
                            \ existing_sign[0], existing_sign[1], lnum))
            else
                let cmd = 'sign place '.existing_sign[0].' name='.sign_type.' buffer='.bufnr
                call neomake#utils#DebugMessage('Upgrading sign for lnum='.lnum.': '.cmd.'.')
                exe cmd
            endif
            call add(kept_signs, existing_sign[0])
        endfor

        for [lnum, sign_type] in place_new
            if !exists('next_sign_id')
                if !empty(placed_signs)
                    let next_sign_id = max(map(values(copy(placed_signs)), 'v:val[0]')) + 1
                else
                    let next_sign_id = s:base_sign_id
                endif
            else
                let next_sign_id += 1
            endif
            let cmd = 'sign place '.next_sign_id.' line='.lnum.
                        \ ' name='.sign_type.
                        \ ' buffer='.bufnr
            call neomake#utils#DebugMessage('Placing sign: '.cmd.'.')
            let placed_signs[lnum] = [next_sign_id, sign_type]
            exe cmd
        endfor
        let s:placed_signs[a:type][bufnr] = placed_signs
    endfor
endfunction

function! neomake#signs#CleanAllOldSigns(type) abort
    call neomake#utils#DebugObject('Removing signs', s:last_placed_signs)
    for buf in keys(s:last_placed_signs[a:type])
        call neomake#signs#CleanOldSigns(buf, a:type)
    endfor
endfunction

" type may be either 'file' or 'project'
function! neomake#signs#CleanOldSigns(bufnr, type) abort
    if !has_key(s:last_placed_signs[a:type], a:bufnr)
        return
    endif
    let placed_signs = s:last_placed_signs[a:type][a:bufnr]
    unlet s:last_placed_signs[a:type][a:bufnr]
    call neomake#utils#DebugObject('Cleaning old signs in buffer '.a:bufnr, placed_signs)
    for sign_info in values(placed_signs)
        let sign_id = sign_info[0]
        let cmd = 'sign unplace '.sign_id.' buffer='.a:bufnr
        call neomake#utils#DebugMessage('Unplacing sign: '.cmd.'.')
        exe cmd
    endfor
endfunction

function! neomake#signs#RedefineSign(name, opts) abort
    let sign_define = 'sign define '.a:name
    for attr in keys(a:opts)
        let sign_define .= ' '.attr.'='.a:opts[attr]
    endfor
    exe sign_define

    for type in keys(s:placed_signs)
        for buf in keys(s:placed_signs[type])
            for ln in keys(s:placed_signs[type][buf])
                let [sign_id, sign_type] = s:placed_signs[type][buf][ln]
                if sign_type == a:name
                    exe 'sign place '.sign_id.' name='.a:name.' buffer='.buf
                endif
            endfor
        endfor
    endfor
endfunction

function! neomake#signs#RedefineErrorSign(...) abort
    let default_opts = {'text': '✖', 'texthl': 'NeomakeErrorSign'}
    let opts = {}
    if a:0
        call extend(opts, a:1)
    elseif exists('g:neomake_error_sign')
        call extend(opts, g:neomake_error_sign)
    endif
    call extend(opts, default_opts, 'keep')
    call neomake#signs#RedefineSign('neomake_file_err', opts)
    call neomake#signs#RedefineSign('neomake_project_err', opts)
endfunction

function! neomake#signs#RedefineWarningSign(...) abort
    let default_opts = {'text': '⚠', 'texthl': 'NeomakeWarningSign'}
    let opts = {}
    if a:0
        call extend(opts, a:1)
    elseif exists('g:neomake_warning_sign')
        call extend(opts, g:neomake_warning_sign)
    endif
    call extend(opts, default_opts, 'keep')
    call neomake#signs#RedefineSign('neomake_file_warn', opts)
    call neomake#signs#RedefineSign('neomake_project_warn', opts)
endfunction

function! neomake#signs#RedefineMessageSign(...) abort
    let default_opts = {'text': '➤', 'texthl': 'NeomakeMessageSign'}
    let opts = {}
    if a:0
        call extend(opts, a:1)
    elseif exists('g:neomake_message_sign')
        call extend(opts, g:neomake_message_sign)
    endif
    call extend(opts, default_opts, 'keep')
    call neomake#signs#RedefineSign('neomake_file_msg', opts)
    call neomake#signs#RedefineSign('neomake_project_msg', opts)
endfunction

function! neomake#signs#RedefineInfoSign(...) abort
    let default_opts = {'text': 'ℹ', 'texthl': 'NeomakeInfoSign'}
    let opts = {}
    if a:0
        call extend(opts, a:1)
    elseif exists('g:neomake_info_sign')
        call extend(opts, g:neomake_info_sign)
    endif
    call extend(opts, default_opts, 'keep')
    call neomake#signs#RedefineSign('neomake_file_info', opts)
    call neomake#signs#RedefineSign('neomake_project_info', opts)
endfunction

function! neomake#signs#HlexistsAndIsNotCleared(group) abort
    if !hlexists(a:group)
        return 0
    endif
    return neomake#utils#redir('hi '.a:group) !~# 'cleared'
endfunction

function! neomake#signs#DefineHighlights() abort
    let ctermbg = neomake#utils#GetHighlight('SignColumn', 'bg')
    let guibg = neomake#utils#GetHighlight('SignColumn', 'bg#')
    let bg = 'ctermbg='.ctermbg.' guibg='.guibg

    for [group, fg_from] in items({
                \ 'NeomakeErrorSign': ['Error', 'bg'],
                \ 'NeomakeWarningSign': ['Todo', 'fg'],
                \ 'NeomakeInfoSign': ['Question', 'fg'],
                \ 'NeomakeMessageSign': ['ModeMsg', 'fg']
                \ })
        let [fg_group, fg_attr] = fg_from
        let ctermfg = neomake#utils#GetHighlight(fg_group, fg_attr)
        let guifg = neomake#utils#GetHighlight(fg_group, fg_attr.'#')
        " Ensure that we're not using SignColumn bg as fg (as with gotham
        " colorscheme, issue https://github.com/neomake/neomake/pull/659).
        if ctermfg == ctermbg && guifg == guibg
            let fg_attr = neomake#utils#ReverseSynIDattr(fg_attr)
            let ctermfg = neomake#utils#GetHighlight(fg_group, fg_attr)
            let guifg = neomake#utils#GetHighlight(fg_group, fg_attr.'#')
        endif
        exe 'hi '.group.'Default ctermfg='.ctermfg.' guifg='.guifg.' '.bg
        if !neomake#signs#HlexistsAndIsNotCleared(group)
            exe 'hi link '.group.' '.group.'Default'
        endif
    endfor
endfunction

function! neomake#signs#DefineSigns() abort
    call neomake#signs#RedefineErrorSign()
    call neomake#signs#RedefineWarningSign()
    call neomake#signs#RedefineInfoSign()
    call neomake#signs#RedefineMessageSign()
endfunction

function! s:wipe_signs(bufnr) abort
    for type in ['file', 'project']
        if has_key(s:placed_signs[type], a:bufnr)
            unlet s:placed_signs[type][a:bufnr]
        endif
        if has_key(s:last_placed_signs[type], a:bufnr)
            unlet s:last_placed_signs[type][a:bufnr]
        endif
    endfor
endfunction
augroup neomake_signs
    au!
    autocmd BufWipeout * call s:wipe_signs(expand('<abuf>'))
augroup END

call neomake#signs#DefineSigns()
call neomake#signs#DefineHighlights()
