let s:timer_info = {}
let s:timer_by_bufnr = {}

function! s:get_setting(name, default) abort
  return get(get(b:, 'neomake', {}), a:name,
        \ get(get(g:, 'neomake', {}), a:name, a:default))
endfunction

function! s:neomake_autolint_delayed(mode) abort
  let bufnr = bufnr('%')
  if exists('s:timer_by_bufnr[bufnr]')
    call timer_stop(s:timer_by_bufnr[bufnr])
    unlet s:timer_by_bufnr[bufnr]
  endif

  " TODO: test
  let buftype = getbufvar(bufnr, '&buftype')
  if len(buftype)
    call neomake#utils#DebugMessage(printf(
          \ 'autolint: timer: skipping setup for buftype=%s (bufnr=%s)', buftype, bufnr))
    return
  endif

  let delay = s:get_setting('autolint_delay', 500)
  let timer = timer_start(
        \ delay,
        \ function('s:autolint_delayed_cb'))
  let s:timer_info[timer] = {
        \ 'context': [getpos('.'), a:mode, bufnr]}
  let s:timer_by_bufnr[bufnr] = timer
endfunction

function! s:autolint_delayed_cb(timer) abort
  let bufnr = bufnr('%')
  let timer_info = s:timer_info[a:timer]
  if !len(timer_info)
    " Timed out in a different buffer?!
    " TODO: restart?
    "
    return
  endif

  if [getpos('.'), mode(), bufnr] == timer_info.context
    if b:changedtick != get(b:, 'neomake_autolint_tick', -1)
      Neomake

      let b:neomake_autolint_tick = b:changedtick
    endif
  endif

  unlet s:timer_info[a:timer]
endfunction

function! neomake#configure#autolint_for_buffer(...) abort
  let bufnr = a:0 > 2 ? a:3 : bufnr('%')
  let buftype = getbufvar(bufnr, '&buftype')
  if !empty(&buftype)
    call neomake#utils#DebugMessage(printf(
          \ 'autolint: skipping setup for buftype=%s (bufnr=%s)', buftype, bufnr))
    return
  endif
  if a:0 > 0
    if !exists('b:neomake')
      let b:neomake = {}
    endif
    let b:neomake.autolint_modes = a:1
    if a:0 > 1
      let b:neomake.autolint_delay = a:2
    endif
  endif

  augroup neomake_autolint_buffer
    let modes = s:get_setting('autolint_modes', '')
    if len(modes)
      if modes =~# 'n' || modes =~# 'i'
        if !has('timers')
          call neomake#utils#ErrorMessage('Timer support is required for autolinting.')
        else
          if modes =~# 'n'
            autocmd WinEnter <buffer> call <SID>neomake_autolint_delayed('n')
            autocmd TextChanged <buffer> call <SID>neomake_autolint_delayed('n')
          endif
          if modes =~# 'i'
            autocmd TextChangedI <buffer> call <SID>neomake_autolint_delayed('i')
          endif
        endif
      endif
    endif
    if modes =~# 'w'
      autocmd BufWritePost <buffer> Neomake
    endif
  augroup END
  " Log neomake#utils#redir('au neomake_autolint_buffer')
endfunction

function! neomake#configure#autolint(...) abort
  if a:0
    if !exists('g:neomake')
      let g:neomake = {}
    endif
    let g:neomake.autolint_modes = a:1
    if a:0 > 1
      let g:neomake.autolint_delay = a:2
    endif
  endif

  augroup neomake_autolint
    au!
    if len(g:neomake.autolint_modes)
      if !has('timers')
        call neomake#utils#ErrorMessage('Timer support is required for autolinting.')
      else
        autocmd FileType,BufWinEnter,BufNew * call neomake#configure#autolint_for_buffer()
      endif
      " Setup current buffer now.
      call neomake#configure#autolint_for_buffer()
    endif
  augroup END
endfunction
