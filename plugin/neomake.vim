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
command! -nargs=1 NeomakeCancelJob call neomake#CancelJob(<args>)

command! -bar NeomakeInfo call neomake#DisplayInfo()

augroup neomake
  au!
  au WinEnter,CursorHold * call neomake#ProcessCurrentWindow()
  au BufEnter * call neomake#highlights#ShowHighlights()
  au CursorMoved * call neomake#CursorMoved()
  au ColorScheme,VimEnter * call neomake#signs#DefineHighlights()
augroup END

" vim: sw=2 et
