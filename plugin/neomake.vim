" vim: ts=4 sw=4 et

command! -nargs=* -bang -bar -complete=customlist,neomake#CompleteMakers Neomake call neomake#WithCallback(<bang>1, [<f-args>])
" These commands are available for clarity
command! -nargs=* -bar -complete=customlist,neomake#CompleteMakers NeomakeProject Neomake! <args>
command! -nargs=* -bar -complete=customlist,neomake#CompleteMakers NeomakeFile Neomake <args>

command! -nargs=+ -complete=shellcmd NeomakeSh call neomake#ShWithCallback(<q-args>)

command! NeomakeListJobs call neomake#ListJobs()

augroup neomake
    autocmd!
    autocmd BufWinEnter,CursorHold * call neomake#ProcessCurrentBuffer()
    autocmd CursorMoved * call neomake#CursorMoved()
augroup END
