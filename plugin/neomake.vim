command! -nargs=* -bang -bar -complete=customlist,neomake#CompleteMakers
      \ Neomake call neomake#Make(<bang>1, [<f-args>])

" These commands are available for clarity
command! -nargs=* -bar -complete=customlist,neomake#CompleteMakers
      \ NeomakeProject Neomake! <args>
command! -nargs=* -bar -complete=customlist,neomake#CompleteMakers
      \ NeomakeFile Neomake <args>

command! -nargs=+ -complete=shellcmd NeomakeSh call neomake#Sh(<q-args>)
command! NeomakeListJobs call neomake#ListJobs()
command! -nargs=1 NeomakeCancelJob call neomake#CancelJob(<args>)

augroup neomake
  au!
  au WinEnter,CursorHold * call neomake#ProcessCurrentWindow()
  au CursorMoved * call neomake#CursorMoved()
augroup END

" vim: sw=2 et
