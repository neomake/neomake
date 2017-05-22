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

augroup neomake
  au!
  if !exists('*nvim_buf_add_highlight')
    au BufEnter * call neomake#highlights#ShowHighlights()
  endif
  if has('timers')
    au CursorMoved * call neomake#CursorMovedDelayed()
    " Force-redraw display of current error after resizing Vim, which appears
    " to clear the previously echoed error.
    au VimResized * call timer_start(100, function('neomake#EchoCurrentError'))
  else
    au CursorMoved * call neomake#CursorMoved()
  endif
  au VimLeave * call neomake#VimLeave()
augroup END

if has('signs')
  let g:neomake_place_signs = get(g:, 'neomake_place_signs', 1)
else
  let g:neomake_place_signs = 0
  lockvar g:neomake_place_signs
endif

" vim: sw=2 et
