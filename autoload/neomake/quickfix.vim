" vim: ts=4 sw=4 et
scriptencoding utf-8

let s:is_enabled = 0

let s:match_base_priority = 10

" args: a:1: force enabling?  (used in tests and for VimEnter callback)
function! neomake#quickfix#enable(...) abort
    if has('vim_starting') && !(a:0 && a:1)
        " Delay enabling for our FileType autocommand to happen as late as
        " possible, since placing signs triggers a redraw, and together with
        " vim-qf_resize this causes flicker.
        " https://github.com/vim/vim/issues/2763
        augroup neomake_qf
            autocmd!
            autocmd VimEnter * call neomake#quickfix#enable(1)
        augroup END
        return
    endif
    let s:is_enabled = 1
    augroup neomake_qf
        autocmd!
        autocmd FileType qf call neomake#quickfix#FormatQuickfix()
    augroup END
    if &filetype ==# 'qf'
        call neomake#quickfix#FormatQuickfix()
    endif
endfunction


function! neomake#quickfix#disable() abort
    let s:is_enabled = 0
    if &filetype ==# 'qf'
        call neomake#quickfix#FormatQuickfix()
    endif
    if exists('#neomake_qf')
        autocmd! neomake_qf
        augroup! neomake_qf
    endif
endfunction


function! neomake#quickfix#is_enabled() abort
    return s:is_enabled
endfunction


function! s:cursor_moved() abort
    if b:neomake_start_col
        if col('.') <= b:neomake_start_col + 1
            call cursor(line('.'), b:neomake_start_col + 2)
        endif

        if exists('b:_neomake_cursor_match_id')
            silent! call matchdelete(b:_neomake_cursor_match_id)
        endif
        if exists('*matchaddpos')
            let b:_neomake_cursor_match_id = matchaddpos('neomakeCursorListNr',
                        \ [[line('.'), (b:neomake_start_col - b:neomake_number_len) + 2, b:neomake_number_len]],
                        \ s:match_base_priority+3)
        else
            let b:_neomake_cursor_match_id = matchadd('neomakeCursorListNr',
                        \  '\%' . line('.') . 'c'
                        \. '\%' . ((b:neomake_start_col - b:neomake_number_len) + 2) . 'c'
                        \. '.\{' . b:neomake_number_len . '}',
                        \ s:match_base_priority+3)
        endif
    endif
endfunction


function! neomake#quickfix#set_syntax(names) abort
    runtime! syntax/neomake/qf.vim
    for name in a:names
        execute 'runtime! syntax/neomake/'.name.'.vim '
                    \  . 'syntax/neomake/'.name.'/*.vim'
    endfor
endfunction

function! s:set_qf_lines(lines) abort
    let ul = &l:undolevels
    setlocal modifiable nonumber undolevels=-1

    call setline(1, a:lines)

    let &l:undolevels = ul
    setlocal nomodifiable nomodified
endfunction

function! s:clean_qf_annotations() abort
    if exists('b:_neomake_qf_orig_lines')
        call s:set_qf_lines(b:_neomake_qf_orig_lines)
        unlet b:_neomake_qf_orig_lines
    endif
    unlet b:neomake_qf
    augroup neomake_qf
        autocmd! * <buffer>
    augroup END

    if exists('b:_neomake_maker_match_id')
        silent! call matchdelete(b:_neomake_maker_match_id)
    endif
    if exists('b:_neomake_gutter_match_id')
        silent! call matchdelete(b:_neomake_gutter_match_id)
    endif
    if exists('b:_neomake_bufname_match_id')
        silent! call matchdelete(b:_neomake_bufname_match_id)
    endif
    if exists('b:_neomake_cursor_match_id')
        silent! call matchdelete(b:_neomake_cursor_match_id)
    endif
    call neomake#signs#ResetFile(bufnr('%'))
endfunction


