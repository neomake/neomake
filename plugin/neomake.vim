" vim: ts=4 sw=4 et

function! s:NeomakeCommand(file_mode, enabled_makers)
    if a:file_mode
        call neomake#Make({
            \ 'enabled_makers': len(a:enabled_makers) ?
                \ a:enabled_makers :
                \ neomake#GetEnabledMakers(&ft),
            \ 'ft': &ft,
            \ 'file_mode': 1,
            \ })
    else
        call neomake#Make({
            \ 'enabled_makers': len(a:enabled_makers) ?
                \ a:enabled_makers :
                \ neomake#GetEnabledMakers()
            \ })
    endif
endfunction

command! -nargs=* -bang Neomake call s:NeomakeCommand('<bang>' !=# '!', [<f-args>])
" These commands are available for clarity
command! -nargs=* NeomakeProject Neomake! <args>
command! -nargs=* NeomakeFile Neomake <args>

command! NeomakeListJobs call neomake#ListJobs()

augroup neomake
    autocmd!
    if has('nvim')
        au JobActivity neomake* call neomake#MakeHandler()
    endif
augroup END

function! NeomakeEchoCurrentErrorEnable()
    call NeomakeEchoCurrentErrorDisable()
    au neomake CursorMoved * call neomake#CursorMoved()
endfunction

function! NeomakeEchoCurrentErrorDisable()
    autocmd! neomake CursorMoved
endfunction

if get(g:, 'neomake_echo_current_error', 1)
    " Call after creating the neomake augroup
    call NeomakeEchoCurrentErrorEnable()
endif
