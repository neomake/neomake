command! Neomake NeomakeFile
command! NeomakeFile call neomake#Make({
    \ 'enabled_makers': neomake#GetEnabledMakers(&ft),
    \ 'ft': &ft,
    \ 'file_mode': 1,
    \ })
command! NeomakeProject call neomake#Make(
    \ {'enabled_makers': neomake#GetEnabledMakers()})
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
