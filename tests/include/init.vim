" Sourced by ./setup.vader.
" Keeping this in a separate file is better for performance.

function! s:wait_for_jobs(filter)
  let max = 45
  while 1
    let jobs = copy(neomake#GetJobs())
    if len(a:filter)
      let jobs = filter(jobs, a:filter)
    endif
    if !len(jobs)
      break
    endif
    let max -= 1
    if max == 0
      for j in jobs
        call vader#log('Remaining job: '.string(neomake#utils#fix_self_ref(j)))
      endfor
      call neomake#CancelJobs(1)
      throw len(jobs).' jobs did not finish after 3s.'
    endif
    exe 'sleep' (max < 25 ? 100 : max < 35 ? 50 : 10).'m'
  endwhile
endfunction
command! NeomakeTestsWaitForFinishedJobs call s:wait_for_jobs("!get(v:val, 'finished')")
command! NeomakeTestsWaitForRemovedJobs call s:wait_for_jobs('')

function! s:wait_for_next_message()
  let max = 45
  let n = len(g:neomake_test_messages)
  while 1
    let max -= 1
    if max == 0
      throw 'No new message appeared after 3s.'
    endif
    exe 'sleep' (max < 25 ? 100 : max < 35 ? 50 : 10).'m'
    if len(g:neomake_test_messages) != n
      break
    endif
  endwhile
endfunction
command! NeomakeTestsWaitForNextMessage call s:wait_for_next_message()

function! s:wait_for_message(...)
  let max = 45
  let n = len(g:neomake_test_messages)
  let error = 'No new message appeared after 3s.'
  while 1
    let max -= 1
    if max == 0
      throw error
    endif
    exe 'sleep' (max < 25 ? 100 : max < 35 ? 50 : 10).'m'
    if len(g:neomake_test_messages) != n
      try
        call call('s:AssertNeomakeMessage', a:000)
      catch
        let error = v:exception
        let n = len(g:neomake_test_messages)
        continue
      endtry
      break
    endif
  endwhile
endfunction
command! -nargs=+ NeomakeTestsWaitForMessage call s:wait_for_message(<args>)

function! s:wait_for_finished_job()
  Assert neomake#has_async_support(), 'NeomakeTestsWaitForNextFinishedJob should only be used for async mode'
  if !exists('#neomake_tests')
    call g:NeomakeSetupAutocmdWrappers()
  endif
  let max = 45
  let n = len(g:neomake_test_jobfinished)
  let start = neomake#compat#reltimefloat()
  while 1
    let max -= 1
    if max == 0
      throw printf('No job finished after %.3fs.', neomake#compat#reltimefloat() - start)
    endif
    exe 'sleep' (max < 25 ? 10 : max < 35 ? 5 : 1).'m'
    if len(g:neomake_test_jobfinished) != n
      break
    endif
  endwhile
endfunction
command! NeomakeTestsWaitForNextFinishedJob call s:wait_for_finished_job()

command! -nargs=* RunNeomake Neomake <args>
  \ | NeomakeTestsWaitForFinishedJobs
command! -nargs=* RunNeomakeProject NeomakeProject <args>
  \ | NeomakeTestsWaitForFinishedJobs
command! -nargs=* CallNeomake call neomake#Make(<args>)
  \ | NeomakeTestsWaitForFinishedJobs

" NOTE: NeomakeSh does not use '-bar'.
command! -nargs=* RunNeomakeSh call RunNeomakeSh(<q-args>)
function! RunNeomakeSh(...)
  call call('neomake#Sh', a:000)
  NeomakeTestsWaitForFinishedJobs
endfunction

let s:tempname = tempname()

function! g:NeomakeTestsCreateExe(name, lines)
  let path_separator = exists('+shellslash') ? ';' : ':'
  let dir_separator = exists('+shellslash') ? '\' : '/'
  let tmpbindir = s:tempname . dir_separator . 'neomake-vader-tests'
  let exe = tmpbindir.dir_separator.a:name
  if $PATH !~# tmpbindir . path_separator
    Save $PATH
    if !isdirectory(tmpbindir)
      call mkdir(tmpbindir, 'p', 0770)
    endif
    let $PATH = tmpbindir . ':' . $PATH
  endif
  call writefile(a:lines, exe)
  if exists('*setfperm')
    call setfperm(exe, 'rwxrwx---')
  else
    " XXX: Windows support
    call system('chmod 770 '.shellescape(exe))
  endif
endfunction

function! s:AssertNeomakeMessage(msg, ...)
  let level = a:0 ? a:1 : -1
  let context = a:0 > 1 ? copy(a:2) : -1
  let options = a:0 > 2 ? a:3 : {}
  let found_but_before = 0
  let found_but_context_diff = []
  let ignore_order = get(options, 'ignore_order', 0)
  let found_but_other_level = -1
  let idx = -1
  for [l, m, info] in g:neomake_test_messages
    let r = 0
    let idx += 1
    if a:msg[0] ==# '\'
      let g:neomake_test_matchlist = matchlist(m, a:msg)
      let matches = len(g:neomake_test_matchlist)
    else
      let matches = m ==# a:msg
    endif
    if matches
      if level == -1
        let r = 1
      else
        if l == level
          let r = 1
        else
          let found_but_other_level = l
        endif
      endif
    endif
    if r
      if !ignore_order && idx <= g:neomake_test_messages_last_idx
        if idx < g:neomake_test_messages_last_idx
          let found_but_before = 1
        endif
        let r = 0
      endif
    endif
    if !r
      continue
    endif

    if type(context) == type({})
      let context_diff = []
      " Only compare entries relevant for messages.
      call filter(context, "index(['id', 'make_id', 'bufnr'], v:key) != -1")
      let l:UNDEF = {}
      for [k, v] in items(info)
        let expected = get(context, k, l:UNDEF)
        if expected is l:UNDEF
          call add(context_diff, printf('Missing value for context.%s: '
              \  ."expected nothing, but got '%s'.", k, string(v)))
          continue
        endif
        try
          let same = v ==# expected
        catch
          call add(context_diff, printf(
            \ 'Could not compare context entries (expected: %s, actual: %s): %s',
            \ string(expected), string(v), v:exception))
          continue
        endtry
        if !same
          call add(context_diff, printf('Got unexpected value for context.%s: '
            \  ."expected '%s', but got '%s'.", k, string(expected), string(v)))
        endif
        unlet v  " for Vim without patch-7.4.1546
      endfor
      let missing = filter(copy(context), 'index(keys(info), v:key) == -1')
      for [k, expected] in items(missing)
        call add(context_diff, printf('Missing entry for context.%s: '
          \  ."expected '%s', but got nothing.", k, string(expected)))
      endfor
      let found_but_context_diff = context_diff
      if len(context_diff)
        if ignore_order
          continue
        endif
        throw join(context_diff, "\n")
      endif
    endif
    let g:neomake_test_messages_last_idx = idx
    " Make it count as a successful assertion.
    Assert 1
    return 1
  endfor
  if found_but_before || found_but_other_level != -1
    let msg = []
    if found_but_other_level != -1
      let msg += ['for level '.found_but_other_level]
    endif
    if found_but_before
      let msg += ['_before_ last asserted one']
    endif
    let msg = "Message '".a:msg."' was found, but ".join(msg, ' and ')
    throw msg
  endif
  if !empty(found_but_context_diff)
    throw join(found_but_context_diff, "\n")
  endif
  throw "Message '".a:msg."' not found."
endfunction
command! -nargs=+ AssertNeomakeMessage call s:AssertNeomakeMessage(<args>)

function! s:AssertNeomakeMessageAbsent(msg, ...)
  try
    call call('s:AssertNeomakeMessage', [a:msg] + a:000)
  catch /^Message/
    return 1
  endtry
  throw 'Found unexpected message: '.a:msg
endfunction
command! -nargs=+ AssertNeomakeMessageAbsent call s:AssertNeomakeMessageAbsent(<args>)

function! s:NeomakeTestsResetMessages()
  let g:neomake_test_messages = []
  let g:neomake_test_messages_last_idx = -1
endfunction
command! NeomakeTestsResetMessages call s:NeomakeTestsResetMessages()

function! g:NeomakeSetupAutocmdWrappers()
  let g:neomake_test_finished = []
  function! s:OnNeomakeFinished(context)
    let g:neomake_test_finished += [a:context]
  endfunction

  let g:neomake_test_jobfinished = []
  function! s:OnNeomakeJobFinished(context)
    let g:neomake_test_jobfinished += [a:context]
  endfunction

  let g:neomake_test_countschanged = []
  function! s:OnNeomakeCountsChanged(context)
    let g:neomake_test_countschanged += [a:context]
  endfunction

  augroup neomake_tests
    au!
    au User NeomakeFinished call s:OnNeomakeFinished(g:neomake_hook_context)
    au User NeomakeJobFinished call s:OnNeomakeJobFinished(g:neomake_hook_context)
    au User NeomakeCountsChanged call s:OnNeomakeCountsChanged(g:neomake_hook_context)
  augroup END
endfunction

command! -nargs=1 NeomakeTestsSkip call vader#log('SKIP: ' . <args>)

function! NeomakeAsyncTestsSetup()
  if neomake#has_async_support()
    call neomake#statusline#ResetCounts()
    call g:NeomakeSetupAutocmdWrappers()
    return 1
  endif
  NeomakeTestsSkip 'no async support.'
endfunction

function! NeomakeTestsCommandMaker(name, cmd)
  let maker = neomake#utils#MakerFromCommand(a:cmd)
  return extend(maker, {
  \ 'name': a:name,
  \ 'errorformat': '%m',
  \ 'append_file': 0})
endfunction

function! NeomakeTestsFakeJobinfo() abort
  let make_info = neomake#GetStatus().make_info
  let make_info[-42] = {
        \ 'verbosity': get(g:, 'neomake_verbose', 1),
        \ 'active_jobs': [],
        \ 'queued_jobs': []}
  return {'file_mode': 1, 'bufnr': bufnr('%'), 'ft': '', 'make_id': -42}
endfunction

function! s:monkeypatch_highlights() abort
  " Monkeypatch to check setting of length.
  runtime autoload/neomake/highlights.vim
  Save g:neomake_tests_highlight_lengths
  let g:neomake_tests_highlight_lengths = []
  function! neomake#highlights#AddHighlight(entry, ...) abort
    call add(g:neomake_tests_highlight_lengths,
    \ [get(a:entry, 'lnum', -1), get(a:entry, 'length', -1)])
  endfunction
endfunction
command! NeomakeTestsMonkeypatchHighlights call s:monkeypatch_highlights()

" Fixtures
let g:sleep_efm_maker = {
    \ 'name': 'sleep_efm_maker',
    \ 'exe': 'sh',
    \ 'args': ['-c', 'sleep 0.01; echo file_sleep_efm:1:E:error message; '
    \         .'echo file_sleep_efm:2:W:warning; '
    \         .'echo file_sleep_efm:1:E:error2'],
    \ 'errorformat': '%f:%l:%t:%m',
    \ 'append_file': 0,
    \ }
let g:sleep_maker = NeomakeTestsCommandMaker('sleep-maker', 'sleep .05; echo slept')
let g:error_maker = NeomakeTestsCommandMaker('error-maker', 'echo error; false')
let g:error_maker.errorformat = '%E%m'
function! g:error_maker.postprocess(entry) abort
  let a:entry.bufnr = bufnr('')
  let a:entry.lnum = 1
endfunction
let g:success_maker = NeomakeTestsCommandMaker('success-maker', 'echo success')
let g:true_maker = NeomakeTestsCommandMaker('true-maker', 'true')
let g:doesnotexist_maker = {'exe': 'doesnotexist'}

" A maker that generates incrementing errors.
let g:neomake_test_inc_maker_counter = 0
function! s:IncMakerArgs()
  let g:neomake_test_inc_maker_counter += 1
  let cmd = ''
  for i in range(g:neomake_test_inc_maker_counter)
    let cmd .= 'echo b'.g:neomake_test_inc_maker_counter.' '.g:neomake_test_inc_maker_counter.':'.i.': buf: '.shellescape(bufname('%')).'; '
  endfor
  return ['-c', cmd]
endfunction
let g:neomake_test_inc_maker = {
      \ 'name': 'incmaker',
      \ 'exe': &shell,
      \ 'args': function('s:IncMakerArgs'),
      \ 'errorformat': '%E%f %m',
      \ 'append_file': 0,
      \ }

function! NeomakeTestsGetSigns()
  let signs = split(neomake#utils#redir('sign place'), '\n')
  call map(signs, "substitute(substitute(v:val, '\\m^\\s\\+', '', ''), '\\m\\s\\+$', '', '')")
  return signs[1:-1]
endfunction

function! s:After()
  if exists('g:neomake_tests_highlight_lengths')
    " Undo monkeypatch.
    runtime autoload/neomake/highlights.vim
  endif

  Restore
  unlet! g:expected  " for old Vim with Vader, that does not wrap tests in a function.

  let errors = []

  " Stop any (non-canceled) jobs.  Canceled jobs might take a while to call the
  " exit handler, but that is OK.
  let jobs = filter(neomake#GetJobs(), "!get(v:val, 'canceled', 0)")
  if len(jobs)
    for job in jobs
      call neomake#CancelJob(job.id, !neomake#has_async_support())
    endfor
    call add(errors, 'There were '.len(jobs).' jobs left: '
    \ .string(map(jobs, "v:val.make_id.'.'.v:val.id")))
  endif

  let status = neomake#GetStatus()
  let make_info = status.make_info
  if has_key(make_info, -42)
    unlet make_info[-42]
  endif
  if !empty(make_info)
    call add(errors, 'make_info is not empty: '.string(make_info))
  endif
  let actions = filter(copy(status.action_queue), '!empty(v:val)')
  if !empty(actions)
    call add(errors, printf('action_queue is not empty: %d entries: %s',
          \ len(actions), string(status.action_queue)))
  endif
  try
    NeomakeTestsWaitForRemovedJobs
  catch
    call neomake#CancelJobs(1)
    call add(errors, v:exception)
  endtry

  if exists('#neomake_tests')
    autocmd! neomake_tests
    augroup! neomake_tests
  endif

  if winnr('$') > 1
    let error = 'More than 1 window after tests: '
      \ .string(map(range(1, winnr('$')),
      \ "[bufname(winbufnr(v:val)), getbufvar(winbufnr(v:val), '&bt')]"))
    try
      for b in neomake#compat#uniq(sort(tabpagebuflist()))
        if bufname(b) !=# '[Vader-workbench]'
          exe 'bwipe!' b
        endif
      endfor
      " In case there are two windows with Vader-workbench.
      only
    catch
      Log "Error while cleaning windows: ".v:exception
    endtry
    call add(errors, error)
  elseif bufname(winbufnr(1)) !=# '[Vader-workbench]'
    call add(errors, 'Vader-workbench has been renamed: '.bufname(winbufnr(1)))
  endif

  " Ensure that all w:neomake_make_ids lists have been removed.
  for t in [tabpagenr()] + range(1, tabpagenr()-1) + range(tabpagenr()+1, tabpagenr('$'))
    for w in range(1, tabpagewinnr(t, '$'))
      let val = gettabwinvar(t, w, 'neomake_make_ids')
      if !empty(val)  " '' (default) or [] (used and emptied).
        call add(errors, 'neomake_make_ids left for tab '.t.', win '.w.': '.string(val))
        call settabwinvar(t, w, 'neomake_make_ids', [])
      endif
      unlet val  " for Vim without patch-7.4.1546
    endfor
  endfor

  let new_buffers = filter(range(1, bufnr('$')), 'bufexists(v:val) && index(g:neomake_test_buffers_before, v:val) == -1')
  if !empty(new_buffers)
    call add(errors, 'Unexpected/not wiped buffers: '.join(new_buffers, ', '))
    Log neomake#utils#redir('ls!')
    for b in new_buffers
      exe 'bwipe!' b
    endfor
  endif

  for k in keys(make_info)
    unlet make_info[k]
  endfor

  " Check that no new global functions are defined.
  redir => output_func
    silent function /\C^[A-Z]
  redir END
  let funcs = map(split(output_func, '\n'),
        \ "substitute(v:val, '\\v^function (.*)\\(.*$', '\\1', '')")
  let new_funcs = filter(copy(funcs), 'index(g:neomake_test_funcs_before, v:val) == -1')
  if !empty(new_funcs)
    call add(errors, 'New global functions (use script-local ones, or :delfunction to clean them): '.string(new_funcs))
    call extend(g:neomake_test_funcs_before, new_funcs)
  endif

  if exists('#neomake_event_queue')
    call add(errors, '#neomake_event_queue was not empty.')
    autocmd! neomake_event_queue
    augroup! neomake_event_queue
  endif

  if !empty(errors)
    " Reload to reset e.g. s:action_queue.
    runtime autoload/neomake.vim
    throw len(errors).' error(s) in teardown: '.join(errors, "\n")
  endif
endfunction
command! NeomakeTestsGlobalAfter call s:After()
