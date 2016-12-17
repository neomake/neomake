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

function! s:neomake_init()
  call neomake#highlights#DefineHighlights()
  if has('signs')
    let g:neomake_place_signs = get(g:, 'neomake_place_signs', 1)
    if g:neomake_place_signs
      call neomake#signs#DefineHighlights()
      call neomake#signs#DefineSigns()
    endif
  else
    let g:neomake_place_signs = 0
    lockvar g:neomake_place_signs
  endif
endfunction

augroup neomake
  au!
  au WinEnter,CursorHold * call neomake#ProcessCurrentWindow()
  au BufEnter * call neomake#highlights#ShowHighlights()
  au CursorMoved * call neomake#CursorMoved()
  au ColorScheme,VimEnter * call s:neomake_init()
augroup END

" vim: sw=2 et
