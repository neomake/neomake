" vim: ts=4 sw=4 et

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
    return {
        \ 'args': ['test', '--no-run', '--message-format=json', '--quiet'],
        \ 'append_file': 0,
        \ 'errorformat':
            \ '[%t%n] "%f" %l:%v %m,'.
            \ '[%t] "%f" %l:%v %m',
        \ 'mapexpr': 'neomake#makers#ft#rust#CargoParseJSON(v:val)',
        \ }
endfunction

function! neomake#makers#ft#rust#CargoParseJSON(val) abort
    let l:text = a:val
    if l:text[0] ==# '{'
        if exists('*json_decode')
            let l:decoded = json_decode(l:text)
        else
            python import json
            let l:decoded = pyeval("json.loads(vim.eval('l:text'))")
        endif
        let l:data = get(l:decoded, 'message', v:null)
        if type(l:data) == type({})
            echom 'hoooi'
            let l:code = get(l:data, 'code', v:null)

            if type(l:code) == type({})
                let l:code = l:code['code']
            else
                if get(l:data, 'level', '') ==# 'warning'
                    let l:code = 'W'
                else
                    let l:code = 'E'
                endif
            endif
            let l:message = l:data['message']
            let l:span = l:data['spans'][0]
            let l:detail = l:span['label']
            let l:col = l:span['column_start']
            let l:row = l:span['line_start']
            let l:file = l:span['file_name']
            let l:error = '[' . l:code . '] "' . l:file . '" ' .
                        \ l:row . ':' .l:col .  ' ' .
                        \ l:message
            if detail
                let l:error = l:error . ': ' . l:detail
            endif
            return l:error
        endif
    endif
endfunction
