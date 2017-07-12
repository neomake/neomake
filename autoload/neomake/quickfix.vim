" vim: ts=4 sw=4 et
scriptencoding utf-8

let s:maker_match_id = 997
let s:gutter_match_id = 998
let s:cursor_match_id = 999
let s:is_enabled = 0


function! neomake#quickfix#enable() abort
    let s:is_enabled = 1
    augroup neomake_qf
        autocmd!
        autocmd FileType qf call neomake#quickfix#FormatQuickfix()
    augroup END
endfunction


function! neomake#quickfix#disable() abort
    let s:is_enabled = 0
endfunction


function! neomake#quickfix#is_enabled() abort
    return s:is_enabled
endfunction


function! s:cursor_moved() abort
    if b:neomake_start_col
        if col('.') <= b:neomake_start_col + 1
            call cursor(line('.'), b:neomake_start_col + 2)
        endif

        silent! call matchdelete(s:cursor_match_id)
        if exists('*matchaddpos')
            call matchaddpos('neomakeCursorListNr',
                        \ [[line('.'), (b:neomake_start_col - b:neomake_number_len) + 2, b:neomake_number_len]],
                        \ s:cursor_match_id,
                        \ s:cursor_match_id)
        else
            call matchadd('neomakeCursorListNr',
                        \  '\%' . line('.') . 'c'
                        \. '\%' . ((b:neomake_start_col - b:neomake_number_len) + 2) . 'c'
                        \. '.\{' . b:neomake_number_len . '}',
                        \ s:cursor_match_id, s:cursor_match_id)
        endif
    endif
endfunction


function! s:reset(buf) abort
    call neomake#signs#Clean(a:buf, 'file')
    silent! call matchdelete(s:maker_match_id)
    silent! call matchdelete(s:gutter_match_id)
    silent! call matchdelete(s:cursor_match_id)
endfunction


function! neomake#quickfix#set_syntax(names) abort
    runtime! syntax/neomake/qf.vim
    for name in a:names
        execute 'runtime! syntax/neomake/'.name.'.vim '
                    \  . 'syntax/neomake/'.name.'/*.vim'
    endfor
endfunction


function! neomake#quickfix#FormatQuickfix() abort
    if !s:is_enabled || &filetype !=# 'qf'
        if exists('b:neomake_qf')
            call s:reset(bufnr('%'))
            unlet! b:neomake_qf
            augroup neomake_qf
                autocmd! * <buffer>
            augroup END
        endif
        return
    endif

    let buf = bufnr('%')
    call s:reset(buf)

    let src_buf = 0
    let loclist = 1
    let qflist = getloclist(0)
    if empty(qflist)
        let loclist = 0
        let qflist = getqflist()
    endif

    if empty(qflist) || qflist[0].text !~# '\<nmcfg:{.*}$'
        set syntax=qf
        return
    endif

    if loclist
        let b:neomake_qf = 'file'
        let src_buf = qflist[0].bufnr
    else
        let b:neomake_qf = 'project'
    endif

    let ul = &l:undolevels
    setlocal modifiable nonumber undolevels=-1
    silent % delete _

    let lines = []
    let signs = []
    let i = 0
    let lnum_width = 0
    let col_width = 0
    let maker_width = 0
    let maker = {}
    let makers = []

    for item in qflist
        let config = matchstr(item.text, '\<nmcfg:\zs{.*}$')
        if !empty(config)
            let maker = eval(config)
            if index(makers, maker.name) == -1
                call add(makers, maker.name)
            endif
            let item.text = matchstr(item.text, '.*\ze\<nmcfg:')
        endif

        let item.maker_name = get(maker, 'short', '????')
        let maker_width = max([len(item.maker_name), maker_width])

        if item.lnum
            let lnum_width = max([len(item.lnum), lnum_width])
            let col_width = max([len(item.col), col_width])
        endif

        let i += 1
    endfor

    let syntax = makers
    if src_buf
        for ft in split(neomake#compat#getbufvar(src_buf, '&filetype', ''), '\.')
            if !empty(ft) && index(syntax, ft) == -1
                call add(syntax, ft)
            endif
        endfor
    endif
    if !empty(syntax)
        call neomake#quickfix#set_syntax(syntax)
    endif

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
    let buffers = neomake#compat#uniq(sort(map(copy(qflist), 'v:val.bufnr')))
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
        if !empty(buffer_names)
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

    call setline(1, lines)
    let &l:undolevels = ul
    setlocal nomodifiable nomodified

    if exists('+breakindent')
        " Keeps the text aligned with the fake gutter.
        setlocal breakindent linebreak
        let &breakindentopt = 'shift:'.(b:neomake_start_col + 1)
    endif

    call neomake#signs#PlaceSigns(buf, signs, 'file')

    if b:neomake_start_col
        call matchadd('neomakeMakerName',
                    \ '.*\%<'.(maker_width + 1).'c',
                    \ s:maker_match_id,
                    \ s:maker_match_id)
        call matchadd('neomakeListNr',
                    \ '\%>'.(maker_width).'c'
                    \ .'.*\%<'.(b:neomake_start_col + 2).'c',
                    \ s:gutter_match_id,
                    \ s:gutter_match_id)
    endif

    augroup neomake_qf
        autocmd! * <buffer>
        autocmd CursorMoved <buffer> call s:cursor_moved()
    augroup END

    if loclist
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
