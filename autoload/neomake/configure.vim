" TODO: slow down timer automatically for several TextChanged events, e.g.
"       when using undo/u?!
"
" Default settings, setup in global config dict.
let s:default_settings = {
      \ 'ignore_filetypes': ['startify'],
      \ }
let g:neomake = get(g:, 'neomake', {})
let g:neomake.automake = get(g:neomake, 'automake', {})
call extend(g:neomake.automake, s:default_settings, 'keep')

let s:timer_info = {}
let s:timer_by_bufnr = {}

let s:default_delay = has('timers') ? 500 : 0

" A mapping of configured buffers with cached settings (enabled_makers).
let s:configured_buffers = {}
" A list of configured/used autocommands.
let s:registered_events = []

" TODO: allow for namespaces, and prefer 'automake' here.
" TODO: handle bufnr!  (getbufvar)
function! s:get_setting(name, default) abort
    return get(get(b:, 'neomake', {}), a:name,
                \ get(get(t:, 'neomake', {}), a:name,
                \ get(get(g:, 'neomake', {}), a:name, a:default)))
endfunction


function! s:debug_log(msg, ...) abort
    let context = {'bufnr': bufnr('%')}
    if a:0
        call extend(context, a:1)
    endif
    call neomake#utils#DebugMessage(printf('automake: %s.', a:msg), context)
endfunction

" Check if buffer's tick (or ft) changed.
function! s:tick_changed(context, update) abort
    let bufnr = +a:context.bufnr
    let ft = get(a:context, 'ft', getbufvar(bufnr, '&filetype'))
    let prev_tick = getbufvar(bufnr, 'neomake_automake_tick')
    let r = 1
    if !empty(prev_tick)
        let cur_tick = [getbufvar(bufnr, 'changedtick'), ft]
        if cur_tick == prev_tick
            return 0
        endif

        " NOTE: every write (BufWritePost) increments b:changedtick.
        if a:context.event ==# 'BufWritePost'
            let adjusted_prev_tick = [prev_tick[0]+1, prev_tick[1]]
            if adjusted_prev_tick == cur_tick
                let r = 0
                call setbufvar(bufnr, 'neomake_automake_tick', adjusted_prev_tick)
            endif
        endif
    endif
    if a:update
        call setbufvar(bufnr, 'neomake_automake_tick',
                    \ [getbufvar(bufnr, 'changedtick'), ft])
    endif
    return r
endfunction

function! s:neomake_do_automake(context) abort
    let disabled = neomake#config#get_with_source('disabled', 0)
    if disabled[0]
        call s:debug_log(printf('disabled (%s)', disabled[1]))
        return
    endif
    let bufnr = +a:context.bufnr

    if a:context.delay
        if exists('s:timer_by_bufnr[bufnr]')
            call timer_stop(s:timer_by_bufnr[bufnr])
            unlet s:timer_by_bufnr[bufnr]
        endif
        " call s:debug_log('context: '.string(context))
        if !s:tick_changed(a:context, 0)
            call s:debug_log('buffer was not changed', {'bufnr': bufnr})
            return
        endif

        " call s:start_timer(a:delay, a:context)
        let timer = timer_start(a:context.delay, function('s:automake_delayed_cb'))
        let s:timer_info[timer] = a:context
        if !has_key(a:context, 'pos')
            let s:timer_info[timer].pos = [getpos('.'), mode()]
        endif
        let s:timer_by_bufnr[a:context.bufnr] = timer
        call s:debug_log(printf('started timer (%dms): %d', a:context.delay, timer),
                    \ {'bufnr': a:context.bufnr})
        return
    endif

    let ft = getbufvar(bufnr, '&filetype')
    let event = a:context.event

    call s:debug_log('neomake_do_automake: '.event, {'bufnr': bufnr})
    if !s:tick_changed({'event': event, 'bufnr': bufnr, 'ft': ft}, 1)
        call s:debug_log('buffer was not changed', {'bufnr': bufnr})
        return
    endif
    let prev_make_id = getbufvar(bufnr, 'neomake_automake_make_id')
    if !empty(prev_make_id)
        call s:debug_log(printf('stopping previous make run: %s', prev_make_id))
        call neomake#CancelMake(prev_make_id)
    endif

    call s:debug_log(printf('enabled makers: %s', join(map(copy(a:context.enabled_makers), "type(v:val) == type('') ? v:val : v:val.name"), ', ')))
    let jobinfos = neomake#Make({
                \ 'file_mode': 1,
                \ 'enabled_makers': a:context.enabled_makers,
                \ 'ft': ft,
                \ 'automake': 1})
    let started_jobs = filter(copy(jobinfos), "!get(v:val, 'finished', 0)")
    call s:debug_log(printf('started jobs: %s', string(map(copy(started_jobs), 'v:val.id'))))
    if !empty(started_jobs)
        call setbufvar(bufnr, 'neomake_automake_make_id', jobinfos[0].make_id)
    endif
