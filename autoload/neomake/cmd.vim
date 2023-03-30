scriptencoding utf8

let s:last_completion = []
function! neomake#cmd#complete_makers(ArgLead, CmdLine, ...) abort
    if a:CmdLine !~# '\s'
        " Just 'Neomake!' without following space.
        return [' ']
    endif

    " Filter only by name before non-breaking space.
    let filter_name = split(a:ArgLead, ' ', 1)[0]

    let file_mode = a:CmdLine =~# '\v^(Neomake|NeomakeFile)\s'

    let compl_info = [bufnr('%'), &filetype, a:CmdLine]
    if empty(&filetype)
        let maker_names = neomake#GetProjectMakers()
    else
        let maker_names = neomake#GetMakers(&filetype)

        " Prefer (only) makers for the current filetype.
        if file_mode
            if !empty(filter_name)
                call filter(maker_names, 'v:val[:len(filter_name)-1] ==# filter_name')
            endif
            if empty(maker_names) || s:last_completion == compl_info
                call extend(maker_names, neomake#GetProjectMakers())
            endif
        else
            call extend(maker_names, neomake#GetProjectMakers())
        endif
    endif

    " Only display executable makers.
    let makers = []
    for maker_name in maker_names
        try
            let maker = neomake#GetMaker(maker_name)
        catch /^Neomake: /
            let error = substitute(v:exception, '^Neomake: ', '', '').'.'
            call neomake#log#debug(printf('Could not get maker %s: %s',
                  \ maker_name, error))
            continue
        endtry
        if type(get(maker, 'exe', 0)) != type('') || executable(maker.exe)
            let makers += [[maker_name, maker]]
        endif
    endfor

    " Append maker.name if it differs, uses non-breaking-space.
    let r = []
    for [maker_name, maker] in makers
        if maker.name !=# maker_name
                    \ && (empty(a:ArgLead) || stridx(maker_name, a:ArgLead) != 0)
            let r += [printf('%s (%s)', maker_name, maker.name)]
        else
            let r += [maker_name]
        endif
    endfor

    let s:last_completion = compl_info
    if !empty(filter_name)
        call filter(r, 'v:val[:len(filter_name)-1] ==# filter_name')
    endif
    return r
endfunction

function! neomake#cmd#complete_jobs(...) abort
    return join(map(neomake#GetJobs(), "v:val.id.': '.v:val.maker.name"), "\n")
endfunction

function! s:is_neomake_list(list) abort
    if empty(a:list)
        return 0
    endif
    return a:list[0].text =~# ' nmcfg:{.\{-}}$'
endfunction

function! neomake#cmd#clean(file_mode) abort
    let buf = bufnr('%')
    call neomake#_clean_errors({
          \ 'file_mode': a:file_mode,
          \ 'bufnr': buf,
          \ })
    if a:file_mode
        if s:is_neomake_list(getloclist(0))
            call setloclist(0, [], 'r')
            lclose
        endif
        call neomake#signs#ResetFile(buf)
        call neomake#statusline#ResetCountsForBuf(buf)
    else
        if s:is_neomake_list(getqflist())
            call setqflist([], 'r')
            cclose
        endif
        call neomake#signs#ResetProject()
        call neomake#statusline#ResetCountsForProject()
    endif
    call neomake#EchoCurrentError(1)
    call neomake#virtualtext#handle_current_error()
endfunction

" Enable/disable/toggle commands.  {{{
function! s:handle_disabled_status(scope, disabled) abort
    if a:scope is# g:
        if a:disabled
            if exists('#neomake')
                autocmd! neomake
                augroup! neomake
            endif
            call neomake#configure#disable_automake()
            call neomake#virtualtext#handle_current_error()
        else
            call neomake#setup#setup_autocmds()
        endif
    elseif a:scope is# t:
        let buffers = neomake#compat#uniq(sort(tabpagebuflist()))
        if a:disabled
            for b in buffers
                call neomake#configure#disable_automake_for_buffer(b)
            endfor
        else
            for b in buffers
                call neomake#configure#enable_automake_for_buffer(b)
            endfor
        endif
    elseif a:scope is# b:
        let bufnr = bufnr('%')
        if a:disabled
            call neomake#configure#disable_automake_for_buffer(bufnr)
        else
            call neomake#configure#enable_automake_for_buffer(bufnr)
        endif
    endif
    call neomake#cmd#display_status()
    call neomake#configure#automake()
    call neomake#statusline#clear_cache()
endfunction

