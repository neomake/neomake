" Create a List object from a quickfix/location list.
" TODO: (optionally?) add entries sorted?  (errors first, grouped by makers (?) etc)

let s:use_efm_parsing = has('patch-8.0.1040')  " 'efm' in setqflist/getqflist

function! neomake#list#ListForMake(make_info) abort
    let type = a:make_info.options.file_mode ? 'loclist' : 'quickfix'
    let list = neomake#list#List(type)
    let list.make_info = a:make_info
    if type ==# 'loclist'
        let info = get(w:, '_neomake_info', {})
        let info['loclist'] = list
        let w:_neomake_info = info
    else
        let info = get(g:, '_neomake_info', {})
        let info['qflist'] = list
        let g:_neomake_info = info
    endif
    return list
endfunction

" a:type: "loclist" or "quickfix"
function! neomake#list#List(type) abort
    let list = deepcopy(s:base_list)
    let list.type = a:type
    if a:type ==# 'loclist'
        if exists('*win_getid')
            let list.winid = win_getid()
        endif
    endif
    " Display debug messages about changed entries.
    let list.debug = exists('g:neomake_test_messages')
                \ || !empty(get(g:, 'neomake_logfile'))
                \ || neomake#utils#get_verbosity() >= 3
    return list
endfunction

" Internal base list implementation.
let s:base_list = {
            \ 'need_init': 1,
            \ 'entries': [],
            \ }

" Do we need to replace (instead of append) the location/quickfix list, for
" :lwindow to not open it with only invalid entries?!
" Without patch-7.4.379 this does not work though, and a new list needs to
" be created (which is not done).
" @vimlint(EVL108, 1)
let s:needs_to_replace_qf_for_lwindow = has('patch-7.4.379')
            \ && (!has('patch-7.4.1752') || (has('nvim') && !has('nvim-0.2.0')))
" https://github.com/vim/vim/issues/3633
" See tests/lists.vader for patch-7.4.379.
let s:needs_to_init_qf_for_lwindow = 1
" @vimlint(EVL108, 0)

function! s:base_list.sort_by_location() dict abort
    let entries = get(self, '_sorted_entries_by_location', copy(self.entries))
    let self._sorted_entries_by_location = sort(entries, 's:cmp_listitem_loc')
    return self._sorted_entries_by_location
endfunction

" a:1: start index of entries in the location/quickfix list.
function! s:base_list.add_entries(entries, ...) dict abort
    let idx = a:0 ? a:1 : len(self.entries)+1
    for entry in a:entries
        call add(self.entries, extend(copy(entry), {'nmqfidx': idx}))
        let idx += 1
    endfor
    if self.debug
        let indexes = map(copy(self.entries), 'v:val.nmqfidx')
        if len(neomake#compat#uniq(sort(copy(indexes)))) != len(indexes)
            call neomake#log#error(printf('Duplicate qf indexes in list entries: %s.',
                        \ string(indexes)))
        endif
    endif
    " Sort if it was sorted before.
    if has_key(self, '_sorted_entries_by_location')
        call extend(self._sorted_entries_by_location, a:entries)
        call self.sort_by_location()
    endif
endfunction

" Add entries for a job (non-efm method).
function! s:base_list.add_entries_for_job(entries, jobinfo) dict abort
    return self._appendlist(a:entries, a:jobinfo)
endfunction

