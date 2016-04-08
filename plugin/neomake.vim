" vim: ts=4 sw=4 et

command! -nargs=* -bang -bar -complete=customlist,neomake#CompleteMakers Neomake call neomake#Make(<bang>1, [<f-args>])
" These commands are available for clarity
command! -nargs=* -bar -complete=customlist,neomake#CompleteMakers NeomakeProject Neomake! <args>
command! -nargs=* -bar -complete=customlist,neomake#CompleteMakers NeomakeFile Neomake <args>

command! -nargs=+ -complete=shellcmd NeomakeSh call neomake#Sh(<q-args>)

command! NeomakeListJobs call neomake#ListJobs()

command! -nargs=1 NeomakeCancelJob call neomake#CancelJob(<args>)

augroup neomake
    autocmd!
    autocmd BufWinEnter,CursorHold * call neomake#ProcessCurrentBuffer()
    autocmd CursorMoved * call neomake#CursorMoved()
augroup END