endfunction

function! s:automake_delayed_cb(timer) abort
    let timer_info = s:timer_info[a:timer]
    if !len(timer_info)
        call s:debug_log(printf('no timer_info found for timer: %d', a:timer))
        return
    endif
    unlet s:timer_info[a:timer]
    unlet s:timer_by_bufnr[timer_info.bufnr]

    if !bufexists(timer_info.bufnr)
        call s:debug_log(printf('buffer does not exist anymore for timer %d', a:timer),
                    \ {'bufnr': timer_info.bufnr})
        return
    endif

    call s:debug_log(printf('callback for timer %d (via %s)', string(a:timer), timer_info.event),
          \ {'bufnr': timer_info.bufnr})

    let bufnr = bufnr('%')
    if timer_info.bufnr != bufnr
        call s:debug_log(printf('buffer changed: %d => %d',
              \ timer_info.bufnr, bufnr))
        return
    endif

    " Check disabled ft here for BufWinEnter, since &ft might not be defined
    " before (startify).
    if timer_info.event ==# 'BufWinEnter' && s:disabled_for_ft(timer_info.bufnr)
        return
    endif

    " Verify context/position is the same.
    " TODO: only makes sense for some events, e.g. not for
    "       BufWritePost/BufWinEnter?!
    " if timer_info.event !=# 'BufWritePost'
    if !empty(timer_info.pos)
        let current_context = [getpos('.'), mode()]
        if current_context != timer_info.pos
            call s:debug_log(printf('context/position changed: %s => %s',
                        \ string(timer_info.pos), string(current_context)))
            " Restart timer.
            if !empty(timer_info.pos)
                let timer_info.pos = [getpos('.'), mode()]
            endif
            call s:neomake_do_automake(timer_info)
            return
        endif
    endif
    " endif
    let context = copy(timer_info)
    let context.delay = 0
    call s:neomake_do_automake(context)
endfunction

