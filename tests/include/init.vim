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
  let n = g:neomake_test_messages_last_idx + 1
  let timeout = get(a:0 > 3 ? a:4 : {}, 'timeout', 3000)
  if timeout < 300
    throw 'NeomakeTestsWaitForMessage: timeout should be at least 300 (ms), got: '.string(timeout)
  endif
  let error = ''
  let total_slept = 0
  while 1
    let max -= 1
    if max == 0
      if empty(error)
        let error = printf('No new message appeared after %dms.', timeout)
      endif
      let error .= ' (total wait time: '.total_slept.'m)'
      throw error
    endif
    let ms = (max < 25 ? (timeout/30)+1 : max < 35 ? (timeout/60)+1 : (timeout/300)+1)
    let total_slept += ms
    exe 'sleep' ms.'m'
    if len(g:neomake_test_messages) > n
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
  if !neomake#has_async_support() && !has('timers')
    return
  endif
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

function! g:NeomakeTestsCreateExe(name, ...)
  let lines = a:0 ? a:1 : []
  let path_separator = exists('+shellslash') ? ';' : ':'
  let dir_separator = exists('+shellslash') ? '\' : '/'
  let tmpbindir = s:tempname . dir_separator . 'neomake-vader-tests'
  let exe = tmpbindir.dir_separator.a:name
  if $PATH !~# tmpbindir . path_separator
    if !isdirectory(tmpbindir)
      call mkdir(tmpbindir, 'p', 0770)
    endif
    call g:NeomakeTestsSetPATH(tmpbindir . ':' . $PATH)
  endif
  call writefile(lines, exe)
  if exists('*setfperm')
    call setfperm(exe, 'rwxrwx---')
  else
    " XXX: Windows support
    call system('/bin/chmod 770 '.shellescape(exe))
    Assert !v:shell_error, 'Got shell_error with chmod: '.v:shell_error
  endif
endfunction

let s:saved_path = 0
function! g:NeomakeTestsSetPATH(path) abort
  if !s:saved_path
    Save $PATH
    let s:saved_path = 1
  endif
  let $PATH = a:path
endfunction

function! s:AssertNeomakeMessage(msg, ...)
  let level = a:0 ? a:1 : -1
  let context = a:0 > 1 ? copy(a:2) : -1
  let options = a:0 > 2 ? a:3 : {}
  let found_but_before = -1
  let found_but_context_diff = []
  let ignore_order = get(options, 'ignore_order', 0)
  let found_but_other_level = -1
  let idx = -1
  for msg_entry in g:neomake_test_messages
    let [l, m, info] = msg_entry
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
        let found_but_before = g:neomake_test_messages_last_idx - idx
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
    call add(g:_neomake_test_asserted_messages, msg_entry)
    return 1
  endfor
  if found_but_before != -1 || found_but_other_level != -1
    let msgs = []
    if found_but_other_level != -1
      let msgs += ['for level '.found_but_other_level]
    endif
    if found_but_before != -1
      let msgs += [printf('%d entries before last asserted one', found_but_before)]
    endif
    let msg = printf('Message %s was found, but %s.', string(a:msg), join(msgs, ' and '))
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
  let make_id = -42
  let jobinfo = {'file_mode': 1, 'bufnr': bufnr('%'), 'ft': '', 'make_id': make_id}
  let make_info = neomake#GetStatus().make_info
  let make_info[make_id] = {
        \ 'options': jobinfo,
        \ 'verbosity': get(g:, 'neomake_verbose', 1),
        \ 'active_jobs': [],
        \ 'finished_jobs': []}
  return jobinfo
endfunction

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
let g:success_maker.errorformat = '%-Gsuccess'
let g:true_maker = NeomakeTestsCommandMaker('true-maker', 'true')
let g:entry_maker = {'name': 'entry_maker'}
function! g:entry_maker.get_list_entries(...) abort
  return get(g:, 'neomake_test_getlistentries', [
  \   {'text': 'error', 'lnum': 1, 'type': 'E'}])
endfunction
let g:doesnotexist_maker = {'exe': 'doesnotexist'}

" A maker that generates incrementing errors.
let g:neomake_test_inc_maker_counter = 0
let s:shell_argv = split(&shell) + split(&shellcmdflag)
function! s:IncMakerArgs()
  let g:neomake_test_inc_maker_counter += 1
  let cmd = ''
  for i in range(g:neomake_test_inc_maker_counter)
    let cmd .= 'echo b'.g:neomake_test_inc_maker_counter.' '.g:neomake_test_inc_maker_counter.':'.i.': buf: '.shellescape(bufname('%')).'; '
  endfor
  return s:shell_argv[1:] + [cmd]
endfunction
let g:neomake_test_inc_maker = {
      \ 'name': 'incmaker',
      \ 'exe': s:shell_argv[0],
      \ 'args': function('s:IncMakerArgs'),
      \ 'errorformat': '%E%f %m',
      \ 'append_file': 0,
      \ }

