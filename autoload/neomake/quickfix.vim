" vim: ts=4 sw=4 et
scriptencoding utf-8

let s:maker_match_id = 997
let s:gutter_match_id = 998
let s:cursor_match_id = 999


function! neomake#quickfix#enable() abort
    augroup neomake_qf
        autocmd!
        autocmd FileType qf call neomake#quickfix#FormatLocList()
    augroup END
endfunction


function! s:cursor_moved() abort
    if b:neomake_start_col
        if col('.') <= b:neomake_start_col + 1
            call cursor(line('.'), b:neomake_start_col + 2)
        endif

        silent! call matchdelete(s:cursor_match_id)
        call matchaddpos('neomakeCursorListNr',
                    \ [[line('.'), (b:neomake_start_col - b:neomake_number_len) + 2, b:neomake_number_len]],
                    \ s:cursor_match_id,
                    \ s:cursor_match_id)
    endif
endfunction


function! neomake#quickfix#FormatLocList() abort
    if &filetype != 'qf'
        return
    endif

    let loclist = getloclist(0)
    if empty(loclist)
        return
    endif

    let buf = bufnr('%')
    call neomake#signs#Reset(buf, 'file')

    let ul = &l:undolevels
    setlocal modifiable nonumber undolevels=-1
    silent % delete _

    let lines = []
    let signs = []
    let i = 1
    let lnum_width = 0
    let col_width = 0
    let maker_width = 0
    let src_buf = loclist[0].bufnr

    " XXX This will be blank sometimes.  Can only reproduce when using the
    " flake8 maker and if the location list is already open.
    let neomake_entries = deepcopy(neomake#GetErrors(src_buf))

    for item in loclist
        let maker_name = ''
        if item.lnum
            let entries = get(neomake_entries, item.lnum,
                        \ [{'maker_name': 'unknown'}])
            if !empty(entries)
                let entry = remove(entries, 0)
                let maker_name = entry.maker_name
                let maker_width = max([len(maker_name), maker_width])
            endif
        endif

        let item.maker_name = maker_name

        if item.lnum
            let lnum_width = max([len(item.lnum), lnum_width])
            let col_width = max([len(item.col), col_width])
        endif
    endfor

    if maker_width + lnum_width + col_width > 0
        let b:neomake_start_col = maker_width + lnum_width + col_width + 2
        let b:neomake_number_len = lnum_width + col_width + 2
        let blank_col = repeat(' ', lnum_width + col_width + 1)
    else
        let b:neomake_start_col = 0
        let b:neomake_number_len = 0
        let blank_col = ''
    endif

    let i = 1
    for item in loclist
        if item.lnum
            call add(signs, {'lnum': i, 'bufnr': buf, 'type': item.type})
        endif
        let i += 1

        if !item.lnum
            call add(lines, printf('%*s %s %s',
                        \ maker_width, item.maker_name,
                        \ blank_col, item.text))
        else
            call add(lines, printf('%*s %*s:%*s %s',
                        \ maker_width, item.maker_name,
                        \ lnum_width, item.lnum,
                        \ col_width, item.col ? item.col : '-',
                        \ item.text))
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

    for item in signs
        call neomake#signs#PlaceSign(item, 'file')
    endfor

    runtime! syntax/neomake/qf.vim
    execute 'runtime! syntax/neomake/'.getbufvar(src_buf, '&filetype').'.vim'

    call clearmatches()

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

    let w:quickfix_title = printf('Neomake: %s', bufname(src_buf))
endfunction
