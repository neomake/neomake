function! s:neomake_autolint_delayed(mode) abort
  if exists('s:autolint_timer')
    call timer_stop(s:autolint_timer)
    unlet s:autolint_timer
  endif
  let s:autolint_laststate = [getpos('.'), a:mode, bufnr('%')]
  let s:autolint_timer = timer_start(
        \ get(g:, 'neomake#config#autolint_delay', 500),
        \ function('s:autolint_delayed_cb'))
endfunction

function! s:autolint_delayed_cb(timer) abort
  if [getpos('.'), mode(), bufnr('%')] == s:autolint_laststate
    if b:changedtick != get(get(b:, 'neomake_state', {}), 'changedtick', -1)
      Neomake

      if !exists('b:neomake_state')
        let b:neomake_state = {}
      endif
      let b:neomake_state.changedtick = b:changedtick
    endif
  endif
endfunction

function! neomake#configure#autolint(modes, ...) abort
  if a:0
    let g:neomake#config#autolint_delay = a:1
  endif

  augroup neomake_autolint
    au!
    if len(a:modes)
      if !has('timers')
        call neomake#utils#ErrorMessage('Timer support is required for autolinting.')
      endif
      if a:modes =~# 'n'
        autocmd WinEnter,CursorMoved * call <SID>neomake_autolint_delayed('n')
      endif
      if a:modes =~# 'i'
        autocmd InsertEnter,CursorMovedI * call <SID>neomake_autolint_delayed('i')
      endif
    endif
  augroup END
endfunction
