command! Neomake NeomakeFile
command! NeomakeFile call neomake#Make({
    \ 'enabled_makers': neomake#GetEnabledMakers(&ft),
    \ 'ft': &ft,
    \ 'file_mode': 1,
    \ })
command! NeomakeProject call neomake#Make(
    \ {'enabled_makers': neomake#GetEnabledMakers()})
command! NeomakeListJobs call neomake#ListJobs()

if has('nvim')
    augroup neomake
        autocmd!
        au JobActivity neomake* call neomake#MakeHandler()
    augroup END
endif