function! s:parse_events_from_args(config, ...) abort
    if !a:0
        return
    endif

    if a:0 > 1
        if has('timers')
            let delay = a:2
        else
            call neomake#utils#QuietMessage('automake: timer support is required for delayed events.')
            let delay = 0
        endif
    else
        let delay = s:default_delay
    endif

    if type(a:1) == type({})
        let events = copy(a:1)

        " Validate events.
        for [event, config] in items(events)
            if !exists('##'.event)
                call neomake#utils#ErrorMessage(printf(
                            \ 'automake: event %s does not exist.', event))
                unlet events[event]
                continue
            endif

            if get(config, 'delay', 0) && !has('timers')
                call neomake#utils#ErrorMessage(printf(
                            \ 'automake: timer support is required for automaking, removing event %s.',
                            \ event))
                unlet events[event]
            endif
        endfor
        call neomake#config#set_dict(a:config, 'automake.events', events)
        if a:0 > 1
            let a:config.automake_delay = a:2
        endif
    else
        " Map string config to events dict.
        let modes = a:1
        let events = {}
        let default_with_delay = {}

        " Insert mode.
        if modes =~# 'i'
            if exists('##TextChangedI') && has('timers')
                let events['TextChangedI'] = default_with_delay
            else
                call s:debug_log('using CursorHoldI instead of TextChangedI')
                let events['CursorHoldI'] = (delay != 0 ? {'delay': 0} : {})
            endif
        endif
        " Normal mode.
        if modes =~# 'n'
            if exists('##TextChanged') && has('timers')
                let events['TextChanged'] = default_with_delay
                if !has_key(events, 'TextChangedI')
                    " Run when leaving insert mode, since only TextChangedI would be triggered
                    " for `ciw` etc.
                    " let events['InsertLeave'] = {'delay': 0}
                    let events['InsertLeave'] = default_with_delay
                endif
            else
                call s:debug_log('using CursorHold instead of TextChanged')
                let events['CursorHold'] = (delay != 0 ? {'delay': 0} : {})
                let events['InsertLeave'] = (delay != 0 ? {'delay': 0} : {})
            endif
        endif
        " On writes.
        if modes =~# 'w'
            let events['BufWritePost'] = (delay != 0 ? {'delay': 0} : {})
        endif
        " On reads.
        if modes =~# 'r'
            let events['BufWinEnter'] = {}
            let events['FileType'] = {}

            " When a file was changed outside of Vim.
            " TODO: test
            let events['FileChangedShellPost'] = {}
            " XXX: FileType might work better, at least when wanting to skip filetypes.
            " let events['FileType'] = {'delay': a:0 > 1 ? delay : 0}
        endif
    endif

    call neomake#config#set_dict(a:config, 'automake.events', events)
    if a:0 > 1
        let a:config.automake_delay = delay
    endif
    if a:0 > 2
        let options = a:3
        if type(options) == type([])
            let a:config.enabled_makers = options
        elseif has_key(options, 'enabled_makers')
            let a:config.enabled_makers = options.enabled_makers
        endif
    endif
endfunction

" Setup automake for buffer (current, or options.bufnr).
" a:1: string or dict describing the events
" a:2: delay
" a:3: options ('bufnr', 'makers') / or list of makers  TODO
function! neomake#configure#automake_for_buffer(...) abort
    let options = a:0 > 2 ? a:3 : {}
    if type(options) == type([])
        let options = {'enabled_makers': options}
    endif
    if has_key(options, 'bufnr')
        let bufnr = options.bufnr
        unlet options.bufnr
    else
        let bufnr = bufnr('%')
    endif
    call setbufvar(bufnr, 'neomake_automake_tick', [])
    return call('s:configure_buffer', [bufnr] + a:000)
endfunction

" Workaround for getbufvar not having support for defaults.
function! s:getbufvar(bufnr, name, default) abort
    let b_dict = getbufvar(+a:bufnr, '')
    if empty(b_dict)
        " NOTE: it is an empty string for non-existing buffers.
        return a:default
    endif
    return get(b_dict, a:name, a:default)
endfunction

" a:1: string or dict describing the events
" a:2: delay
" a:3: options ('enabled_makers')  TODO: test
function! s:configure_buffer(bufnr, ...) abort
    let bufnr = +a:bufnr
    let ft = getbufvar(bufnr, '&filetype')
    let config = s:getbufvar(bufnr, 'neomake', {})
    if a:0
        call call('s:parse_events_from_args', [config] + a:000)
        call setbufvar(bufnr, 'neomake', config)
    endif

    " Register the buffer, and remember if it is custom.
    let s:configured_buffers[bufnr] = {'custom': a:0 > 0}

    " Set enabled_makers.
    let options = a:0 > 2 ? a:3 : {}
    if has_key(config, 'enabled_makers')  " TODO: only "makers"?!
        let enabled_makers = config.enabled_makers
        let source = 'options'
    else
        let [enabled_makers, source] = neomake#config#get_with_source('automake.enabled_makers', neomake#GetEnabledMakers(ft))
    endif
    let s:configured_buffers[bufnr].enabled_makers = enabled_makers
    call s:debug_log(printf('configured buffer for ft=%s (%s)',
                \ ft, empty(enabled_makers) ? 'no enabled makers' : join(map(copy(enabled_makers), "type(v:val) == type('') ? v:val : v:val.name"), ', ').' ('.source.')'), {'bufnr': bufnr})

    " if a:0 && !empty(enabled_makers)
    if a:0
      " Setup autocommands etc (when called manually)?!
      call neomake#configure#automake()
    endif
    return config
endfunction

