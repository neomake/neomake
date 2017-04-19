function! neomake#makers#ft#rust#EnabledMakers() abort
    return ['cargo']
endfunction

function! neomake#makers#ft#rust#rustc() abort
    return {
        \ 'errorformat':
            \ '%-Gerror: aborting due to previous error,'.
            \ '%-Gerror: aborting due to %\\d%\\+ previous errors,'.
            \ '%-Gerror: Could not compile `%s`.,'.
            \ '%Eerror[E%n]: %m,'.
            \ '%Eerror: %m,'.
            \ '%Wwarning: %m,'.
            \ '%Inote: %m,'.
            \ '%-Z\ %#-->\ %f:%l:%c,'.
            \ '%G\ %#\= %*[^:]: %m,'.
            \ '%G\ %#|\ %#%\\^%\\+ %m,'.
            \ '%I%>help:\ %#%m,'.
            \ '%Z\ %#%m,'.
            \ '%-G%s',
        \ }
endfunction

function! neomake#makers#ft#rust#cargo() abort
    let maker_command = get(b:, 'neomake_rust_cargo_command',
                \ get(g:, 'neomake_rust_cargo_command', ['check']))
    return {
        \ 'args': maker_command + ['--message-format=json', '--quiet'],
        \ 'append_file': 0,
        \ 'errorformat':
            \ '[%t%n] "%f" %l:%v %m,'.
            \ '[%t] "%f" %l:%v %m',
        \ 'process_output': function('neomake#makers#ft#rust#CargoProcessOutput'),
        \ }
endfunction

function! neomake#makers#ft#rust#CargoProcessOutput(context) abort
    let errors = []
    for line in a:context['output']
        if line[0] !=# '{'
            continue
        endif

        let decoded = neomake#utils#JSONdecode(line)
        let data = get(decoded, 'message', -1)
        if type(data) != type({}) || empty(data['spans'])
            continue
        endif

        let error = {'maker_name': 'cargo'}
        let code_dict = get(data, 'code', -1)
        if code_dict is g:neomake#compat#json_null
            if get(data, 'level', '') ==# 'warning'
                let error.type = 'W'
            else
                let error.type = 'E'
            endif
        else
            let error.type = code_dict['code'][0]
            let error.nr = code_dict['code'][1:]
        endif

        let span = data.spans[0]
        let expanded = 0
        let has_expansion = type(span.expansion) == type({})
                    \ && type(span.expansion.span) == type({})
                    \ && type(span.expansion.def_site_span) == type({})

        if span.file_name =~# '^<.*>$' && has_expansion
            let expanded = 1
            call neomake#makers#ft#rust#FillErrorFromSpan(error,
                        \ span.expansion.span)
        else
            call neomake#makers#ft#rust#FillErrorFromSpan(error, span)
        endif

        let error.text = data.message
        let detail = span.label
        let children = data.children
        if type(detail) == type('') && !empty(detail)
            let error.text = error.text . ': ' . detail
        elseif !empty(children) && has_key(children[0], 'message')
            let error.text = error.text . '. ' . children[0].message
        endif

        call add(errors, error)

        if has_expansion && !expanded
            let error = copy(error)
            call neomake#makers#ft#rust#FillErrorFromSpan(error,
                        \ span.expansion.span)
            call add(errors, error)
        endif

        for child in children[1:]
            if !has_key(child, 'message')
                continue
            endif

            let info = deepcopy(error)
            let info.type = 'I'
            let info.text = child.message
            call neomake#utils#CompressWhitespace(info)
            if has_key(child, 'rendered')
                        \ && !(child.rendered is g:neomake#compat#json_null)
                let info.text = info.text . ': ' . child.rendered
            endif

            if len(child.spans)
                let span = child.spans[0]
                if span.file_name =~# '^<.*>$'
                            \ && type(span.expansion) == type({})
                            \ && type(span.expansion.span) == type({})
                            \ && type(span.expansion.def_site_span) == type({})
                    call neomake#makers#ft#rust#FillErrorFromSpan(info,
                                \ span.expansion.span)
                else
                    call neomake#makers#ft#rust#FillErrorFromSpan(info, span)
                endif
                let detail = span.label
                if type(detail) == type('') && len(detail)
                    let info.text = info.text . ': ' . detail
                endif
            endif

            call add(errors, info)
        endfor
    endfor
    return errors
endfunction

function! neomake#makers#ft#rust#FillErrorFromSpan(error, span) abort
    let a:error.filename = a:span.file_name
    let a:error.col = a:span.column_start
    let a:error.lnum = a:span.line_start
    let a:error.length = a:span.byte_end - a:span.byte_start
endfunction

" vim: ts=4 sw=4 et