" Append entries to location/quickfix list.
function! s:base_list._appendlist(entries, jobinfo) abort
    call neomake#log#debug(printf('Adding %d list entries.', len(a:entries)))

    let loclist_win = 0
    if self.type ==# 'loclist'
        " NOTE: prefers using 0 for when winid is not supported with
        " setloclist() yet (vim74-xenial).
        if index(get(w:, 'neomake_make_ids', []), a:jobinfo.make_id) == -1
            if has_key(self, 'winid')
                let loclist_win = self.winid
            else
                let [t, w] = neomake#core#get_tabwin_for_makeid(a:jobinfo.make_id)
                if [t, w] == [-1, -1]
                    throw printf('Neomake: could not find location list for make_id %d.', a:jobinfo.make_id)
                endif
                if t != tabpagenr()
                    throw printf('Neomake: trying to use location list from another tab (current=%d != target=%d).', tabpagenr(), t)
                endif
                let loclist_win = w
            endif
        endif
    endif

    let set_entries = a:entries
    if self.need_init
        let action = ' '
        let self.need_init = 0

        if self.type ==# 'loclist'
            call neomake#log#debug('Creating location list.', self.make_info)
            if s:needs_to_init_qf_for_lwindow
                call setloclist(0, [])
                let action = 'a'
            endif
        else
            call neomake#log#debug('Creating quickfix list.', self.make_info)
            if s:needs_to_init_qf_for_lwindow
                call setqflist([])
                let action = 'a'
            endif
        endif
    else
        if s:needs_to_replace_qf_for_lwindow
            let action = 'r'
            if self.type ==# 'loclist'
                let set_entries = getloclist(loclist_win) + set_entries
            else
                let set_entries = getqflist() + set_entries
            endif
        else
            let action = 'a'
        endif
    endif

    " Add marker for custom quickfix to the first (new) entry.
    let needs_custom_qf_marker = neomake#quickfix#is_enabled()
    if needs_custom_qf_marker
        if action ==# 'a'
            let prev_idx = 0
        else
            let prev_idx = len(self.entries)
        endif
        let maker_name = a:jobinfo.maker.name
        let config = {
                    \ 'name': maker_name,
                    \ 'short': get(a:jobinfo.maker, 'short_name', maker_name[:3]),
                    \ }
        let set_entries = copy(set_entries)
        let marker_entry = copy(set_entries[prev_idx])
        let marker_entry.text .= printf(' nmcfg:%s', string(config))
        let set_entries[prev_idx] = marker_entry
    endif

    " NOTE: need to fetch (or pre-parse with new patch) to get updated bufnr etc.
    if self.type ==# 'loclist'
        call setloclist(loclist_win, set_entries, action)
        let added = getloclist(loclist_win)[len(self.entries) :]
    else
        call setqflist(set_entries, action)
        let added = getqflist()[len(self.entries) :]
    endif

    if needs_custom_qf_marker
        " Remove marker that should only be in the quickfix list.
        let added[0].text = substitute(added[0].text, ' nmcfg:{.\{-}}$', '', '')
    endif

    if self.debug
    if added != a:entries
        let diff = neomake#list#_diff_new_entries(a:entries, added)
        if !empty(diff)
            for [k, v] in items(diff)
                " TODO: if debug
                " TODO: handle valid=1 being added?
                call neomake#log#debug(printf(
                  \ 'Entry %d differs after adding: %s.',
                  \ k+1,
                  \ string(v)),
                  \ a:jobinfo)
            endfor
        endif
    endif
    endif

    let parsed_entries = copy(a:entries)
    let idx = 0
    for e in added
        if parsed_entries[idx].bufnr != e.bufnr
            call neomake#log#debug(printf(
                        \ 'Updating entry bufnr: %s => %s.',
                        \ a:entries[idx].bufnr, e.bufnr))
            let parsed_entries[idx].bufnr = e.bufnr
        endif
        let idx += 1
    endfor

    call self.add_entries(parsed_entries)
    return parsed_entries
endfunction

function! neomake#list#_diff_new_entries(orig, new) abort
    if a:orig == a:new
        return {}
    endif
    let i = 0
    let r = {}
    for new in a:new
        let orig = copy(get(a:orig, i, {}))
        for [k, v] in items({'pattern': '', 'module': '', 'valid': 1})
            if has_key(new, k)
                let orig[k] = v
            endif
        endfor
        if new != orig
            " 'removed': {'length': 4, 'filename': 'from.rs',
            " 'maker_name': 'cargo'}}
            let new = copy(new)
            for k in ['length', 'maker_name']
                if has_key(orig, k)
                    let new[k] = orig[k]
                endif
            endfor
            let diff = neomake#utils#diff_dict(orig, new)
            if !empty(diff)
                let r[i] = diff
            endif
        endif
        let i += 1
    endfor
    return r
endfunction