function! s:disabled_for_ft(bufnr, ...) abort
    let bufnr = +a:bufnr
    let ft = getbufvar(bufnr, '&filetype')
    if index(neomake#config#get('automake.ignore_filetypes', []), ft) != -1
        if a:0
            call s:debug_log(printf('%s: skipping setup for filetype=%s', a:1, ft),
                        \ {'bufnr': bufnr})
        else
            call s:debug_log(printf('skipping callback for filetype=%s', ft),
                        \ {'bufnr': bufnr})
        endif
        return 1
    endif
    return 0
endfunction

" Called from autocommands.
function! s:neomake_automake(event, bufnr) abort
    let bufnr = +a:bufnr

    " TODO: blacklist/whitelist.
    " TODO: after/only for configured buffers?!
    let buftype = getbufvar(bufnr, '&buftype')
    if !empty(buftype)
        " TODO: test
        call s:debug_log(printf('ignoring %s for buftype=%s', a:event, buftype),
                    \ {'bufnr': bufnr})
        return
    endif

    " NOTE: Do it later for BufWinEnter again, since &ft might not be defined (startify).
    if s:disabled_for_ft(bufnr, a:event)
        return
    endif

    if !has_key(s:configured_buffers, bufnr)
        " register the buffer, and remember that it's automatic.
        call s:configure_buffer(bufnr)
    endif
    let enabled_makers = s:configured_buffers[bufnr].enabled_makers
    if empty(enabled_makers)
        return
    endif

    call s:debug_log(printf('automake for event %s', a:event), {'bufnr': bufnr})
    let config = neomake#config#get('automake.events', {})
    if !has_key(config, a:event)
        call s:debug_log('event is not registered', {'bufnr': bufnr})
        return
    endif
    let config = config[a:event]

    let event = a:event
    let bufnr = +a:bufnr
    " TODO: rename to neomake.automake.delay
    let delay = get(config, 'delay', s:get_setting('automake_delay', s:default_delay))
    let context = {
                \ 'delay': delay,
                \ 'bufnr': bufnr,
                \ 'event': a:event,
                \ 'enabled_makers': enabled_makers,
                \ }
    if event ==# 'BufWinEnter'
        " Ignore context, so that e.g. with vim-stay restoring the view
        " (cursor position), it will still be triggered.
        let context.pos = []
    endif
    call s:neomake_do_automake(context)
endfunction

function! neomake#configure#reset_automake() abort
    let s:configured_buffers = {}
    let s:registered_events = []
endfunction

function! s:neomake_automake_clean(bufnr) abort
    if has_key(s:timer_by_bufnr, a:bufnr)
        let timer = s:timer_by_bufnr[a:bufnr]
        call s:debug_log('automake: cleaning timer for wiped buffer: '.timer)
        unlet s:timer_info[timer]
        unlet s:timer_by_bufnr[a:bufnr]
        call timer_stop(timer)
    endif
endfunction

function! neomake#configure#automake(...) abort
    if !exists('g:neomake')
        let g:neomake = {}
    endif
    if a:0
        call call('s:parse_events_from_args', [g:neomake] + a:000)
    endif

    " Keep custom configured buffers.
    call filter(s:configured_buffers, 'v:val.custom')
    let s:registered_events = keys(get(get(g:neomake, 'automake', {}), 'events', {}))
    for b in keys(s:configured_buffers)
        if empty(s:configured_buffers[b].enabled_makers)
            continue
        endif
        let b_cfg = neomake#config#get('b:automake.events', {})
        for event_config in items(b_cfg)
            let event = event_config[0]
            if index(s:registered_events, event) == -1
                call add(s:registered_events, event)
            endif
        endfor
    endfor
    call s:debug_log('registered events: '.join(s:registered_events, ', '))

    augroup neomake_automake
        au!
        autocmd BufWipeout * call s:neomake_automake_clean(expand('<abuf>'))
        for event in s:registered_events
            exe 'autocmd '.event." * call s:neomake_automake('".event."', expand('<abuf>'))"
        endfor
    augroup END
    augroup neomake_automake_update
        au!
        autocmd FileType * call s:configure_buffer(expand('<abuf>'))
    augroup END
endfunction
