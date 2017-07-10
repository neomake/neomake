if exists('g:loaded_neomake') || &compatible
    finish
endif
let g:loaded_neomake = 1

command! -nargs=* -bang -bar -complete=customlist,neomake#CompleteMakers
            \ Neomake call neomake#Make(<bang>1, [<f-args>])

" These commands are available for clarity
command! -nargs=* -bar -complete=customlist,neomake#CompleteMakers
            \ NeomakeProject Neomake! <args>
command! -nargs=* -bar -complete=customlist,neomake#CompleteMakers
            \ NeomakeFile Neomake <args>

command! -nargs=+ -bang -complete=shellcmd
            \ NeomakeSh call neomake#ShCommand(<bang>0, <q-args>)
command! NeomakeListJobs call neomake#ListJobs()
command! -bang -nargs=1 -complete=custom,neomake#CompleteJobs
            \ NeomakeCancelJob call neomake#CancelJob(<q-args>, <bang>0)
command! -bang NeomakeCancelJobs call neomake#CancelJobs(<bang>0)

command! -bar NeomakeInfo call neomake#DisplayInfo()

" Enable/disable/toggle commands.  {{{
function! s:toggle(scope) abort
    let new = !get(get(a:scope, 'neomake', {}), 'disabled', 0)
    if new
        call neomake#config#set_dict(a:scope, 'neomake.disabled', new)
    else
        call neomake#config#unset_dict(a:scope, 'neomake.disabled')
    endif
    call s:display_status()
endfunction
function! s:disable(scope, disabled) abort
    call neomake#config#set_dict(a:scope, 'neomake.disabled', a:disabled)
    if &verbose
        call s:display_status()
    endif
endfunction
function! s:display_status() abort
    let [disabled, source] = neomake#config#get_with_source('disabled', 0)
    let msg = 'Neomake is ' . (disabled ? 'disabled' : 'enabled')
    if source !=# 'default'
        let msg .= ' ('.source.')'
    endif
    echom msg.'.'
endfunction
command! -bar NeomakeToggle call s:toggle(g:)
command! -bar NeomakeToggleBuffer call s:toggle(b:)
command! -bar NeomakeToggleTab call s:toggle(t:)
command! -bar NeomakeDisable call s:disable(g:, 1)
command! -bar NeomakeDisableBuffer call s:disable(b:, 1)
command! -bar NeomakeDisableTab call s:disable(t:, 1)
command! -bar NeomakeEnable call s:disable(g:, 0)
command! -bar NeomakeEnableBuffer call s:disable(b:, 0)
command! -bar NeomakeEnableTab call s:disable(t:, 0)

command! NeomakeStatus call s:display_status()
" }}}

function! s:define_highlights() abort
    if g:neomake_place_signs
        call neomake#signs#DefineHighlights()
    endif
    if get(g:, 'neomake_highlight_columns', 1)
                \ || get(g:, 'neomake_highlight_lines', 0)
        call neomake#highlights#DefineHighlights()
    endif
endfunction

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
        autocmd CursorMoved * call neomake#CursorMoved()
    endif
    autocmd VimLeave * call neomake#VimLeave()
    autocmd ColorScheme * call s:define_highlights()
augroup END

if has('signs')
    let g:neomake_place_signs = get(g:, 'neomake_place_signs', 1)
else
    let g:neomake_place_signs = 0
    lockvar g:neomake_place_signs
endif

" vim: sw=2 et