" Add raw lines using errorformat.
" This either pre-parses them with newer versions, or uses
" :laddexpr/:caddexpr.
function! s:base_list.add_lines_with_efm(lines, jobinfo) dict abort
    let maker = a:jobinfo.maker
    let file_mode = self.type ==# 'loclist'
    if s:use_efm_parsing
        let efm = a:jobinfo.maker.errorformat
        let parsed_entries = getqflist({'lines': a:lines, 'efm': efm}).items
    else
        if self.need_init
            let self.need_init = 0
            if self.type ==# 'loclist'
                call neomake#log#debug('Creating location list.', self.make_info)
                call setloclist(0, [])
            else
                call neomake#log#debug('Creating quickfix list.', self.make_info)
                call setqflist([])
            endif
        endif

        let olderrformat = &errorformat
        let &errorformat = maker.errorformat
        try
            if file_mode
                let cmd = 'laddexpr'
            else
                let cmd = 'caddexpr'
            endif
            exe 'noautocmd '.cmd.' a:lines'
            let a:jobinfo._delayed_qf_autocmd = 'QuickfixCmdPost '.cmd
        finally
            let &errorformat = olderrformat
            call a:jobinfo.cd_back()
        endtry

        let new_list = file_mode ? getloclist(0) : getqflist()
        let parsed_entries = new_list[len(self.entries) :]
    endif
    if empty(parsed_entries)
        return []
    endif

    let Postprocess = neomake#utils#GetSetting('postprocess', maker, [], a:jobinfo.ft, a:jobinfo.bufnr)
    if type(Postprocess) != type([])
        let postprocessors = [Postprocess]
    else
        let postprocessors = Postprocess
    endif

    let maker_name = maker.name
    let default_type = 'unset'

    let entries = []
    let changed_entries = {}
    let removed_entries = []
    let different_bufnrs = {}
    let bufnr_from_temp = {}
    let bufnr_from_stdin = {}
    let tempfile_bufnrs = has_key(self.make_info, 'tempfiles') ? map(copy(self.make_info.tempfiles), 'bufnr(v:val)') : []
    let uses_stdin = get(a:jobinfo, 'uses_stdin', 0)

    let entry_idx = -1
    for entry in parsed_entries
        let entry_idx += 1
        let before = copy(entry)
        " Handle unlisted buffers via tempfiles and uses_stdin.
        if file_mode && entry.bufnr && entry.bufnr != a:jobinfo.bufnr
                    \ && (!empty(tempfile_bufnrs) || uses_stdin)
            let map_bufnr = index(tempfile_bufnrs, entry.bufnr)
            if map_bufnr != -1
                let entry.bufnr = a:jobinfo.bufnr
                let map_bufnr = tempfile_bufnrs[map_bufnr]
                if !has_key(bufnr_from_temp, map_bufnr)
                    let bufnr_from_temp[map_bufnr] = []
                endif
                let bufnr_from_temp[map_bufnr] += [entry_idx+1]
            elseif uses_stdin
                if !buflisted(entry.bufnr) && bufexists(entry.bufnr)
                    if !has_key(bufnr_from_stdin, entry.bufnr)
                        let bufnr_from_stdin[entry.bufnr] = []
                    endif
                    let bufnr_from_stdin[entry.bufnr] += [entry_idx+1]
                    let entry.bufnr = a:jobinfo.bufnr
                endif
            endif
        endif
        if self.debug && entry.bufnr && entry.bufnr != a:jobinfo.bufnr
            if !has_key(different_bufnrs, entry.bufnr)
                let different_bufnrs[entry.bufnr] = 1
            else
                let different_bufnrs[entry.bufnr] += 1
            endif
        endif
        if !empty(postprocessors)
            let g:neomake_postprocess_context = {'jobinfo': a:jobinfo}
            try
                for F in postprocessors
                    if type(F) == type({})
                        call call(F.fn, [entry], F)
                    else
                        call call(F, [entry], maker)
                    endif
                    unlet! F  " vim73
                endfor
            finally
                unlet! g:neomake_postprocess_context  " Might be unset already with sleep in postprocess.
            endtry
        endif
        if entry != before
            let changed_entries[entry_idx] = entry
            if self.debug
                call neomake#log#debug(printf(
                  \ 'Modified list entry %d (postprocess): %s.',
                  \ entry_idx + 1,
                  \ substitute(string(neomake#utils#diff_dict(before, entry)), '\n', '\\n', 'g')),
                  \ a:jobinfo)
            endif
        endif

        if entry.valid <= 0
            if entry.valid < 0 || maker.remove_invalid_entries
                call insert(removed_entries, entry_idx)
                let entry_copy = copy(entry)
                call neomake#log#debug(printf(
                            \ 'Removing invalid entry: %s (%s).',
                            \ remove(entry_copy, 'text'),
                            \ string(entry_copy)), a:jobinfo)
                continue
            endif
        endif

        if empty(entry.type) && entry.valid
            if default_type ==# 'unset'
                let default_type = neomake#utils#GetSetting('default_entry_type', maker, 'W', a:jobinfo.ft, a:jobinfo.bufnr)
            endif
            if !empty(default_type)
                let entry.type = default_type
                let changed_entries[entry_idx] = entry
            endif
        endif
        call add(entries, entry)
    endfor

    if !s:use_efm_parsing
        let prev_index = len(self.entries)
        " Add marker for custom quickfix to the first (new) entry.
        if neomake#quickfix#is_enabled()
            let config = {
                        \ 'name': maker_name,
                        \ 'short': get(a:jobinfo.maker, 'short_name', maker_name[:3]),
                        \ }
            let marker_entry = copy(entries[0])
            let marker_entry.text .= printf(' nmcfg:%s', string(config))
            let changed_entries[prev_index] = marker_entry
        endif

        if !empty(changed_entries) || !empty(removed_entries)
            " Need to update/replace current list.
            let list = file_mode ? getloclist(0) : getqflist()
            if !empty(changed_entries)
                for k in keys(changed_entries)
                    let list[prev_index + k] = changed_entries[k]
                endfor
            endif
            if !empty(removed_entries)
                for k in removed_entries
                    call remove(list, prev_index + k)
                endfor
            endif
            if file_mode
                call setloclist(0, list, 'r')
            else
                call setqflist(list, 'r')
            endif
        endif
    endif

    if !empty(bufnr_from_temp) || !empty(bufnr_from_stdin)
        if !has_key(self.make_info, '_wipe_unlisted_buffers')
            let self.make_info._wipe_unlisted_buffers = []
        endif
        let self.make_info._wipe_unlisted_buffers += keys(bufnr_from_stdin) + keys(bufnr_from_stdin)
        if !empty(bufnr_from_temp)
            for [tempbuf, entries_idx] in items(bufnr_from_temp)
                call neomake#log#debug(printf(
                            \ 'Used bufnr from temporary buffer %d (%s) for %d entries: %s.',
                            \ tempbuf,
                            \ bufname(+tempbuf),
                            \ len(entries_idx),
                            \ join(entries_idx, ', ')), a:jobinfo)
            endfor
        endif
        if !empty(bufnr_from_stdin)
            for [tempbuf, entries_idx] in items(bufnr_from_stdin)
                call neomake#log#debug(printf(
                            \ 'Used bufnr from stdin buffer %d (%s) for %d entries: %s.',
                            \ tempbuf,
                            \ bufname(+tempbuf),
                            \ len(entries_idx),
                            \ join(entries_idx, ', ')), a:jobinfo)
            endfor
        endif
    endif
    if !empty(different_bufnrs)
        call neomake#log#debug(printf('WARN: seen entries with bufnr different from jobinfo.bufnr (%d): %s, current bufnr: %d.', a:jobinfo.bufnr, string(different_bufnrs), bufnr('%')))
    endif

    if empty(entries)
        return []
    endif

    if s:use_efm_parsing
        call self._appendlist(entries, a:jobinfo)
    else
        call self.add_entries(entries)
    endif
    return entries