function! neomake#quickfix#FormatQuickfix() abort
    let buf = bufnr('%')
    if !s:is_enabled || &filetype !=# 'qf'
        if exists('b:neomake_qf')
            call s:clean_qf_annotations()
        endif
        return
    endif

    let src_buf = 0
    if has('patch-7.4.2215')
        let is_loclist = getwininfo(win_getid())[0].loclist
        if is_loclist
            let qflist = getloclist(0)
        else
            let qflist = getqflist()
        endif
    else
        let is_loclist = 1
        let qflist = getloclist(0)
        if empty(qflist)
            let is_loclist = 0
            let qflist = getqflist()
        endif
    endif

    if empty(qflist) || qflist[0].text !~# ' nmcfg:{.\{-}}$'
        if exists('b:neomake_qf')
            call neomake#log#debug('Resetting custom qf for non-Neomake change.')
            call s:clean_qf_annotations()
        endif
        return
    endif

    if is_loclist
        let b:neomake_qf = 'file'
        let src_buf = qflist[0].bufnr
    else
        let b:neomake_qf = 'project'
    endif

    let lines = []
    let signs = []
    let i = 0
    let lnum_width = 0
    let col_width = 0
    let maker_width = 0
    let maker = {}
    let makers = []

    for item in qflist
        " Look for marker at end of entry.
        if item.text[-1:] ==# '}'
            let idx = strridx(item.text, ' nmcfg:{')
            if idx != -1
                let config = item.text[idx+7:]
                try
                    let maker = eval(config)
                    if index(makers, maker.name) == -1
                        call add(makers, maker.name)
                    endif
                    let item.text = idx == 0 ? '' : item.text[:(idx-1)]
                catch
                    call neomake#log#exception(printf(
                                \ 'Error when evaluating nmcfg (%s): %s.',
                                \ config, v:exception))
                endtry
            endif
        endif

        let item.maker_name = get(maker, 'short', '????')
        let maker_width = max([len(item.maker_name), maker_width])

        if item.lnum
            let lnum_width = max([len(item.lnum), lnum_width])
            let col_width = max([len(item.col), col_width])
        endif

        let i += 1
    endfor

    let syntax = copy(makers)
    if src_buf
        for ft in split(neomake#compat#getbufvar(src_buf, '&filetype', ''), '\.')
            if !empty(ft) && index(syntax, ft) == -1
                call add(syntax, ft)
            endif
        endfor
    endif
    call neomake#quickfix#set_syntax(syntax)

    if maker_width + lnum_width + col_width > 0
        let b:neomake_start_col = maker_width + lnum_width + col_width + 2
        let b:neomake_number_len = lnum_width + col_width + 2
        let blank_col = repeat(' ', lnum_width + col_width + 1)
    else
        let b:neomake_start_col = 0
        let b:neomake_number_len = 0
        let blank_col = ''
    endif

    " Count number of different buffers and cache their names.
    let buffers = neomake#compat#uniq(sort(
                \ filter(map(copy(qflist), 'v:val.bufnr'), 'v:val != 0')))
    let buffer_names = {}
    if len(buffers) > 1
        for b in buffers
            let bufname = bufname(b)
            if empty(bufname)
                let bufname = 'buf:'.b
            else
                let bufname = fnamemodify(bufname, ':t')
                if len(bufname) > 15
                    let bufname = bufname[0:13].'…'
                endif
            endif
            let buffer_names[b] = bufname
        endfor
    endif

    let i = 1
    let last_bufnr = -1
    for item in qflist
        if item.lnum
            call add(signs, {'lnum': i, 'bufnr': buf, 'type': item.type})
        endif
        let i += 1

        let text = item.text
        if item.bufnr != 0 && !empty(buffer_names)
            if last_bufnr != item.bufnr
                let text = printf('[%s] %s', buffer_names[item.bufnr], text)
                let last_bufnr = item.bufnr
            endif
        endif

        if !item.lnum
            call add(lines, printf('%*s %s %s',
                        \ maker_width, item.maker_name,
                        \ blank_col, text))
        else
            call add(lines, printf('%*s %*s:%*s %s',
                        \ maker_width, item.maker_name,
                        \ lnum_width, item.lnum,
                        \ col_width, item.col ? item.col : '-',
                        \ text))
        endif
    endfor

    if !exists('b:_neomake_qf_orig_lines')
        let b:_neomake_qf_orig_lines = getbufline('%', 1, '$')
    endif
    call s:set_qf_lines(lines)

    if exists('+breakindent')
        " Keeps the text aligned with the fake gutter.
        setlocal breakindent linebreak
        let &breakindentopt = 'shift:'.(b:neomake_start_col + 1)
    endif

    call neomake#signs#Reset(buf, 'file')
    call neomake#signs#PlaceSigns(buf, signs, 'file')

    if b:neomake_start_col
        if exists('b:_neomake_maker_match_id')
            silent! call matchdelete(b:_neomake_maker_match_id)
        endif
        let b:_neomake_maker_match_id = matchadd('neomakeMakerName',
                    \ '.*\%<'.(maker_width + 1).'c',
                    \ s:match_base_priority+1)
        if exists('b:_neomake_gutter_match_id')
            silent! call matchdelete(b:_neomake_gutter_match_id)
        endif
        let b:_neomake_gutter_match_id = matchadd('neomakeListNr',
                    \ '\%>'.(maker_width).'c'
                    \ .'.*\%<'.(b:neomake_start_col + 2).'c',
                    \ s:match_base_priority+2)
        if exists('b:_neomake_bufname_match_id')
            silent! call matchdelete(b:_neomake_bufname_match_id)
        endif
        let b:_neomake_bufname_match_id = matchadd('neomakeBufferName',
                    \ '.*\%<'.(maker_width + 1).'c',
                    \ s:match_base_priority+3)
    endif

    augroup neomake_qf
        autocmd! * <buffer>
        autocmd CursorMoved <buffer> call s:cursor_moved()
    augroup END

    if is_loclist
        let bufname = bufname(src_buf)
        if empty(bufname)
            let bufname = 'buf:'.src_buf
        else
            let bufname = pathshorten(bufname)
        endif
        let w:quickfix_title = printf('Neomake[file]: %s (%s)',
                    \ bufname, join(makers, ', '))
    else
        let w:quickfix_title = 'Neomake[project]: '.join(makers, ', ')
    endif
endfunction