function! NeomakeTestsGetSigns()
  let signs = split(neomake#utils#redir('sign place'), '\n')
  call map(signs, "substitute(substitute(v:val, '\\m^\\s\\+', '', ''), '\\m\\s\\+$', '', '')")
  return signs[1:-1]
endfunction

let s:vim_msgs_marker = '== neomake_tests_marker =='
function! NeomakeTestsSetVimMessagesMarker()
  echom s:vim_msgs_marker
endfunction

function! NeomakeTestsGetVimMessages()
  let msgs = split(neomake#utils#redir('messages'), "\n")
  call NeomakeTestsSetVimMessagesMarker()
  let idx = index(reverse(msgs), s:vim_msgs_marker)
  if idx <= 0
    return []
  endif
  return reverse(msgs[0 : idx-1])
endfunction

function! NeomakeTestsGetMakerWithOutput(func, lines_or_file) abort
  if type(a:lines_or_file) == type([])
    let output_file = tempname()
    call writefile(a:lines_or_file, output_file)
  else
    let output_file = a:lines_or_file
  endif

  let maker = call(a:func, [])
  let maker.exe = 'cat'
  let maker.args = [output_file]
  let maker.append_file = 0
  let maker.name = printf('%s-mocked', substitute(a:func, '^.*#', '', ''))
  return maker
endfunction

let s:fixture_root = '/tmp/neomake-tests'

function! NeomakeTestsFixtureMaker(func, fname) abort
  let output_base = getcwd().'/'.substitute(a:fname, '^tests/fixtures/input/', 'tests/fixtures/output/', '')
  let stdout = printf('%s.stdout', output_base)
  let stderr = printf('%s.stderr', output_base)
  let exitcode = readfile(printf('%s.exitcode', output_base))[0]

  let maker = call(a:func, [])
  let maker.exe = &shell
  let maker.args = [&shellcmdflag, printf(
        \ 'cat %s; cat %s >&2; exit %d',
        \ fnameescape(stdout), fnameescape(stderr), exitcode)]
  let maker.name = printf('%s-fixture', substitute(a:func, '^.*#', '', ''))

  " Massage current buffer.
  if get(b:, 'neomake_tests_massage_buffer', 1)
    " Write the input file to the temporary root.
    let test_fname = s:fixture_root . '/' . a:fname
    let test_fname_dir = fnamemodify(test_fname, ':h')
    if !isdirectory(test_fname_dir)
      call mkdir(test_fname_dir, 'p')
    endif
    call writefile(readfile(a:fname), test_fname, 'b')
    exe 'file ' . s:fixture_root . '/' . a:fname
    exe 'lcd '.s:fixture_root
  endif

  return maker
endfunction

function! s:After()
  if exists('#neomake_automake')
    au! neomake_automake
  endif

  Restore
  unlet! g:expected  " for old Vim with Vader, that does not wrap tests in a function.

  let errors = g:neomake_test_errors

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

  let unexpected_errors = filter(copy(g:neomake_test_messages),
        \ 'v:val[0] == 0 && index(g:_neomake_test_asserted_messages, v:val) == -1')
  if !empty(unexpected_errors)
    call add(errors, 'found unexpected error messages: '.string(unexpected_errors))
  endif

  let status = neomake#GetStatus()
  let make_info = status.make_info
  if has_key(make_info, -42)
    unlet make_info[-42]
  endif
  if !empty(make_info)
    call add(errors, 'make_info is not empty: '.string(make_info))
    try
      call neomake#CancelAllMakes(1)
    catch
      call add(errors, v:exception)
    endtry
  endif
  let actions = filter(copy(status.action_queue), '!empty(v:val)')
  if !empty(actions)
    call add(errors, printf('action_queue is not empty: %d entries: %s',
          \ len(actions), string(status.action_queue)))
    try
      call neomake#CancelAllMakes(1)
    catch
      call add(errors, v:exception)
    endtry
  endif

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
      Log "Error while cleaning windows: ".v:exception.' (in '.v:throwpoint.').'
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
    let curbuffers = neomake#utils#redir('ls!')
    call add(errors, 'Unexpected/not wiped buffers: '.join(new_buffers, ', ')."\ncurrent buffers:".curbuffers)
    for b in new_buffers
      exe 'bwipe!' b
    endfor
  endif

  " Check that no new global functions are defined.
  let neomake_output_func_after = neomake#utils#redir('function /\C^[A-Z]')
  let funcs = map(split(neomake_output_func_after, '\n'),
        \ "substitute(v:val, '\\v^function (.*)\\(.*$', '\\1', '')")
  let new_funcs = filter(copy(funcs), 'index(g:neomake_test_funcs_before, v:val) == -1')
  if !empty(new_funcs)
    call add(errors, 'New global functions (use script-local ones, or :delfunction to clean them): '.string(new_funcs))
    call extend(g:neomake_test_funcs_before, new_funcs)
  endif

  if exists('#neomake_event_queue')
    call add(errors, '#neomake_event_queue is not empty: ' . neomake#utils#redir('au neomake_event_queue'))
    autocmd! neomake_event_queue
    augroup! neomake_event_queue
  endif

  if !empty(v:warningmsg)
    call add(errors, printf('There was a v:warningmsg: %s', v:warningmsg))
    let v:warningmsg = ''
  endif

  if !empty(errors)
    call map(errors, "printf('%d. %s', v:key+1, v:val)")
    throw len(errors)." error(s) in teardown:\n".join(errors, "\n")
  endif
endfunction
command! NeomakeTestsGlobalAfter call s:After()