endfunction

" Get the current location or quickfix list.
function! neomake#list#get() abort
    let winnr = winnr()
    let win_info = getwinvar(winnr, '_neomake_info', {})
    if has_key(win_info, 'loclist')
        return win_info['loclist']
    endif
    let info = get(g:, '_neomake_info', {})
    if has_key(info, 'qflist')
        return info['qflist']
    endif
    return {}
endfunction

function! neomake#list#get_loclist(...) abort
    let winnr = a:0 ? a:1 : winnr()
    let info = neomake#compat#getwinvar(winnr, '_neomake_info', {})
    if !has_key(info, 'loclist')
        " Create a new list, not bound to a job.
        call neomake#log#debug('Creating new List object.')
        let list = neomake#list#List('loclist')
        call list.add_entries(getloclist(winnr))
        let info['loclist'] = list
        call setwinvar(winnr, '_neomake_info', info)
    endif
    return info['loclist']
endfunction

" TODO: save project-maker quickfix list.
function! neomake#list#get_qflist() abort
    let info = get(g:, '_neomake_info', {})
    if !has_key(info, 'qflist')
        " Create a new list, not bound to a job.
        call neomake#log#debug('Creating new List object.')
        let list = neomake#list#List('quickfix')
        call list.add_entries(getqflist())
        let info['qflist'] = list
        let g:_neomake_info = info
    endif
    return info['qflist']
