if exists('g:loaded_neomake') || &compatible
    finish
endif
let g:loaded_neomake = 1

command! -nargs=* -bang -bar -complete=customlist,neomake#cmd#complete_makers
            \ Neomake call neomake#Make(<bang>1, [<f-args>])

" These commands are available for clarity
command! -nargs=* -bar -complete=customlist,neomake#cmd#complete_makers
            \ NeomakeProject Neomake! <args>
command! -nargs=* -bar -complete=customlist,neomake#cmd#complete_makers
            \ NeomakeFile Neomake <args>

command! -nargs=+ -bang -complete=shellcmd
            \ NeomakeSh call neomake#ShCommand(<bang>0, <q-args>)
command! NeomakeListJobs call neomake#ListJobs()
command! -bang -nargs=1 -complete=custom,neomake#cmd#complete_jobs
            \ NeomakeCancelJob call neomake#CancelJob(<q-args>, <bang>0)
command! -bang NeomakeCancelJobs call neomake#CancelJobs(<bang>0)

command! -bang -bar -nargs=? -complete=customlist,neomake#cmd#complete_makers
            \ NeomakeInfo call neomake#debug#display_info(<bang>0, <f-args>)

command! -bang -bar NeomakeClean call neomake#cmd#clean(<bang>1)

" Enable/disable/toggle commands.  {{{
function! s:handle_disabled_status(scope, disabled) abort
    if a:scope is# g:
        if a:disabled
            if exists('#neomake')
                autocmd! neomake
                augroup! neomake
            endif
            call neomake#configure#disable_automake()
        else
            call s:setup_autocmds()
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
    call s:display_status()
    call neomake#configure#automake()
    call neomake#statusline#clear_cache()
endfunction

function! s:disable(scope) abort
    let old = get(get(a:scope, 'neomake', {}), 'disabled', -1)
    if old ==# 1
        return
    endif
    call neomake#config#set_dict(a:scope, 'neomake.disabled', 1)
    call s:handle_disabled_status(a:scope, 1)
endfunction

function! s:enable(scope) abort
    let old = get(get(a:scope, 'neomake', {}), 'disabled', -1)
    if old != 1
        return
    endif
    call neomake#config#set_dict(a:scope, 'neomake.disabled', 0)
    call s:handle_disabled_status(a:scope, 0)
endfunction

function! s:toggle(scope) abort
    let new = !get(get(a:scope, 'neomake', {}), 'disabled', 0)
    if new
        call neomake#config#set_dict(a:scope, 'neomake.disabled', 1)
        call s:handle_disabled_status(a:scope, 1)
    else
        call neomake#config#unset_dict(a:scope, 'neomake.disabled')
        call s:handle_disabled_status(a:scope, 0)
    endif
endfunction

function! s:display_status() abort
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

    echom msg
    call neomake#log#debug(msg)
endfunction

command! -bar NeomakeToggle call s:toggle(g:)
command! -bar NeomakeToggleBuffer call s:toggle(b:)
command! -bar NeomakeToggleTab call s:toggle(t:)
command! -bar NeomakeDisable call s:disable(g:)
command! -bar NeomakeDisableBuffer call s:disable(b:)
command! -bar NeomakeDisableTab call s:disable(t:)
command! -bar NeomakeEnable call s:enable(g:)
command! -bar NeomakeEnableBuffer call s:enable(b:)
command! -bar NeomakeEnableTab call s:enable(t:)

command! NeomakeStatus call s:display_status()
" }}}

" NOTE: experimental, no default mappings.
" NOTE: uses -addr=lines (default), and therefore negative counts do not work
"       (see https://github.com/vim/vim/issues/3654).
command! -bar -count=1 NeomakeNextLoclist call neomake#list#next(<count>, 1)
command! -bar -count=1 NeomakePrevLoclist call neomake#list#prev(<count>, 1)
command! -bar -count=1 NeomakeNextQuickfix call neomake#list#next(<count>, 0)
command! -bar -count=1 NeomakePrevQuickfix call neomake#list#prev(<count>, 0)

function! s:define_highlights() abort
    if g:neomake_place_signs
        call neomake#signs#DefineHighlights()
    endif
    if get(g:, 'neomake_highlight_columns', 1)
                \ || get(g:, 'neomake_highlight_lines', 0)
        call neomake#highlights#DefineHighlights()
    endif
endfunction

function! s:setup_autocmds() abort
    augroup neomake
        au!
        if !exists('*nvim_buf_add_highlight')
            autocmd BufEnter * call neomake#highlights#ShowHighlights()
        endif
        if has('timers')
            autocmd CursorMoved * call neomake#CursorMovedDelayed()
            " Force-redraw display of current error after resizing Vim, which appears
            " to clear the previously echoed error.
            autocmd VimResized * call timer_start(100, function('neomake#EchoCurrentError'))
        else
            autocmd CursorHold,CursorHoldI * call neomake#CursorMoved()
        endif
        autocmd VimLeave * call neomake#VimLeave()
        autocmd ColorScheme * call s:define_highlights()
    augroup END
endfunction

if has('signs')
    let g:neomake_place_signs = get(g:, 'neomake_place_signs', 1)
else
    let g:neomake_place_signs = 0
    lockvar g:neomake_place_signs
endif

call s:setup_autocmds()

" vim: sw=4 et
" vim: ts=4 sw=4 et