function! neomake#cmd#disable(scope) abort
    let old = get(get(a:scope, 'neomake', {}), 'disabled', -1)
    if old ==# 1
        return
    endif
    call neomake#config#set_dict(a:scope, 'neomake.disabled', 1)
    call s:handle_disabled_status(a:scope, 1)
endfunction

function! neomake#cmd#enable(scope) abort
    let old = get(get(a:scope, 'neomake', {}), 'disabled', -1)
    if old ==# 0
        return
    endif
    call neomake#config#set_dict(a:scope, 'neomake.disabled', 0)
    call s:handle_disabled_status(a:scope, 0)
endfunction

function! neomake#cmd#toggle(scope) abort
    let new = !get(get(a:scope, 'neomake', {}), 'disabled', 0)
    if new
        call neomake#config#set_dict(a:scope, 'neomake.disabled', 1)
        call s:handle_disabled_status(a:scope, 1)
    else
        call neomake#config#unset_dict(a:scope, 'neomake.disabled')
        call s:handle_disabled_status(a:scope, 0)
    endif
endfunction

function! neomake#cmd#display_status() abort
    let [disabled, source] = neomake#config#get_with_source('disabled', 0)
    let msg = 'Neomake is ' . (disabled ? 'disabled' : 'enabled')
    if source !=# 'default'
        let msg .= ' ('.source.')'
    endif

    " Add information from different scopes (if explicitly configured there).
    for [scope_name, scope] in [['buffer', b:], ['tab', t:], ['global', g:]]
        if scope_name ==# source
            continue
        endif
        let disabled = get(get(scope, 'neomake', {}), 'disabled', -1)
        if disabled != -1
            let msg .= printf(' [%s: %s]', scope_name, disabled ? 'disabled' : 'enabled')
        endif
    endfor
    let msg .= '.'

    " Information about focused makers.
    let focused = neomake#config#get_with_source('_saved_for_focus')
    if focused[1] !=# 'default'
        " NOTE: only looks at new-style config.
        let effective = neomake#config#get_with_source('enabled_makers')

        if focused[0][-1][1] ==# effective[0]
            let msg .= printf(' Focused %s for %s.', join(effective[0], ', '), focused[1])
        else
            let msg .= printf(' Focused for %s, but effective makers are different (%s != %s).',
                        \ focused[1], join(focused[-1][1], ', '), join(effective[0], ', '))
        endif
    endif

    echom msg
    call neomake#log#debug(msg)
endfunction
" }}}

function! s:update_for_focus() abort
    call neomake#configure#automake()
    call neomake#statusline#clear_cache()
endfunction

function! s:msg(msg) abort
    echom a:msg
    call neomake#log#debug(a:msg)
endfunction

function! neomake#cmd#focus(scope, ...) abort
    let unset = g:neomake#config#undefined

    let new = a:000
    let cur = get(get(a:scope, 'neomake', {}), 'enabled_makers', unset)

    let stash = get(get(a:scope, 'neomake', {}), '_saved_for_focus', [])

    if !empty(stash)
                \ && stash[-1][1] == a:000
        call s:msg(printf('Already focused %s.', join(new, ', ')))
    else
        call add(stash, [cur, new])
        call neomake#config#set_dict(a:scope, 'neomake._saved_for_focus', stash)
        call s:msg(printf('Focusing %s.', join(new, ', ')))
        call neomake#config#set_dict(a:scope, 'neomake.enabled_makers', a:000)
        call s:update_for_focus()
    endif
endfunction

function! neomake#cmd#unfocus(bang, scope, ...) abort
    let unset = g:neomake#config#undefined

    let stash = get(get(a:scope, 'neomake', {}), '_saved_for_focus', unset)
    if stash is unset
        call neomake#log#error('nothing to unfocus')
        return
    endif

    if a:bang
        " Back to orig/first.
        let prev = stash[0][0]
        let stash = []
    else
        let prev = remove(stash, -1)[0]
    endif

    " Update stash.
    if empty(stash)
        call neomake#config#unset_dict(a:scope, 'neomake._saved_for_focus')
    else
        call neomake#config#set_dict(a:scope, 'neomake._saved_for_focus', stash)
    endif

    if prev is unset
        call s:msg('Unfocus: unset enabled_makers.')
        call neomake#config#unset_dict(a:scope, 'neomake.enabled_makers')
    else
        call s:msg(printf('Unfocus: set enabled_makers back to %s.', join(prev, ', ')))
        call neomake#config#set_dict(a:scope, 'neomake.enabled_makers', prev)
    endif

    call s:update_for_focus()
endfunction

" vim: ts=4 sw=4 et
