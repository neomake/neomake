" Fix/ignore an error.
" a:action: "fix" or "ignore"
function! neomake#fix#current(action) abort
    let error = neomake#get_nearest_error()
    if empty(error)
        call neomake#log#error('No error found.')
        return
    endif
    call neomake#fix#entry(a:action, error)
endfunction

function! neomake#fix#entry(action, entry) abort
    let error = a:entry
    let bufnr = bufnr('%')

    if !bufexists(a:entry.bufnr)
        call neomake#log#error(printf('Cannot fix non-existing buffer %s.', a:entry.bufnr))
        return
    endif

    if bufnr != a:entry.bufnr && !exists('*nvim_buf_set_lines')
        if !has_key(s:delayed_fixes, a:entry.bufnr)
            let s:delayed_fixes[a:entry.bufnr] = []

            augroup neomake_fix
                exe printf('autocmd BufEnter,WinEnter <buffer=%d> call s:apply_delayed_fixes(%d)', a:entry.bufnr, a:entry.bufnr)
                exe printf('autocmd BufWipeout <buffer=%d> call s:clear_delayed_fixes(%d)', a:entry.bufnr, a:entry.bufnr)
            augroup END
        endif
        call neomake#log#debug('Delaying fixing.', {'bufnr': a:entry.bufnr})

        call add(s:delayed_fixes[a:entry.bufnr], [a:action, a:entry])
        return
    endif

    if has_key(a:entry, 'maker')
        let maker = a:entry.maker
    else
        let maker = neomake#GetMaker(error.maker_name, getbufvar(a:entry.bufnr, '&ft'))
    endif
    if !has_key(maker, 'fix_entry')
        call neomake#log#error(printf('Maker %s does not have a fix_entry method.', maker.name))
        return
    endif

    let fixed = maker.fix_entry(error, a:action)
    if empty(fixed)
        " XXX: should provide feedback always, but also log it?!
        call neomake#log#info('No fix found.')
        echom 'No fix found.'
        return
    endif

    let fixed_something = 0
    for fix in fixed
        let action = fix[0]
        let args = fix[1:]

        " if action ==# 'setline'
        "     let [lnum, new] = args
        "     let old = getline(lnum)
        "     if old ==# new
        "         call neomake#log#warn('fix did not change line.')
        "         continue
        "     endif
        "     call neomake#log#info(printf('%s: fixed %s => %s (line %d).', maker.name, string(old), string(new), lnum), {'bufnr': a:entry.bufnr})
        "     call setline(lnum, new)

        if action ==# 'setlines'
            let [start, end, replacement] = args
            call neomake#log#info(printf('%s: fix: replacing lines %d-%d with %d lines.', maker.name, start, end, len(replacement)), {'bufnr': a:entry.bufnr})

            " Check bounds.
            if start > end
                call neomake#log#error('Fixing entry failed: start is higher than end.')
                continue
            elseif start < 1
                call neomake#log#error('Fixing entry failed: start is less than 1.')
                continue
            endif

            if start == end
                call neomake#log#info(printf('%s: fix: adding %d lines before line %d.', maker.name, len(replacement), start), {'bufnr': a:entry.bufnr})
            elseif start == end - 1 && len(replacement) == 1
                if exists('*nvim_buf_get_lines')
                    let old = nvim_buf_get_lines(a:entry.bufnr, start-1, end-1, 1)[0]
                else
                    let old = getline(start)
                endif
                call neomake#log#info(printf('%s: fixed %s => %s (line %d).', maker.name, string(old), string(replacement[0]), start), {'bufnr': a:entry.bufnr})
            endif

            let err = neomake#utils#buf_set_lines(a:entry.bufnr, start, end, replacement)
            if !empty(err)
                call neomake#log#error(printf('Fixing entry failed: %s.', err))
                continue
            endif

            let fixed_something = 1

        " elseif action ==# 'append'
        "     let [lnum, lines] = args
        "     call neomake#log#info(printf('%s: fix: appending %d lines after line %d.', maker.name, len(lines), lnum), {'bufnr': a:entry.bufnr})
        "     call append(lnum, lines)


        " TODO: wrap into compat functions(s), and refactor.
        " Related: https://github.com/neomake/neomake/pull/1776
        elseif action ==# 'append_to_line'
            let [lnum, append] = args
            let old = neomake#utils#buf_get_lines(a:entry.bufnr, lnum, lnum+1)[0]
            let new = old . append

            call neomake#log#info(printf('%s: fixing %s => %s (line %d).', maker.name, string(old), string(new), lnum), {'bufnr': a:entry.bufnr})

            if exists('*nvim_buf_get_lines')
                call nvim_buf_set_lines(a:entry.bufnr, lnum-1, lnum, 1, [new])
            else
                call setline(lnum, new)
            endif

            let fixed_something = 1

        else
            throw 'Neomake: unknown fixer action: '.action
        endif
    endfor
    return fixed_something
endfunction


let s:delayed_fixes = {}

function! s:apply_delayed_fixes(bufnr) abort
    let fixes = s:delayed_fixes[a:bufnr]
    call neomake#log#debug(printf('Applying %d delayed fixes.', len(fixes)), {'bufnr': a:bufnr})
    while !empty(fixes)
        let [action, entry] = remove(fixes, 0)
        call neomake#fix#entry(action, entry)
    endwhile
    call s:clear_delayed_fixes(a:bufnr)
endfunction

function! s:clear_delayed_fixes(bufnr) abort
    unlet s:delayed_fixes[a:bufnr]
    augroup neomake_fix
        exe 'autocmd! * <buffer>'
    augroup END
endfunction
" vim: ts=4 sw=4 et
