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

function! s:NeomakeSh(sh_command)
    let custom_maker = neomake#utils#MakerFromCommand(&shell, a:sh_command)
    let custom_maker.name = 'sh: '.a:sh_command
    let custom_maker.remove_invalid_entries = 0
    let enabled_makers =  [custom_maker]
    call neomake#Make({'enabled_makers': enabled_makers})
endfunction

command! -nargs=* -bang -bar -complete=customlist,neomake#CompleteMakers Neomake call s:NeomakeCommand(<bang>1, [<f-args>])
" These commands are available for clarity
command! -nargs=* -bar -complete=customlist,neomake#CompleteMakers NeomakeProject Neomake! <args>
command! -nargs=* -bar -complete=customlist,neomake#CompleteMakers NeomakeFile Neomake <args>

command! -nargs=+ -complete=shellcmd NeomakeSh call s:NeomakeSh(<q-args>)

command! NeomakeListJobs call neomake#ListJobs()

augroup neomake
    autocmd!
    autocmd BufWinEnter,CursorHold * call neomake#ProcessCurrentBuffer()
    autocmd CursorMoved * call neomake#CursorMoved()
augroup END