endfunction

function! s:get_list(file_mode) abort
    if a:file_mode
        let list = neomake#list#get_loclist()
        let g:unimpaired_prevnext = ['NeomakePrevLoclist', 'NeomakeNextLoclist']
    else
        let list = neomake#list#get_qflist()
        let g:unimpaired_prevnext = ['NeomakePrevQuickfix', 'NeomakeNextQuickfix']
    endif
    return list
endfunction

function! neomake#list#next(c, ...) abort
    let file_mode = a:0 ? a:1 : 1
    let list = s:get_list(file_mode)
    call s:goto_nearest(list, a:c == 0 ? 1 : a:c)
endfunction

function! neomake#list#prev(c, ...) abort
    let file_mode = a:0 ? a:1 : 1
    let list = s:get_list(file_mode)
    call s:goto_nearest(list, a:c == 0 ? -1 : -a:c)
endfunction

" TODO: global / already used somewhere else? / config
let g:neomake#list#type_prio = {
            \ 'E': 0,
            \ 'W': 1,
            \ 'I': 2,
            \ }

" TODO: allow to customize via own callback(s)?
function! s:cmp_listitem_loc(a, b) abort
    let buf_diff = a:a.bufnr - a:b.bufnr
    if buf_diff
        return buf_diff
    endif

    if exists(':Assert')
        Assert a:a.bufnr != -1
        Assert a:b.bufnr != -1
    endif

    let lnum_diff = a:a.lnum - a:b.lnum
    if lnum_diff
        return lnum_diff
    endif

    let col_diff = a:a.col - a:b.col
    if col_diff
        return col_diff
    endif

    let prio = g:neomake#list#type_prio
    return get(prio, a:a.type, 99) - get(prio, a:b.type, 99)
endfunction

function! s:goto_nearest(list, offset) abort
    let [lnum, col] = getpos('.')[1:2]
    if a:offset == 0
        throw 'a:offset must not be 0'
    endif

    if !has_key(a:list, '_sorted_entries_by_location')
        call a:list.sort_by_location()
    endif
    let entries = a:list._sorted_entries_by_location
    if a:offset < 0
        call reverse(entries)
    endif

    let c = a:offset
    let step = a:offset > 0 ? 1 : -1
    let found = 0
    for item in entries
        if (a:offset > 0 && (item.lnum > lnum || (item.lnum == lnum && item.col > col)))
                    \ || (a:offset < 0 && (item.lnum < lnum || (item.lnum == lnum && item.col < col)))
            let c -= step
            let found = item.nmqfidx
            if c == 0
                break
            endif
        endif
    endfor

    if found
        if a:list.type ==# 'loclist'
            if exists(':AssertEqual')
                " @vimlint(EVL102, 1, l:ll_item)
                let ll_item = getloclist(0)[found-1]
                AssertEqual [ll_item.bufnr, ll_item.lnum], [item.bufnr, item.lnum]
            endif
            execute 'll '.found
        else
            if exists(':AssertEqual')
                " @vimlint(EVL102, 1, l:cc_item)
                let cc_item = getqflist()[found-1]
                AssertEqual [cc_item.bufnr, cc_item.lnum], [item.bufnr, item.lnum]
            endif
            execute 'cc '.found
        endif
    elseif c > 0
        call neomake#log#error('No more next items.')
    elseif c < 0
        call neomake#log#error('No more previous items.')
    endif
endfunction

" vim: ts=4 sw=4 et
